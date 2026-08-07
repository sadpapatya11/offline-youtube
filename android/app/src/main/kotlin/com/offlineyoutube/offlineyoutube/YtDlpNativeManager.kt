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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

object YtDlpNativeManager {
    private const val TAG = "YtDlpNativeManager"
    private var isInitialized = false
    private val activeTasks = ConcurrentHashMap<String, String>() // taskId -> taskId
    private val intentionallyStoppedTasks = ConcurrentHashMap.newKeySet<String>()

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

            // Auto-update yt-dlp binary in background
            kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                try {
                    YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext, YoutubeDL.UpdateChannel._STABLE)
                    Log.i(TAG, "yt-dlp auto-updated successfully")
                } catch (e: Exception) {
                    Log.w(TAG, "Background yt-dlp update skipped: ${e.message}")
                }
            }
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
            val isPlaylist = isPlaylistUrl(url)
            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--no-check-certificates")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                addOption("--extractor-args", "youtube:lang=tr")
                addOption("--geo-bypass-country", "TR")
                if (isPlaylist) {
                    addOption("--flat-playlist")
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

    suspend fun fetchPlaylistEntries(url: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        try {
            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--no-check-certificates")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                addOption("--extractor-args", "youtube:lang=tr")
                addOption("--geo-bypass-country", "TR")
                addOption("--flat-playlist")
                addOption("-J")
            }
            val response = YoutubeDL.getInstance().execute(request)
            val jsonStr = response.out
            val entries = mutableListOf<Map<String, Any?>>()

            if (!jsonStr.isNullOrEmpty()) {
                val jsonObj = org.json.JSONObject(jsonStr)
                if (jsonObj.has("entries") && !jsonObj.isNull("entries")) {
                    val rawArray = jsonObj.getJSONArray("entries")
                    for (i in 0 until rawArray.length()) {
                        val item = rawArray.optJSONObject(i) ?: continue
                        val itemId = item.optString("id", "").trim()
                        var itemTitle = item.optString("title", "").trim()
                        if (itemTitle.isEmpty() || itemTitle.equals("null", ignoreCase = true)) {
                            itemTitle = if (itemId.isNotEmpty()) "Video ($itemId)" else "Video ${i + 1}"
                        }

                        // Skip deleted/private/unavailable videos
                        val lowerTitle = itemTitle.lowercase()
                        if (lowerTitle.contains("[deleted") || lowerTitle.contains("[private") || lowerTitle.contains("[unavailable")) {
                            continue
                        }

                        val itemDuration = item.optInt("duration", 0)
                        var itemThumbnail = item.optString("thumbnail", "").trim()
                        if (itemThumbnail.equals("null", ignoreCase = true)) {
                            itemThumbnail = if (itemId.isNotEmpty()) "https://i.ytimg.com/vi/$itemId/hqdefault.jpg" else ""
                        }
                        var itemUploader = item.optString("uploader", "").trim()
                        if (itemUploader.equals("null", ignoreCase = true)) {
                            itemUploader = ""
                        }
                        val itemUploadDate = item.optString("upload_date", "").trim()
                        val itemUrl = if (itemId.isNotEmpty()) {
                            "https://www.youtube.com/watch?v=$itemId"
                        } else {
                            val u = item.optString("url", "").trim()
                            if (u.equals("null", ignoreCase = true)) "" else u
                        }

                        if (itemUrl.isNotEmpty()) {
                            entries.add(mapOf(
                                "id" to itemId,
                                "title" to itemTitle,
                                "duration" to itemDuration,
                                "thumbnail" to itemThumbnail,
                                "uploader" to itemUploader,
                                "url" to itemUrl,
                                "uploadDate" to itemUploadDate
                            ))
                        }
                    }
                } else {
                    val id = jsonObj.optString("id", "").trim()
                    var title = jsonObj.optString("title", "").trim()
                    if (title.isEmpty() || title.equals("null", ignoreCase = true)) {
                        title = if (id.isNotEmpty()) "Video ($id)" else "Video"
                    }
                    val duration = jsonObj.optInt("duration", 0)
                    var thumbnail = jsonObj.optString("thumbnail", "").trim()
                    if (thumbnail.equals("null", ignoreCase = true)) {
                        thumbnail = if (id.isNotEmpty()) "https://i.ytimg.com/vi/$id/hqdefault.jpg" else ""
                    }
                    var uploader = jsonObj.optString("uploader", "").trim()
                    if (uploader.equals("null", ignoreCase = true)) {
                        uploader = ""
                    }
                    val uploadDate = jsonObj.optString("upload_date", "").trim()

                    entries.add(mapOf(
                        "id" to id,
                        "title" to title,
                        "duration" to duration,
                        "thumbnail" to thumbnail,
                        "uploader" to uploader,
                        "url" to url,
                        "uploadDate" to uploadDate
                    ))
                }
            }

            // Sort entries: En son yayınlanan video (newest upload date) en başta olacak şekilde
            entries.sortWith(Comparator { a, b ->
                val dateA = a["uploadDate"] as? String ?: ""
                val dateB = b["uploadDate"] as? String ?: ""
                if (dateA.isNotEmpty() && dateB.isNotEmpty()) {
                    dateB.compareTo(dateA) // Descending: Newest first
                } else {
                    0
                }
            })

            return@withContext entries
        } catch (e: Exception) {
            Log.e(TAG, "Fetch playlist entries failed for $url: ${e.message}", e)
            throw e
        }
    }

    fun isPlaylistUrl(url: String): Boolean {
        return url.contains("list=") || url.contains("/playlist") || url.contains("/@") || url.contains("/channel/")
    }

    fun startDownload(
        taskId: String,
        url: String,
        outputDir: File,
        onProgress: (Float, Long, String, String, String) -> Unit,
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
            intentionallyStoppedTasks.remove(taskId)

            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                addOption("--extractor-args", "youtube:lang=tr")
                addOption("--geo-bypass-country", "TR")
                addOption("--write-thumbnail")
                addOption("--convert-thumbnails", "jpg")
                addOption("-o", "${outputDir.absolutePath}/%(title)s.%(ext)s")
                addOption("-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best")
                addOption("--no-mtime")
                addOption("--continue")
                addOption("--ignore-errors")
                addOption("--no-playlist") // Her video tek tek bağımsız indirilir
                // Türkçe Altyazı Desteği (Varsa Türkçe altyazı veya otomatik Türkçe çeviri indir)
                addOption("--write-subs")
                addOption("--write-auto-subs")
                addOption("--sub-lang", "tr,tr-orig,tr-TR,en")
                addOption("--sub-format", "vtt/srt/best")
                // Anti-Ban & Doğal Video İzleme Akışı
                addOption("--limit-rate", "3.5M") // ~3.5 MB/s doğal insan akış hızı
                addOption("--sleep-interval", "2") // İstekler arası 2 saniye dinlenme
                addOption("--retries", "10")
                addOption("--fragment-retries", "10")
            }

            var lastProgressEmitTime = 0L
            val response: YoutubeDLResponse = YoutubeDL.getInstance().execute(
                request,
                taskId
            ) { progress, etaInSeconds, line ->
                val now = System.currentTimeMillis()
                if (progress >= 100f || now - lastProgressEmitTime >= 500L) {
                    lastProgressEmitTime = now
                    val speed = parseSpeed(line)
                    val totalSize = parseTotalSize(line)
                    val downloadedSize = parseDownloadedSize(line)
                    onProgress(progress, etaInSeconds, speed, totalSize, downloadedSize)
                }
            }

            activeTasks.remove(taskId)
            onComplete(response.out ?: "İndirme Tamamlandı")
        } catch (e: Exception) {
            activeTasks.remove(taskId)
            if (intentionallyStoppedTasks.remove(taskId)) {
                Log.i(TAG, "Task $taskId was intentionally paused/stopped. Suppressing error callback.")
                return
            }
            Log.e(TAG, "Download error for task $taskId: ${e.message}", e)
            onError(e)
        }
    }

    fun stopDownload(taskId: String) {
        try {
            intentionallyStoppedTasks.add(taskId)
            YoutubeDL.getInstance().destroyProcessById(taskId)
            activeTasks.remove(taskId)
            Log.i(TAG, "Task $taskId destroyed/stopped intentionally")
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

    private fun parseTotalSize(line: String?): String {
        if (line == null) return ""
        val regex = "of\\s+~?\\s*([0-9.]+\\s*[kKMmGg]?[iI]?[bB])".toRegex()
        val match = regex.find(line)
        return match?.groupValues?.get(1) ?: ""
    }

    private fun parseDownloadedSize(line: String?): String {
        if (line == null) return ""
        val regex = "\\[download\\]\\s+([0-9.]+\\s*[kKMmGg]?[iI]?[bB])\\s+of".toRegex()
        val match = regex.find(line)
        return match?.groupValues?.get(1) ?: ""
    }
}
