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

    // FIX(anr): Bu alanlar ana thread'de yazılıp IO thread'lerinde okunuyor
    // (kurulum artık arka planda koşuyor), @Volatile olmadan bir thread bayat
    // "kurulmadı" değeri görüp motoru ikinci kez kurmaya kalkabilirdi.
    @Volatile private var isInitialized = false
    @Volatile private var appContext: Context? = null
    // FIX(init-retry): FFmpeg ve Aria2c ayrı izleniyor. Eski kod ikisi patlasa
    // bile isInitialized = true yazıyor ve sonraki init() çağrıları "if
    // (isInitialized) return" ile kısa devre oluyordu: ffmpeg bir kez
    // kurulamayınca birleştirme (merge) her videoda sessizce bozuk kalıyor,
    // kullanıcıya verilen "uygulamayı yeniden başlat" tavsiyesi de sonuçsuz
    // kalıyordu. Artık yalnız eksik bileşen her çağrıda yeniden denenir.
    @Volatile private var ffmpegReady = false
    @Volatile private var aria2cReady = false
    @Volatile private var lastInitError: String? = null
    // NOT: Eski "activeTasks" haritası kaldırıldı — yazılıyor ama hiçbir yerde
    // okunmuyordu (ne get, ne containsKey). Aktif görevlerin tek doğruluk
    // kaynağı DownloadForegroundService.activeDownloadJobs'tur; ikinci bir
    // yarım kayıt tutmak yalnızca sapma üretir.
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

    /**
     * Yalnızca uygulama context'ini bağlar, ağır kurulum YAPMAZ.
     *
     * FIX(anr): [init] yt-dlp, ffmpeg ve aria2c arşivlerini diske açar; ilk
     * açılışta saniyeler sürer ve ana thread'de çağrıldığı için uygulama daha
     * ilk karede ANR veriyordu. Ağır kısım artık arka plana alındı, ama
     * [startDownload] çıktı yolu denetimi appContext'e bakıyor: context'i
     * ANINDA bağlamazsak (ya da servis START_STICKY ile tek başına dirilirse)
     * appContext null kalır ve yol denetimi tamamen atlanırdı.
     */
    fun attachContext(context: Context) {
        appContext = context.applicationContext
    }

    /**
     * Motoru kurar ve gerçekten kurulup kurulmadığını döndürür.
     *
     * ARKA PLAN THREAD'İNDEN çağrılmalıdır (bkz. [attachContext]).
     * `@Synchronized`: arka plandaki ilk kurulum ile ilk indirmenin
     * [ensureInitialized] çağrısı yarışabilir; ikisi aynı anda arşiv açarsa
     * yarım dosyalar üzerine yazılır.
     */
    @Synchronized
    fun init(context: Context): Boolean {
        val ctx = context.applicationContext
        appContext = ctx
        if (!isInitialized) {
            try {
                ThermalManager.init(ctx)
                YoutubeDL.getInstance().init(ctx)
                isInitialized = true
                lastInitError = null
                Log.i(TAG, "YtDlpNativeManager initialized successfully")
            } catch (e: Exception) {
                lastInitError = e.message ?: e.javaClass.simpleName
                Log.e(TAG, "Failed to initialize YoutubeDL: ${e.message}", e)
                return false
            }
        }
        if (!ffmpegReady) {
            ffmpegReady = try {
                FFmpeg.getInstance().init(ctx)
                true
            } catch (e: Exception) {
                Log.w(TAG, "FFmpeg init notice: ${e.message}")
                false
            }
        }
        if (!aria2cReady) {
            aria2cReady = try {
                Aria2c.getInstance().init(ctx)
                true
            } catch (e: Exception) {
                Log.w(TAG, "Aria2c init notice: ${e.message}")
                false
            }
        }
        return isInitialized
    }

    /** Son kurulum hatası; kurulum başarısızsa çağırana gerçek nedeni taşır. */
    fun lastInitError(): String? = lastInitError

    /**
     * Motor hazır değilse burada kurar (IO thread'inde çağrılır).
     *
     * Gerekli: kurulum artık arka planda başlatıldığı için ilk `fetchMetadata`
     * veya indirme, kurulum bitmeden gelebilir; ayrıca sistem uygulamayı
     * öldürüp yalnızca servisi START_STICKY ile dirilttiğinde MainActivity hiç
     * çalışmaz ve motor hiç kurulmamış olur.
     */
    private fun ensureInitialized(): Boolean {
        if (isInitialized) return true
        val ctx = appContext ?: return false
        return init(ctx)
    }

    private fun initFailureReason(): String =
        lastInitError ?: "uygulama bağlamı bağlanmadı"

    /**
     * Uygulamaya özel depolama kökleri.
     *
     * Yalnız `getExternalFilesDir` yetmez: Dart tarafı harici dizini
     * oluşturamazsa `getApplicationDocumentsDirectory()` altına (app_flutter)
     * düşer (storage_manager.dart initDirectory yedek dalı). O yol listede
     * olmazsa native taraf kendi indirme klasörümüzü "yetkisiz" sayar ve
     * indirme hiç başlamaz.
     */
    private fun appStorageRoots(context: Context): List<File> {
        val roots = mutableListOf<File>()
        try {
            context.getExternalFilesDirs(null)?.forEach { dir -> if (dir != null) roots.add(dir) }
        } catch (e: Exception) {
            Log.w(TAG, "External app dirs unavailable: ${e.message}")
        }
        try {
            roots.add(context.filesDir)
            // Flutter'ın PathUtils.getDataDirectory() ile birebir aynı yol:
            // path_provider'ın getApplicationDocumentsDirectory() dönüşü budur.
            roots.add(context.getDir("flutter", Context.MODE_PRIVATE))
        } catch (e: Exception) {
            Log.w(TAG, "Internal app dirs unavailable: ${e.message}")
        }
        return roots
    }

    /**
     * Verilen yolun uygulamaya özel depolamanın İÇİNDE olup olmadığı.
     *
     * FIX(path): Eski denetim iki yerden birden sızdırıyordu: (a) `safeBaseDir`
     * boş dizeye düşünce `startsWith("")` her yol için true dönüyor, kapı tamamen
     * açılıyordu; (b) `contains(packageName)` ölçütü
     * `/storage/emulated/0/Download/com.offlineyoutube.offlineyoutube_yedek/../..`
     * gibi bir yolu kabul ediyordu. Artık karşılaştırma canonical (sembolik link
     * ve `..` çözülmüş) Path üzerinden yapılır; kök hiç bulunamazsa kapı AÇILMAZ.
     */
    fun isPathInAppStorage(context: Context, target: File): Boolean {
        val targetPath = try {
            target.canonicalFile.toPath()
        } catch (e: Exception) {
            Log.w(TAG, "Path canonicalization failed: ${e.message}")
            return false
        }
        return appStorageRoots(context).any { root ->
            try {
                targetPath.startsWith(root.canonicalFile.toPath())
            } catch (e: Exception) {
                false
            }
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
        try {
            val uri = android.net.Uri.parse(url)
            if (uri.scheme != "https") return false
            val host = uri.host?.lowercase() ?: return false
            return host == "youtube.com" || host == "youtu.be" ||
                   host == "www.youtube.com" || host == "m.youtube.com" ||
                   host == "music.youtube.com" ||
                   host.endsWith(".youtube.com") || host.endsWith(".youtu.be")
        } catch (e: Exception) {
            return false
        }
    }

    suspend fun fetchMetadata(url: String): Map<String, Any?> = withContext(Dispatchers.IO) {
        var cookieFile: File? = null
        try {
            if (!isUrlSafe(url)) throw IllegalArgumentException("Unauthorized URL scheme/domain")
            if (!ensureInitialized()) throw IllegalStateException("yt-dlp motoru kurulamadı: ${initFailureReason()}")
            val isPlaylist = isPlaylistUrl(url)
            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                
                appContext?.let { ctx ->
                    cookieFile = CookieHelper.saveCookies(ctx, "meta")
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
                    "youtube:lang=tr"
                )
                addOption("--geo-bypass-country", "TR")
                addOption("--force-ipv4")
                addOption("--socket-timeout", "15")
                addOption("--sleep-requests", "1.0")
                
                if (isPlaylist) {
                    addOption("--flat-playlist")
                } else {
                    addOption("--no-playlist")
                    // FIX(size): Metadatann (rn: 76 MB) gerek indirme boyutuyla (rn: 1.95 GB) eYleYmesi iin 
                    // indirme srasnda kullandmz yǬksek kalite format deYerini bilgi ekerken de zorluyoruz.
                    addOption("-f", "bestvideo+bestaudio/best")
                    addOption("-S", "res,vcodec:av1,vcodec:vp9,vcodec:h264")
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
            CookieHelper.release(cookieFile)
        }
    }

    suspend fun fetchPlaylistEntries(url: String): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        var cookieFile: File? = null
        try {
            if (!isUrlSafe(url)) throw IllegalArgumentException("Unauthorized URL scheme/domain")
            if (!ensureInitialized()) throw IllegalStateException("yt-dlp motoru kurulamadı: ${initFailureReason()}")
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
                addOption("--force-ipv4")
                addOption("--socket-timeout", "15")
                addOption("--sleep-requests", "1.0")
                addOption("--flat-playlist")
                addOption("-J")
                appContext?.let { ctx ->
                    cookieFile = CookieHelper.saveCookies(ctx, "list")
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
            CookieHelper.release(cookieFile)
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

        if (!ensureInitialized()) {
            onError(IllegalStateException("yt-dlp motoru kurulamadı: ${initFailureReason()}"))
            return
        }

        // Kurulum başarılıysa appContext kesinlikle doludur; yine de null ise
        // yolu doğrulayamayız ve "doğrulayamadım" sessizce "geçti" sayılamaz.
        val ctx = appContext
        if (ctx == null) {
            onError(IllegalStateException("Uygulama bağlamı yok, çıktı yolu doğrulanamadı"))
            return
        }
        if (outputDir.absolutePath.isEmpty() || !isPathInAppStorage(ctx, outputDir)) {
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

            intentionallyStoppedTasks.remove(taskId)

            val ffmpegThreads = ThermalManager.getRecommendedFfmpegThreads()
            val dynamicRateLimit = ThermalManager.getRecommendedLimitRate()

            val request = YoutubeDLRequest(url).apply {
                addOption("--no-update")
                addOption("--no-warnings")
                addOption("--no-cache-dir")
                addOption("--add-header", "Accept-Language: tr-TR,tr;q=0.9,en;q=0.8")
                addOption("--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
                addOption("--extractor-args", "youtube:lang=tr")
                addOption("--geo-bypass-country", "TR")
                addOption("--force-ipv4") // Prevents hanging on IPv6 networks
                addOption("--socket-timeout", "15") // Fail fast instead of hanging
                addOption("--sleep-requests", "1.0")
                addOption("--sleep-subtitles", "1")
                addOption("--write-thumbnail") // Sidecar image file only (zero video transcoding)
                // Safe formatting: 50-char max title (50 chars * up to 4 bytes/char = 200 bytes) + unique video id keeps the full filename, incl. sidecar suffixes like [id].f137.mp4.part, under Android's 255-byte filename limit without slicing multi-byte UTF-8 chars
                addOption("-o", "${outputDir.absolutePath}/%(title).50s [%(id)s].%(ext)s")
                // FIX(quality): YTDLnis-inspired format selection chain for maximum resolution:
                // Sadece ext=mp4 ile sınırlamak, YouTube'un yüksek çözünürlükleri sadece vp9/webm
                // olarak sunduğu durumlarda çözünürlüğü 480p'ye düşürebilir. Bu yüzden her codec
                // kabul ediliyor (bestvideo+bestaudio) ve sonrasında ffmpeg ile mp4'e remux ediliyor.
                addOption("-f", "bestvideo+bestaudio/best")
                // Kullanıcının codec önceliği: en yüksek çözünürlük > AV1 > VP9 > H.264
                addOption("-S", "res,vcodec:av1,vcodec:vp9,vcodec:h264")
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
                cookieFile = CookieHelper.saveCookies(ctx, taskId)
                if (cookieFile != null && cookieFile!!.exists()) {
                    addOption("--cookies", cookieFile!!.absolutePath)
                }

                // 5. Türkçe Altyazı (Sidecar .vtt/.srt files - no video re-encoding)
                addOption("--write-subs")
                addOption("--write-auto-subs")
                addOption("--sub-lang", "tr,tr-orig,tr-TR,en")
                addOption("--sub-format", "vtt/srt/best")
                
                // 6. Hız sınırı: değer SÜREÇ BAŞLARKEN bir kez seçilir.
                // DİKKAT (yanlış güvenlik hissi): yt-dlp --limit-rate'i komut
                // satırından okur, çalışırken değiştirilemez. Cihaz indirme
                // sırasında ısınırsa ThermalManager daha düşük bir değer önerse
                // bile ÇALIŞAN süreç eski hızla devam eder; termal koruma ancak
                // bir sonraki görevde (veya duraklat/devam ettir sonrası, çünkü
                // --continue ile yeni süreç yeni limitle başlar) devreye girer.
                // Süreç içi koruma sistemin kendi kısıtlamasına bırakılmıştır.
                addOption("--limit-rate", dynamicRateLimit)
                addOption("--sleep-interval", "1")
                addOption("--max-sleep-interval", "3")
                addOption("--retry-sleep", "1")
                addOption("--retries", "10")
                addOption("--fragment-retries", "10")
            }

            var lastProgressEmitTime = 0L
            var lastProgressPercent = -1f
            // FIX(yuzde-geri): Geri gitme koruması eskiden callback'in İÇİNDE,
            // her çağrıda sıfırlanan yerel değişkenle yapılıyordu; hiçbir şey
            // hatırlamıyordu. yt-dlp "bestvideo+bestaudio" ile önce videoyu
            // 0'dan 100'e indirir, sonra ses akışını yeniden 0'dan başlatır:
            // kullanıcı bildirimde %100 gördükten saniyeler sonra %0,4 görüyor,
            // indirme bozuldu sanıyordu. Yüzde artık çağrılar arasında monoton.
            var monotonicProgress = 0f

            val response: YoutubeDLResponse = YoutubeDL.getInstance().execute(
                request,
                taskId
            ) { callbackProgress, etaInSeconds, line ->
                // Debug the raw stdout to see what yt-dlp is actually doing or if it's hung
                if (line != null) {
                    Log.d(TAG, "stdout: $line")
                }
                
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
                            m.group(1).toFloatOrNull()?.let { parsedProgress ->
                                currentProgress = maxOf(currentProgress, parsedProgress)
                            }
                        }
                    }
                }

                monotonicProgress = maxOf(monotonicProgress, currentProgress)
                currentProgress = monotonicProgress

                val delta = Math.abs(currentProgress - lastProgressPercent)
                // %100'e ulaşma bir KEZ bildirilir. Monoton yüzde 100'de sabit
                // kaldığı için eski "currentProgress >= 100f" koşulu, birleştirme
                // (merge) boyunca gelen her stdout satırında kısmayı devre dışı
                // bırakıp dört ekranı birden yeniden kurdururdu.
                val reachedFullNow = currentProgress >= 100f && lastProgressPercent < 100f

                // Source-level native callback throttling: parse strings ONLY on meaningful progress or timeout
                if (reachedFullNow || (now - lastProgressEmitTime >= 800L && delta >= 0.5f) || (now - lastProgressEmitTime >= 2500L)) {
                    lastProgressEmitTime = now
                    lastProgressPercent = currentProgress
                    onProgress(currentProgress, etaInSeconds, speed, totalSize, downloadedSize)
                }
            }

            onComplete(response.out ?: "İndirme Tamamlandı")
        } catch (e: Exception) {
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
            CookieHelper.release(cookieFile)
        }
    }

    fun stopDownload(taskId: String) {
        try {
            // FIX(race): Nesli artır — çalışmakta olan yürütme kendi catch'inde
            // neslin değiştiğini görüp hata bildirimini bastırır.
            stopGeneration[taskId] = (stopGeneration[taskId] ?: 0) + 1
            intentionallyStoppedTasks.add(taskId)
            YoutubeDL.getInstance().destroyProcessById(taskId)
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
