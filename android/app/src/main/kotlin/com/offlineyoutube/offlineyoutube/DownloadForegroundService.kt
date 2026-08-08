package com.offlineyoutube.offlineyoutube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap

class DownloadForegroundService : Service() {

    companion object {
        private const val TAG = "DownloadForegroundService"
        const val CHANNEL_ID = "offlineyoutube_downloads"
        const val CHANNEL_NAME = "İndirme İşlemleri"
        const val SERVICE_NOTIFICATION_ID = 999

        const val ACTION_START = "com.offlineyoutube.START_DOWNLOAD"
        const val ACTION_PAUSE = "com.offlineyoutube.PAUSE_DOWNLOAD"
        const val ACTION_RESUME = "com.offlineyoutube.RESUME_DOWNLOAD"
        const val ACTION_CANCEL = "com.offlineyoutube.CANCEL_DOWNLOAD"
        const val ACTION_STOP_SERVICE = "com.offlineyoutube.STOP_SERVICE"

        const val EXTRA_TASK_ID = "extra_task_id"
        const val EXTRA_URL = "extra_url"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_OUTPUT_PATH = "extra_output_path"

        // Event listener for Flutter
        // FIX(visibility): IO thread'lerinde okunuyor, MainActivity main
        // thread'inde yazılıyor — @Volatile olmadan güncel olmayan null okunup
        // event'ler kaybolabiliyordu.
        @Volatile
        var eventCallback: ((Map<String, Any?>) -> Unit)? = null
    }

    private val serviceJob = Job()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val activeDownloadJobs = ConcurrentHashMap<String, Job>()
    private val taskTitles = ConcurrentHashMap<String, String>()
    private val taskUrls = ConcurrentHashMap<String, String>()
    private val taskOutputs = ConcurrentHashMap<String, String>()
    private var idleTimeoutJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        ThermalManager.init(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopAllAndSelf()
            return START_NOT_STICKY
        }

        // FIX(restart): Sistem servisi öldürüp (memory pressure) START_STICKY ile
        // yeniden başlattığında intent null olabilir. O noktada startForeground()
        // çağrılmadan dönmek RemoteServiceException'a ("did not then call
        // startForeground") yol açıyor ve uygulama çöküyordu. Burada servisi
        // tekrar foreground yap; 30 sn içinde Flutter bağlanıp kuyruğu devralır,
        // olmazsa idle timeout servisi kapatır.
        if (intent == null || intent.getStringExtra(EXTRA_TASK_ID).isNullOrEmpty()) {
            startInForeground(
                buildNotification(
                    title = "Offline YouTube",
                    content = "İndirme sürdürülüyor...",
                    progress = 0,
                    indeterminate = true
                )
            )
            checkGracefulStop()
            return START_STICKY
        }

        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Video"
        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: ""

        when (action) {
            ACTION_START, ACTION_RESUME -> {
                // Cancel pending idle shutdown timer
                idleTimeoutJob?.cancel()
                idleTimeoutJob = null

                taskTitles[taskId] = title
                taskUrls[taskId] = url
                taskOutputs[taskId] = outputPath
                
                startInForeground(
                    buildNotification(
                        title = "Offline YouTube",
                        content = "İndirme başlatılıyor: $title",
                        progress = 0,
                        indeterminate = true
                    )
                )
                startDownloadTask(taskId, url, outputPath, title)
            }
            ACTION_PAUSE -> {
                pauseDownloadTask(taskId)
            }
            ACTION_CANCEL -> {
                cancelDownloadTask(taskId)
            }
        }

