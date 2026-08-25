package com.offlineyoutube.offlineyoutube

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.offlineyoutube/downloader"
    private val EVENT_CHANNEL = "com.offlineyoutube/download_events"

    private var eventSink: EventChannel.EventSink? = null

    // FIX(scope): Düz Job'lı bir scope'ta TEK bir yakalanmamış hata parent Job'ı
    // iptal ediyor ve o andan sonra başlatılan HER coroutine sessizce hiç
    // çalışmıyordu: kullanıcı için bu, klasör boyutu ölçümü bir kez patladıktan
    // sonra video bilgisi çekmenin ve motor güncellemenin sonsuza dek yanıtsız
    // kalması demekti. SupervisorJob kardeşleri yalıtır; ayrıca her dal kendi
    // hatasını yakalayıp Dart'a bildirir.
    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Önceki koşudan (süreç öldürülmesi veya çökme) kalan çerez dosyalarını temizle.
        // Bu dosyalar tam Google oturum çerezlerini düz metin taşır; normal akışta
        // indirme sonrası silinirler ama süreç öldürülürse geride kalırlar.
        CookieHelper.clearStaleCookieFiles(applicationContext)

        // FIX(anr): YtDlpNativeManager.init() yt-dlp, ffmpeg ve aria2c arşivlerini
        // diske açar; ilk açılışta saniyeler sürüyor ve ana thread'de çağrıldığı
        // için uygulama daha ilk karede ANR ("Uygulama yanıt vermiyor") veriyordu.
        // Context ANINDA bağlanır (çıktı yolu denetimi ile servis dirilişi buna
        // bakar), ağır kurulum arka plana alınır.
        YtDlpNativeManager.attachContext(applicationContext)
        activityScope.launch {
            withContext(Dispatchers.IO) { YtDlpNativeManager.init(applicationContext) }
        }

        // Event Channel Setup
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    DownloadForegroundService.eventCallback = { data ->
                        runOnUiThread {
                            eventSink?.success(org.json.JSONObject(data).toString())
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
                    // FIX(sahte-basari): Kurulum patlasa bile true dönülüyordu.
                    // Motor hazırlığını bu kanaldan soran taraf her zaman "hazır"
                    // cevabı alıp kullanıcıya kurulum hatası yerine her indirmede
                    // anlamsız yt-dlp hataları gösteriyordu. Ayrıca kurulum ana
                    // thread'de koşuyordu (bkz. ANR notu).
                    activityScope.launch {
                        val hazir = withContext(Dispatchers.IO) {
                            YtDlpNativeManager.init(applicationContext)
                        }
                        if (hazir) {
                            result.success(true)
                        } else {
                            result.error(
                                "INIT_FAILED",
                                YtDlpNativeManager.lastInitError() ?: "yt-dlp motoru kurulamadı",
                                null
                            )
                        }
                    }
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
                    // FIX(dogrulama): Eksik argümanlar sessizce boş dizeye düşüyordu.
                    // Geçersiz istek yine de foreground servisi ve WakeLock'u ayağa
                    // kaldırıyor, 30 saniye "İndirme başlatılıyor" bildirimi gösterip
                    // sessizce ölüyordu. fetchMetadata dalındaki disiplin burada da
                    // uygulanıyor.
                    if (taskId.isEmpty() || url.isEmpty() || outputPath.isEmpty()) {
                        result.error("INVALID_ARGS", "taskId, url ve outputPath zorunludur", null)
                        return@setMethodCallHandler
                    }

                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_START
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                        putExtra(DownloadForegroundService.EXTRA_URL, url)
                        putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        putExtra(DownloadForegroundService.EXTRA_OUTPUT_PATH, outputPath)
                    }
                    // FIX(fgs-start): API 31+'te uygulama arka plandayken
                    // startForegroundService() ForegroundServiceStartNotAllowedException
                    // fırlatır; yakalanmazsa Dart tarafında PlatformException olur ve
                    // görev "İndirme başlatılamadı" hatasına düşer. Yapılandırılmış
                    // hata dönüyoruz ki Dart kuyruğu ön plana dönünce yeniden denesin.
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "FGS start failed: ${e.message}")
                        result.error("FGS_NOT_ALLOWED", "Arka planda servis başlatılamadı. Uygulama ön plana alınca otomatik yeniden denenecek.", null)
                    }
                }

                "pauseDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    if (taskId.isEmpty()) {
                        result.error("INVALID_ARGS", "taskId zorunludur", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_PAUSE
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                    }
                    // FIX(sahte-garanti): Dönüş "istek servise İLETİLDİ" demektir,
                    // "duraklatıldı" demek değil; duraklamanın kesin onayı servisin
                    // gönderdiği "paused" olayıdır. Eskiden istisna hiç ele
                    // alınmadığı için iletim başarısızken bile true dönülüyordu:
                    // uygulama arka plandayken (API 26+) startService
                    // IllegalStateException fırlatır, Dart görevi "duraklatıldı"
                    // sayar, native indirme ise sürer.
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "pauseDownload startService failed: ${e.message}")
                        result.error("SERVICE_NOT_STARTED", "Duraklatma isteği servise iletilemedi", null)
                    }
                }

                // NOTE: Eski "resumeDownload" handler'ı kaldırıldı — Dart tarafında
                // hiçbir çağıran yoktu (devam etme aynı taskId ile "startDownload"
                // üzerinden yapılıyor) ve yanıltıcı ölü yüzey oluşturuyordu.

                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    if (taskId.isEmpty()) {
                        result.error("INVALID_ARGS", "taskId zorunludur", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_CANCEL
                        putExtra(DownloadForegroundService.EXTRA_TASK_ID, taskId)
                    }
                    // Bkz. pauseDownload: dönüş yalnız iletimi doğrular, iptalin
                    // kesin onayı servisin "cancelled" olayıdır.
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "cancelDownload startService failed: ${e.message}")
                        result.error("SERVICE_NOT_STARTED", "İptal isteği servise iletilemedi", null)
                    }
                }

                "stopDownloadService" -> {
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_STOP_SERVICE
                    }
                    try {
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "stopDownloadService startService failed: ${e.message}")
                        result.error("SERVICE_NOT_STARTED", "Servisi durdurma isteği iletilemedi", null)
                    }
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
                    // FIX(kota): Eski kapı iki yönde birden sızdırıyordu.
                    // (a) getExternalFilesDir null dönünce (telefon USB ile
                    // bilgisayara bağlanıp depolama paylaşıma açıldığında olur)
                    // safeBaseDir boş dizeye düşüyor, startsWith("") HER yolu kabul
                    // ediyordu. (b) Ters yönde: Dart harici dizini oluşturamayıp
                    // app_flutter altındaki yedek klasöre düştüğünde o yol listede
                    // olmadığı için ölçüm kalıcı olarak 0 dönüyordu; arayüzde
                    // "0 B" yazıyor ve depolama kotası hiç kapanmıyordu.
                    // İzinli kökler artık YtDlpNativeManager ile TEK kaynaktan
                    // geliyor (indirme yolu denetimiyle aynı liste).
                    if (path.isEmpty() ||
                        !YtDlpNativeManager.isPathInAppStorage(applicationContext, File(path))
                    ) {
                        Log.w("MainActivity", "Blocked unauthorized path size request")
                        // 0L DEĞİL hata: "ölçemedim" ile "0 bayt" aynı şey değildir;
                        // Dart tarafı hatayı görünce kendi yedek taramasını yapar.
                        result.error("UNAUTHORIZED_PATH", "Yol uygulama depolamasının dışında, ölçüm yapılmadı", null)
                        return@setMethodCallHandler
                    }
                    activityScope.launch {
                        try {
                            val size = withContext(Dispatchers.IO) {
                                calculateFolderSize(File(path))
                            }
                            result.success(size)
                        } catch (e: Exception) {
                            result.error("FOLDER_SIZE_ERROR", e.message ?: "Klasör boyutu ölçülemedi", null)
                        }
                    }
                }

                "getThermalDiagnostics" -> {
                    result.success(ThermalManager.getDiagnosticsReport())
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        // FIX(scope): Activity yok edildikten sonra süren coroutine'ler hem
        // Activity'yi hem de artık kimseye ulaşmayacak eventSink'i canlı tutuyordu.
        activityScope.cancel()
        super.onDestroy()
    }

    // FIX(cycle): Sembolik link döngüsü veya FIFO içeren klasörlerde sonsuz
    // özyineleme StackOverflowError'a (Error — catch edilemez) yol açıyordu.
    // Derinlik limiti + izlenen gerçek yollar ile korunuyor.
    private fun calculateFolderSize(file: File, depth: Int = 0): Long {
        if (!file.exists() || depth > 16) return 0L
        if (file.isFile) return file.length()
        var length = 0L
        val files = file.listFiles() ?: return 0L
        for (f in files) {
            length += if (f.isFile) f.length() else calculateFolderSize(f, depth + 1)
        }
        return length
    }
}
