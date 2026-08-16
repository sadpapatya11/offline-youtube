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
import java.util.regex.Pattern

object YtDlpNativeManager {
    private const val TAG = "YtDlpNativeManager"
    private var isInitialized = false
    private var appContext: Context? = null
    private val activeTasks = ConcurrentHashMap<String, String>() // taskId -> taskId
    private val intentionallyStoppedTasks = ConcurrentHashMap.newKeySet<String>()
    // FIX(race): Her görev için "durdurma nesli" sayacı. stopDownload() sayacı
    // artırır; startDownload'ın catch bloğu, yürütme başladıktan sonra sayacın
    // değişip değişmediğine bakarak gerçek hatayı bilinçli durdurmadan ayırt
    // eder. Önceden yalnızca intentionallyStoppedTasks bayrağı kullanılıyordu;
    // "duraklat -> hızlı devam ettir" durumunda bayrak erken silindiğinden eski
    // coroutine'in catch'i aktif görev için SAHTE "error" eventi üretiyordu.
    private val stopGeneration = ConcurrentHashMap<String, Int>()

    // Pre-compiled static regex patterns to eliminate runtime pattern allocations and GC churn
    private val SPEED_PATTERN = Pattern.compile("at\\s+([0-9.]+\\s*[kKMmGg]?[iI]?[bB]/s)")
    private val TOTAL_SIZE_PATTERN = Pattern.compile("of\\s+~?\\s*([0-9.]+\\s*[kKMmGg]?[iI]?[bB])")
    // FIX(size): Eski desen hiç eşleşmiyordu — "[download]" sonrası gelen token
    // boyut değil YÜZDE'dir ("45.5% of 10.00MiB ..."). İndirilen miktar artık
    // yüzde + toplam boyuttan hesaplanıyor (parseDownloadedSize).
    private val DOWNLOADED_PERCENT_PATTERN = Pattern.compile("\\[download\\]\\s+([0-9.]+)%")
    private val SIZE_VALUE_PATTERN = Pattern.compile("([0-9.]+)\\s*([kKmMgG]?[iI]?[bB])")

