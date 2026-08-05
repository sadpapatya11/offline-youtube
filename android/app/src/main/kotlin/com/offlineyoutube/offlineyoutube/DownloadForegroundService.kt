package com.offlineyoutube.offlineyoutube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
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
    private val activeDownloadJobs = ConcurrentHashMap<String, Job>()
    private val taskTitles = ConcurrentHashMap<String, String>()
    private val taskUrls = ConcurrentHashMap<String, String>()
    private val taskOutputs = ConcurrentHashMap<String, String>()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val taskId = intent?.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Video"
        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: ""

        when (action) {
            ACTION_START, ACTION_RESUME -> {
                taskTitles[taskId] = title
                taskUrls[taskId] = url
                taskOutputs[taskId] = outputPath
                
                // Start foreground service with persistent summary
                startForeground(
                    SERVICE_NOTIFICATION_ID,
                    buildNotification(
                        title = "Offline YouTube",
                        content = "İndirmeler yürütülüyor...",
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

    private fun startDownloadTask(taskId: String, url: String, outputPath: String, title: String) {
        val outputDir = if (outputPath.isNotEmpty()) File(outputPath) else File(getExternalFilesDir(null), "downloads")
        val notifId = getNotificationId(taskId)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

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
                onProgress = { progress, eta, speed ->
                    val notification = buildNotification(
                        title = title,
                        content = "$speed - Kalan: ${formatEta(eta)}",
                        progress = progress.toInt(),
                        indeterminate = false
                    )
                    manager.notify(notifId, notification)

                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "progress",
                        "progress" to progress,
                        "eta" to eta,
                        "speed" to speed
                    ))
                },
                onComplete = { result ->
                    activeDownloadJobs.remove(taskId)
                    manager.cancel(notifId)
                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "completed",
                        "result" to result
                    ))
                    checkStopSelf()
                },
                onError = { e ->
                    activeDownloadJobs.remove(taskId)
                    manager.cancel(notifId)
                    emitEvent(mapOf(
                        "taskId" to taskId,
                        "type" to "error",
                        "error" to (e.message ?: "Bilinmeyen hata")
                    ))
                    checkStopSelf()
                }
            )
        }
        activeDownloadJobs[taskId] = job
    }

    private fun pauseDownloadTask(taskId: String) {
        val notifId = getNotificationId(taskId)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notifId)

        activeDownloadJobs[taskId]?.cancel()
        activeDownloadJobs.remove(taskId)
        YtDlpNativeManager.stopDownload(taskId)
        emitEvent(mapOf(
            "taskId" to taskId,
            "type" to "paused"
        ))
        checkStopSelf()
    }

    private fun cancelDownloadTask(taskId: String) {
        val notifId = getNotificationId(taskId)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notifId)

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
        checkStopSelf()
    }

    private fun checkStopSelf() {
        if (activeDownloadJobs.isEmpty()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
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

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "offlineyoutube:download_wakelock").apply {
            acquire(24 * 60 * 60 * 1000L) // 24 hours max
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
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
