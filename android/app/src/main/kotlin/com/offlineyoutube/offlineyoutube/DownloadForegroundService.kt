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
import kotlin.math.abs

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
        var eventCallback: ((Map<String, Any?>) -> Unit)? = null

        fun getNotificationId(taskId: String): Int {
            return (abs(taskId.hashCode()) % 100000) + 1000
        }
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
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopAllAndSelf()
            return START_NOT_STICKY
        }

        val taskId = intent?.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
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

        val job = serviceScope.launch {
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
                    val now = System.currentTimeMillis()
                    if (progress >= 100f || now - lastNotificationTime >= 1000L) {
                        lastNotificationTime = now
                        val sizeInfo = if (totalSize.isNotEmpty()) " [$totalSize]" else ""
                        val notification = buildNotification(
                            title = title,
                            content = "$speed$sizeInfo - Kalan: ${formatEta(eta)}",
                            progress = progress.toInt(),
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
        activeDownloadJobs[taskId] = job
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
                delay(45000L) // 45 saniye bekle
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
                wakeLock?.acquire(2 * 60 * 60 * 1000L) // 2 hours max safety
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

    private fun releaseLocksIfIdle() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release error: ${e.message}")
        }
        try {
            wifiLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "WifiLock release error: ${e.message}")
        }
    }

    private fun formatEta(seconds: Long): String {
        if (seconds <= 0) return "--"
        val m = seconds / 60
        val s = seconds % 60
        return String.format("%02d:%02d", m, s)
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceJob.cancel()
        releaseLocksIfIdle()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
