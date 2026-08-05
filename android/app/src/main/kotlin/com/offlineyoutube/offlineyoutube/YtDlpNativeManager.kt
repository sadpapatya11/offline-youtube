package com.offlineyoutube.offlineyoutube

import android.content.Context
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDLResponse
import com.yausername.youtubedl_android.mapper.VideoInfo
import com.yausername.ffmpeg.FFmpeg
import com.yausername.aria2c.Aria2c
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.ConcurrentHashMap

object YtDlpNativeManager {
    private const val TAG = "YtDlpNativeManager"
    private var isInitialized = false
    private val activeTasks = ConcurrentHashMap<String, String>() // taskId -> processId or url

    fun init(context: Context) {
        if (isInitialized) return
        try {
            YoutubeDL.getInstance().init(context.applicationContext)
            try {
                FFmpeg.getInstance().init(context.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "FFmpeg init warning: ${e.message}")
            }
            try {
                Aria2c.getInstance().init(context.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "Aria2c init warning: ${e.message}")
            }
            isInitialized = true
            Log.i(TAG, "YtDlpNativeManager initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize YoutubeDL: ${e.message}", e)
        }
    }

    suspend fun updateYtDlp(context: Context): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext, YoutubeDL.UpdateChannel._STABLE)
            Log.i(TAG, "yt-dlp update status: $status")
            true
        } catch (e: Exception) {
            Log.e(TAG, "yt-dlp update failed: ${e.message}", e)
            false
        }
    }

    suspend fun fetchMetadata(url: String): Map<String, Any?> = withContext(Dispatchers.IO) {
        try {
            val isPlaylist = url.contains("list=") || url.contains("/playlist") || url.contains("/@") || url.contains("/channel/")
            val request = YoutubeDLRequest(url).apply {
                if (isPlaylist) {
                    addOption("--flat-playlist")
                    addOption("--playlist-reverse")
                } else {
                    addOption("--no-playlist")
                }
                addOption("--dump-single-json")
            }
            val videoInfo: VideoInfo = YoutubeDL.getInstance().getInfo(request)
            return@withContext mapOf(
                "id" to (videoInfo.id ?: ""),
                "title" to (videoInfo.title ?: if (isPlaylist) "Oynatma Listesi" else "Bilinmeyen Video"),
                "duration" to (videoInfo.duration ?: 0),
                "thumbnail" to (videoInfo.thumbnail ?: ""),
                "uploader" to (videoInfo.uploader ?: ""),
                "description" to (videoInfo.description ?: ""),
                "fileSize" to (videoInfo.fileSize ?: 0L),
                "ext" to (videoInfo.ext ?: "mp4"),
                "isPlaylist" to isPlaylist,
                "url" to url
            )
        } catch (e: Exception) {
            Log.e(TAG, "Fetch metadata failed for $url: ${e.message}", e)
            throw e
        }
    }

    fun startDownload(
        taskId: String,
        url: String,
        outputDir: File,
        onProgress: (Float, Long, String) -> Unit,
        onComplete: (String) -> Unit,
        onError: (Exception) -> Unit
    ) {
        try {
            if (!outputDir.exists()) {
                outputDir.mkdirs()
            }
            // Add .nomedia file to keep gallery clean
            val noMedia = File(outputDir, ".nomedia")
            if (!noMedia.exists()) {
                noMedia.createNewFile()
            }

            activeTasks[taskId] = taskId

            val isPlaylist = url.contains("list=") || url.contains("/playlist") || url.contains("/@") || url.contains("/channel/")

            val request = YoutubeDLRequest(url).apply {
                addOption("-o", "${outputDir.absolutePath}/%(title)s.%(ext)s")
                addOption("-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best")
                addOption("--no-mtime")
                addOption("--continue")
                addOption("--ignore-errors") // Skip unavailable/private videos without failing the batch
                if (isPlaylist) {
                    addOption("--yes-playlist")
                    addOption("--playlist-reverse") // Download newest / latest added items first
                } else {
                    addOption("--no-playlist")
                }
            }

            val response: YoutubeDLResponse = YoutubeDL.getInstance().execute(
                request,
                taskId
            ) { progress, etaInSeconds, line ->
                val speed = parseSpeed(line)
                onProgress(progress, etaInSeconds, speed)
            }

            activeTasks.remove(taskId)
            onComplete(response.out ?: "İndirme Tamamlandı")
        } catch (e: Exception) {
            activeTasks.remove(taskId)
            Log.e(TAG, "Download error for task $taskId: ${e.message}", e)
            onError(e)
        }
    }

    fun stopDownload(taskId: String) {
        try {
            YoutubeDL.getInstance().destroyProcessById(taskId)
            activeTasks.remove(taskId)
            Log.i(TAG, "Task $taskId destroyed/stopped successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop task $taskId: ${e.message}", e)
        }
    }

    private fun parseSpeed(line: String?): String {
        if (line == null) return ""
        val regex = "at\\s+([0-9.]+\\s*[kKMmGg]?[iI]?[bB]/s)".toRegex()
        val match = regex.find(line)
        return match?.groupValues?.get(1) ?: ""
    }
}