        return START_STICKY
    }

    private fun startInForeground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    SERVICE_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(SERVICE_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground error: ${e.message}", e)
            try {
                startForeground(SERVICE_NOTIFICATION_ID, notification)
            } catch (ex: Exception) {
                Log.e(TAG, "Fallback startForeground error: ${ex.message}", ex)
            }
        }
    }

    private fun startDownloadTask(taskId: String, url: String, outputPath: String, title: String) {
        acquireLocksIfNeeded()
        val outputDir = if (outputPath.isNotEmpty()) File(outputPath) else File(getExternalFilesDir(null), "downloads")
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        var lastNotificationTime = 0L

        serviceScope.launch {
            // FIX(race): Görevi en başta kaydet. Önceden kayıt launch'tan SONRA
            // (main thread'de) yapılıyordu; çok hızlı başarısızlıkta onError
            // önce çalışıp checkGracefulStop() boş map gördüğü için idle timeout
            // hiç ateşlenmiyor, servis sonsuza dek foreground'da kalıyordu.
            activeDownloadJobs[taskId] = coroutineContext[Job] ?: Job()

            emitEvent(mapOf(
                "taskId" to taskId,
                "type" to "started",
                "progress" to 0.0f,
                "title" to title
            ))

            YtDlpNativeManager.startDownload(
                taskId = taskId,
                url = url,
                outputDir = outputDir,
                onProgress = { progress, eta, speed, totalSize, downloadedSize ->
                    // FIX(wakelock): 30 dk'lık timeout'lı wake lock uzun
                    // indirmelerde erken serbest kalıyordu; her progress'te
                    // tutulmuyorsa yeniden al (99%+ wifi lock bilinçli
                    // bırakıldıysa geri alma).
                    reAcquireLocksIfDropped(progress)

                    // If download is near completion / post-processing, release WifiLock early to cool RF modem
                    if (progress >= 99f) {
                        releaseWifiLockOnly()
                    }

                    val now = System.currentTimeMillis()
                    if (progress >= 100f || now - lastNotificationTime >= 1000L) {
                        lastNotificationTime = now
                        // FIX(percent): Bildirim metninde canlı yüzde + indirilen
                        // miktar göster — setProgress() yalnızca çubuk çizer,
                        // sayı metne yazılmazsa kullanıcı yüzdeyi göremez.
                        val pct = if (progress >= 100f) 100 else progress.toInt()
                        val sizeInfo = if (downloadedSize.isNotEmpty() && totalSize.isNotEmpty()) {
                            " [$downloadedSize / $totalSize]"
                        } else if (totalSize.isNotEmpty()) {
                            " [$totalSize]"
                        } else {
                            ""
                        }
                        val notification = buildNotification(
                            title = title,
                            content = "%$pct $speed$sizeInfo - Kalan: ${formatEta(eta)}",
                            progress = pct,
                            indeterminate = false
                        )
                        manager.notify(SERVICE_NOTIFICATION_ID, notification)
                    }

                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "progress",
                        "progress" to progress,
                        "eta" to eta,
                        "speed" to speed,
                        "totalSize" to totalSize,
                        "downloadedSize" to downloadedSize
                    ))
                },
                onComplete = { result ->
                    activeDownloadJobs.remove(taskId)
                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "completed",
                        "result" to result
                    ))
                    checkGracefulStop()
                },
                onError = { e ->
                    activeDownloadJobs.remove(taskId)
                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "error",
                        "error" to (e.message ?: "Bilinmeyen hata")
                    ))
                    checkGracefulStop()
                }
            )
        }
    }

    private fun pauseDownloadTask(taskId: String) {
        activeDownloadJobs[taskId]?.cancel()
        activeDownloadJobs.remove(taskId)
        YtDlpNativeManager.stopDownload(taskId)
        emitEvent(mapOf(
            "taskId" to taskId,
            "type" to "paused"
        ))
        checkGracefulStop()
    }

    private fun cancelDownloadTask(taskId: String) {
        activeDownloadJobs[taskId]?.cancel()
        activeDownloadJobs.remove(taskId)
        YtDlpNativeManager.stopDownload(taskId)
        taskTitles.remove(taskId)
        taskUrls.remove(taskId)
        taskOutputs.remove(taskId)
        emitEvent(mapOf(
            "taskId" to taskId,
            "type" to "cancelled"
        ))
        checkGracefulStop()
    }

    private fun checkGracefulStop() {
        if (activeDownloadJobs.isEmpty()) {
            releaseLocksIfIdle()
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val waitingNotification = buildNotification(
                title = "Offline YouTube",
                content = "Sıradaki video hazırlanıyor...",
                progress = 0,
                indeterminate = true
            )
            manager.notify(SERVICE_NOTIFICATION_ID, waitingNotification)

            idleTimeoutJob?.cancel()
            idleTimeoutJob = serviceScope.launch {
                delay(30000L) // 30 saniye bekle
                if (activeDownloadJobs.isEmpty()) {
                    Log.i(TAG, "No active downloads within grace period. Stopping foreground service.")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
    }

    private fun stopAllAndSelf() {
        idleTimeoutJob?.cancel()
        idleTimeoutJob = null
        for ((taskId, job) in activeDownloadJobs) {
            job.cancel()
            YtDlpNativeManager.stopDownload(taskId)
        }
        activeDownloadJobs.clear()
        releaseLocksIfIdle()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun emitEvent(data: Map<String, Any?>) {
        try {
            eventCallback?.invoke(data)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to emit event: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "offlineyoutube arkaplan indirme bildirimleri"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(
        title: String,
        content: String,
        progress: Int,
        indeterminate: Boolean
    ): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, indeterminate)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun acquireLocksIfNeeded() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "offlineyoutube:download_wakelock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(30 * 60 * 1000L) // 30 mins safety max
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock acquire error: ${e.message}")
        }

        try {
            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL, "offlineyoutube:download_wifilock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld != true) {
                wifiLock?.acquire()
            }
        } catch (e: Exception) {
            Log.e(TAG, "WifiLock acquire error: ${e.message}")
        }
    }

    private fun releaseWifiLockOnly() {
        try {
            wifiLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.i(TAG, "WifiLock released early for modem thermal cooling.")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "WifiLock release error: ${e.message}")
        }
    }

    // FIX(wakelock): acquireLocksIfNeeded() yalnızca yeni görev başlarken
    // çağrılıyordu; 30 dk'lık timeout sonrası kilitsiz geçen uzun indirmeler
    // Doze altında kesilebiliyordu. Progress callback bu metodu her çağrışta
    // düşen kilitleri yeniden alır.
    private fun reAcquireLocksIfDropped(progress: Float) {
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire()
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock re-acquire error: ${e.message}")
        }
        // WifiLock 99%+ iken termal soğutma için bilinçli bırakıldı; altına
        // düşüldüyse geri al.
        if (progress < 99f && wifiLock?.isHeld != true) {
            try {
                wifiLock?.acquire()
            } catch (e: Exception) {
                Log.e(TAG, "WifiLock re-acquire error: ${e.message}")
            }
        }
    }

    private fun releaseLocksIfIdle() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release error: ${e.message}")
        }
        releaseWifiLockOnly()
    }

    private fun formatEta(seconds: Long): String {
        if (seconds <= 0) return "--"
        val m = seconds / 60
        val s = seconds % 60
        return String.format("%02d:%02d", m, s)
    }

    override fun onDestroy() {
        // FIX(orphan): Aktif yt-dlp süreçlerini durdur. Önceden yalnızca job
        // iptal ediliyordu; job.cancel() bloklayan YoutubeDL.execute() çağrısını
        // kesemiyor, python çocuk süreçleri servis öldükten sonra bile bildirimsiz
        // ve kilitsiz indirmeye devam ediyordu.
        for (taskId in activeDownloadJobs.keys) {
            try {
                YtDlpNativeManager.stopDownload(taskId)
            } catch (e: Exception) {
                Log.e(TAG, "stopDownload on destroy error: ${e.message}")
            }
        }
        activeDownloadJobs.clear()
        serviceJob.cancel()
        releaseLocksIfIdle()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
