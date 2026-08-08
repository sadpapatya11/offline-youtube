package com.offlineyoutube.offlineyoutube

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.offlineyoutube/downloader"
    private val EVENT_CHANNEL = "com.offlineyoutube/download_events"

    private var eventSink: EventChannel.EventSink? = null
    private val activityScope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize YoutubeDL
        YtDlpNativeManager.init(this)

        // Event Channel Setup
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    DownloadForegroundService.eventCallback = { data ->
                        runOnUiThread {
                            eventSink?.success(data)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    DownloadForegroundService.eventCallback = null
                }
            }
        )

        // Method Channel Setup
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    YtDlpNativeManager.init(this)
                    result.success(true)
                }

                "updateYtDlp" -> {
                    activityScope.launch {
                        val success = YtDlpNativeManager.updateYtDlp(this@MainActivity)
                        result.success(success)
                    }
                }

                "fetchMetadata" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_URL", "URL boş olamaz", null)
                        return@setMethodCallHandler
                    }
                    activityScope.launch {
                        try {
                            val data = YtDlpNativeManager.fetchMetadata(url)
                            result.success(data)
                        } catch (e: Exception) {
                            result.error("METADATA_ERROR", e.message ?: "Video bilgisi alınamadı", null)
                        }
                    }
                }

                "fetchPlaylistEntries" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_URL", "URL boş olamaz", null)
                        return@setMethodCallHandler
                    }
                    activityScope.launch {
                        try {
                            val list = YtDlpNativeManager.fetchPlaylistEntries(url)
                            result.success(list)
                        } catch (e: Exception) {
                            result.error("PLAYLIST_ERROR", e.message ?: "Oynatma listesi bilgisi alınamadı", null)
                        }
                    }
                }

                "startDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: "Video"
                    val outputPath = call.argument<String>("outputPath") ?: ""

                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_START
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                        putExtra(DownloadForegroundService.EXTRA_URL, url)
                        putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        putExtra(DownloadForegroundService.EXTRA_OUTPUT_PATH, outputPath)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "pauseDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_PAUSE
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                    }
                    startService(intent)
                    result.success(true)
                }

                "resumeDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: "Video"
                    val outputPath = call.argument<String>("outputPath") ?: ""

                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_RESUME
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                        putExtra(DownloadForegroundService.EXTRA_URL, url)
                        putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        putExtra(DownloadForegroundService.EXTRA_OUTPUT_PATH, outputPath)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_CANCEL
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                    }
                    startService(intent)
                    result.success(true)
                }

                "stopDownloadService" -> {
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_STOP_SERVICE
                    }
                    startService(intent)
                    result.success(true)
                }

                "hasAllFilesPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }

                "requestAllFilesPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val fallbackIntent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            startActivity(fallbackIntent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }

                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (ex: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }

                "getFolderSize" -> {
                    val path = call.argument<String>("path") ?: ""
                    activityScope.launch {
                        val size = withContext(Dispatchers.IO) {
                            calculateFolderSize(File(path))
                        }
                        result.success(size)
                    }
                }

                "getThermalDiagnostics" -> {
                    result.success(ThermalManager.getDiagnosticsReport())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun calculateFolderSize(file: File): Long {
        if (!file.exists()) return 0L
        if (file.isFile) return file.length()
        var length = 0L
        val files = file.listFiles() ?: return 0L
        for (f in files) {
            length += if (f.isFile) f.length() else calculateFolderSize(f)
        }
        return length
    }
}