    fun init(context: Context) {
        if (isInitialized) return
        appContext = context.applicationContext
        try {
            ThermalManager.init(context.applicationContext)
            YoutubeDL.getInstance().init(context.applicationContext)
            try {
                FFmpeg.getInstance().init(context.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "FFmpeg init notice: ${e.message}")
            }
            try {
                Aria2c.getInstance().init(context.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "Aria2c init notice: ${e.message}")
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

    private fun isUrlSafe(url: String): Boolean {
        val lower = url.lowercase()
        return lower.startsWith("https://www.youtube.com/") || 
               lower.startsWith("https://youtu.be/") || 
               lower.startsWith("https://m.youtube.com/") ||
               lower.startsWith("https://youtube.com/")
    }

    suspend fun fetchMetadata(url: String): Map<String, Any?> = withContext(Dispatchers.IO) {
        var cookieFile: File? = null
        try {
            if (!isUrlSafe(url)) throw IllegalArgumentException("Unauthorized URL scheme/domain")
            val isPlaylist = isPlaylistUrl(url)
            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                
                appContext?.let { ctx ->
                    cookieFile = CookieHelper.saveCookies(ctx)
                    if (cookieFile != null && cookieFile!!.exists()) {
                        addOption("--cookies", cookieFile!!.absolutePath)
                    }
                }
                // FIX(tab): iPhone UA + player_client/player_skip ayarları TEK
                // VİDEO için bot-korumasını aşar ama oynatma listesi (tab)
                // sayfasını KIRAR ("Unable to recognize tab page" — Windows'ta
                // birebir üretilip doğrulandı). Liste için desktop UA + lang.
                addOption(
                    "--user-agent",
                    if (isPlaylist)
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
                    else
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
                )
                addOption(
                    "--extractor-args",
                    if (isPlaylist) "youtube:lang=tr"
                    else "youtube:player_client=ios,android,web;lang=tr"
                )
                addOption("--geo-bypass-country", "TR")
                addOption("--sleep-requests", "1.5")
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
            Log.e(TAG, "Fetch metadata failed: ${e.message}", e)
            throw e
        } finally {
            cookieFile?.delete()
        }
    }

    suspend fun fetchPlaylistEntries(url: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        var cookieFile: File? = null
        try {
            if (!isUrlSafe(url)) throw IllegalArgumentException("Unauthorized URL scheme/domain")
            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                // FIX(tab): Liste çekiminde iPhone UA + player_client/player_skip
                // KULLANMA (tab sayfasını kırar; Windows'ta birebir doğrulandı).
                addOption("--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
                addOption("--extractor-args", "youtube:lang=tr")
                addOption("--geo-bypass-country", "TR")
                addOption("--sleep-requests", "1.0")
                addOption("--flat-playlist")
                addOption("-J")
                appContext?.let { ctx ->
                    cookieFile = CookieHelper.saveCookies(ctx)
                    if (cookieFile != null && cookieFile!!.exists()) {
                        addOption("--cookies", cookieFile!!.absolutePath)
                    }
                }
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
                        
                        // Skip deleted/private/unavailable videos
                        val lowerTitle = itemTitle.lowercase()
                        if (itemTitle.isEmpty() || itemTitle.equals("null", ignoreCase = true) || lowerTitle.contains("[deleted") || lowerTitle.contains("[private") || lowerTitle.contains("[unavailable")) {
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
            Log.e(TAG, "Fetch playlist entries failed: ${e.message}", e)
            throw e
        } finally {
            cookieFile?.delete()
        }
    }

    fun isPlaylistUrl(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("list=") || lower.contains("/playlist") || lower.contains("/@") || lower.contains("/channel/") || lower.contains("/c/") || lower.contains("/user/")
    }

    fun startDownload(
        taskId: String,
        url: String,
        outputDir: File,
        onProgress: (Float, Long, String, String, String) -> Unit,
        onComplete: (String) -> Unit,
        onError: (Exception) -> Unit
    ) {
        if (!isUrlSafe(url)) {
            onError(IllegalArgumentException("Unauthorized URL scheme/domain"))
            return
        }
        
        val safeBaseDir = appContext?.getExternalFilesDir(null)?.absolutePath ?: ""
        if (outputDir.absolutePath.isEmpty() || (!outputDir.absolutePath.startsWith(safeBaseDir) && !outputDir.absolutePath.contains(appContext?.packageName ?: ""))) {
            Log.w(TAG, "Blocked unauthorized path: ${outputDir.absolutePath}")
            onError(IllegalArgumentException("Unauthorized output path"))
            return
        }

        // FIX(race): Bu yürütmenin neslini try bloğu DIŞINDA yakala — catch
        // bloğunda da erişilmesi gerekiyor (Kotlin try değişkenlerini catch'e
        // taşımaz).
        val executionGeneration = stopGeneration[taskId] ?: 0
        var cookieFile: File? = null
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

            val ffmpegThreads = ThermalManager.getRecommendedFfmpegThreads()
            val dynamicRateLimit = ThermalManager.getRecommendedLimitRate()

            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                addOption("--user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")
                addOption("--extractor-args", "youtube:player_client=ios,android,web;lang=tr")
                addOption("--geo-bypass-country", "TR")
                addOption("--sleep-requests", "1.5")
                addOption("--sleep-subtitles", "1")
                addOption("--write-thumbnail") // Sidecar image file only (zero video transcoding)
                // Safe formatting: 50-char max title (50 chars * up to 4 bytes/char = 200 bytes) + unique video id keeps the full filename, incl. sidecar suffixes like [id].f137.mp4.part, under Android's 255-byte filename limit without slicing multi-byte UTF-8 chars
                addOption("-o", "${outputDir.absolutePath}/%(title).50s [%(id)s].%(ext)s")
                // FIX(quality): YTDLnis-inspired format selection chain for maximum resolution:
                // 1. bestvideo[ext=mp4]+bestaudio[ext=m4a] → HW-decode-friendly, birleştirmesi sorunsuz
                // 2. bestvideo+bestaudio → VP9/AV1 4K/8K dahil herhangi codec (FFmpeg remux gerekebilir)
                // 3. best → Önceden birleştirilmiş en iyi kalite (fallback)
                addOption("-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best")
                // Çözünürlüğü ve codec kalitesini en yükseğe zorla (8K > 4K > 1080p sıralaması)
                addOption("-S", "res,vcodec:h265,vcodec:h264,acodec:aac")
                
                // 1. FFmpeg Remuxing — container birleştirme (re-encode YOK, sadece kapsayıcı değiştirir)
                addOption("--merge-output-format", "mp4")
                addOption("--postprocessor-args", "ffmpeg:-threads $ffmpegThreads")
                // MP4'e sığmayan codec'lerde (VP9/AV1) otomatik remux yap
                addOption("--remux-video", "mp4")
                
                // 2. Single fragment stream to eliminate Wi-Fi modem saturation & multi-thread CPU bursts
                addOption("--concurrent-fragments", "1")

                // 3. Storage I/O buffer to prevent high-frequency flash storage controller heating
                addOption("--buffer-size", "64K")
                addOption("--http-chunk-size", "10M")

                // 4. Android filesystem compatibility (Strip illegal chars : " ? * < > |)
                // NOTE: --trim-filenames omitted: it limits by CHARACTERS (not bytes), so it could not
                // guarantee the 255-byte limit; the %(title).50s template already caps the name.
                addOption("--windows-filenames")

                addOption("--no-mtime")
                addOption("--continue")
                addOption("--ignore-errors")
                addOption("--no-playlist")
                appContext?.let { ctx ->
                    cookieFile = CookieHelper.saveCookies(ctx)
                    if (cookieFile != null && cookieFile!!.exists()) {
                        addOption("--cookies", cookieFile!!.absolutePath)
                    }
                }
                
                // 5. Türkçe Altyazı (Sidecar .vtt/.srt files - no video re-encoding)
                addOption("--write-subs")
                addOption("--write-auto-subs")
                addOption("--sub-lang", "tr,tr-orig,tr-TR,en")
                addOption("--sub-format", "vtt/srt/best")
                
                // 6. Thermal-Aware Dynamic Rate Limiting & Sleep Interval
                addOption("--limit-rate", dynamicRateLimit)
                addOption("--sleep-interval", "2")
                addOption("--max-sleep-interval", "60")
                addOption("--retry-sleep", "5")
                addOption("--retries", "10")
                addOption("--fragment-retries", "10")
            }

            var lastProgressEmitTime = 0L
            var lastProgressPercent = -1f

            val response: YoutubeDLResponse = YoutubeDL.getInstance().execute(
                request,
                taskId
            ) { callbackProgress, etaInSeconds, line ->
                val now = System.currentTimeMillis()
                
                var currentProgress = callbackProgress
                var speed = ""
                var totalSize = ""
                var downloadedSize = ""
                
                if (line != null && line.contains("[download]")) {
                    if (line.contains("Sleeping")) {
                        // Example: "[download] Sleeping 35.12 seconds..."
                        val m = java.util.regex.Pattern.compile("Sleeping\\s+([\\d.]+)\\s+seconds").matcher(line)
                        if (m.find()) {
                            speed = "Bekliyor: ${m.group(1)}s"
                        } else {
                            speed = "Güvenlik Beklemesi..."
                        }
                    } else {
                        speed = parseSpeed(line)
                        totalSize = parseTotalSize(line)
                        downloadedSize = parseDownloadedSize(line, totalSize)
                        val m = DOWNLOADED_PERCENT_PATTERN.matcher(line)
                        if (m.find()) {
                            m.group(1).toFloatOrNull()?.let {
                                currentProgress = it
                            }
                        }
                    }
                }

                val delta = Math.abs(currentProgress - lastProgressPercent)
                
                // Source-level native callback throttling: parse strings ONLY on meaningful progress or timeout
                if (currentProgress >= 100f || (now - lastProgressEmitTime >= 800L && delta >= 0.5f) || (now - lastProgressEmitTime >= 2500L)) {
                    lastProgressEmitTime = now
                    lastProgressPercent = currentProgress
                    onProgress(currentProgress, etaInSeconds, speed, totalSize, downloadedSize)
                }
            }

            activeTasks.remove(taskId)
            onComplete(response.out ?: "İndirme Tamamlandı")
        } catch (e: Exception) {
            activeTasks.remove(taskId)
            // FIX(race): Nesil değiştiyse (durdurma olduysa) veya bayrak hâlâ
            // duruyorsa bu bilinçli bir duraklatma/iptaldir — hata bildirme.
            val generationChanged = (stopGeneration[taskId] ?: 0) != executionGeneration
            if (generationChanged || intentionallyStoppedTasks.remove(taskId)) {
                Log.i(TAG, "Task $taskId was intentionally paused/stopped. Suppressing error callback.")
                return
            }
            Log.e(TAG, "Download error for task $taskId: ${e.message}", e)
            onError(e)
        } finally {
            cookieFile?.delete()
        }
    }

    fun stopDownload(taskId: String) {
        try {
            // FIX(race): Nesli artır — çalışmakta olan yürütme kendi catch'inde
            // neslin değiştiğini görüp hata bildirimini bastırır.
            stopGeneration[taskId] = (stopGeneration[taskId] ?: 0) + 1
            intentionallyStoppedTasks.add(taskId)
            YoutubeDL.getInstance().destroyProcessById(taskId)
            activeTasks.remove(taskId)
            Log.i(TAG, "Task $taskId destroyed/stopped intentionally")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop task $taskId: ${e.message}", e)
        }
    }

    private fun parseSpeed(line: String?): String {
        if (line.isNullOrEmpty()) return ""
        val m = SPEED_PATTERN.matcher(line)
        return if (m.find()) m.group(1) ?: "" else ""
    }

    private fun parseTotalSize(line: String?): String {
        if (line.isNullOrEmpty()) return ""
        val m = TOTAL_SIZE_PATTERN.matcher(line)
        return if (m.find()) m.group(1) ?: "" else ""
    }

    // FIX(size): "[download]  45.5% of 10.00MiB ..." satırından yüzdeyi okuyup
    // indirilen miktarı toplam boyuttan bayt olarak hesaplar.
    private fun parseDownloadedSize(line: String?, totalSizeText: String?): String {
        if (line.isNullOrEmpty()) return ""
        val m = DOWNLOADED_PERCENT_PATTERN.matcher(line)
        if (!m.find()) return ""
        val percent = m.group(1).toDoubleOrNull() ?: return ""
        val totalBytes = parseSizeToBytes(totalSizeText)
        if (totalBytes <= 0L) return ""
        return formatBytes((totalBytes * percent / 100.0).toLong())
    }

    private fun parseSizeToBytes(text: String?): Long {
        if (text.isNullOrEmpty()) return 0L
        val m = SIZE_VALUE_PATTERN.matcher(text)
        if (!m.find()) return 0L
        val value = m.group(1).toDoubleOrNull() ?: return 0L
        val unit = m.group(2)?.lowercase() ?: ""
        return when {
            unit.endsWith("gib") -> (value * 1024 * 1024 * 1024).toLong()
            unit.endsWith("mib") -> (value * 1024 * 1024).toLong()
            unit.endsWith("kib") -> (value * 1024).toLong()
            unit.endsWith("gb") -> (value * 1000 * 1000 * 1000).toLong()
            unit.endsWith("mb") -> (value * 1000 * 1000).toLong()
            unit.endsWith("kb") -> (value * 1000).toLong()
            else -> value.toLong()
        }
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1024L * 1024 * 1024 -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
            bytes >= 1024L * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            bytes >= 1024L -> String.format("%.1f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}
