import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../models/video_item.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Diskten okunan kuyruk kaydının sonucunu taşır: kurtarılan görevler ve
/// çözülemediği için ATILAN kayıt sayısı. Atılan sayısı çağırana bildirilir,
/// çünkü sessizce kaybolan görev kullanıcı için "kuyruğum silindi" demektir.
class QueueLoadResult {
  final List<DownloadTask> tasks;
  final int droppedCount;
  const QueueLoadResult(this.tasks, this.droppedCount);
}

class DownloadQueueManager {
  static final DownloadQueueManager instance = DownloadQueueManager._internal();
  DownloadQueueManager._internal();

  static const String _tasksPrefKey = 'offline_youtube_persisted_tasks_v3';
  static const String _queuePausedPrefKey = 'offline_youtube_queue_paused_v3';

  /// Aynı görev için yapılacak en fazla otomatik tekrar sayısı.
  ///
  /// Sayı üç ayrı yere (karar koşulu, sayaç sınırı, kullanıcıya gösterilen
  /// metin) elle "2" olarak yazılmıştı. Biri değişip diğeri kaldığında görev ya
  /// hiç denenmez ya da kuyruğu sonsuza kadar döndürür; tek kaynak burasıdır.
  static const int maxRetries = 2;

  /// Kuyruk sağlık kontrolünün çalışma sıklığı.
  static const Duration watchdogInterval = Duration(seconds: 15);

  /// Native taraftan ilerleme olayı gelmeyi kestikten sonra indirmenin
  /// "asılmış" sayılacağı süre.
  ///
  /// yt-dlp bir DNS veya soket takılmasında %0.0'da saatlerce bekleyebiliyor;
  /// watchdog bunu hiç ölçmediği için görev sonsuza kadar `downloading` kalıyor
  /// ve kuyruk bir daha ilerlemiyordu. Eşik bilerek yüksek tutuldu: yt-dlp
  /// ffmpeg birleştirmesi sırasında stdout'a satır basmaz, kısa bir eşik sağlam
  /// bir indirmeyi birleştirme ortasında öldürürdü.
  static const Duration stallTimeout = Duration(minutes: 10);

  /// Ağ izni kontrolü için üst sınır.
  static const Duration _networkCheckTimeout = Duration(seconds: 5);

  /// Depolama ve süre kotası ölçümleri için üst sınır. Bu süre içinde
  /// bitmeyen ölçüm "kota doğrulanamadı" sayılır (bkz. [processNextQueue]).
  static const Duration _quotaMeasureTimeout = Duration(seconds: 20);

  /// startDownload kanal çağrısı için üst sınır.
  ///
  /// Çağrı yanıtsız kalırsa `isProcessingQueue` sonsuza kadar true kalır ve
  /// kuyruk kalıcı olarak kilitlenir: hiçbir katmanda zaman aşımı yoktu.
  static const Duration _startDownloadTimeout = Duration(seconds: 20);

  /// Tekrar denemenin ASLA işe yaramayacağı hata imzaları.
  ///
  /// Disk dolu (ENOSPC) da buraya aittir: geçici sanılıp üç kez tekrarlanıyor,
  /// her tekrar aynı dolu diske yazmaya çalışıp aynı hatayla yanıyordu.
  static const List<String> _permanentErrorSignatures = [
    'video unavailable',
    'this video is unavailable',
    'private video',
    'video is private',
    'removed by the uploader',
    'account associated with this video has been terminated',
    'members-only',
    'no space left on device',
    'enospc',
    'errno 28',
    'disk quota exceeded',
  ];

  /// Kalıcı imzalarla METİN OLARAK çakışan ama aslında geçici olan durumlar.
  /// Bunlar kalıcı listesinden ÖNCE bakılır.
  static const List<String> _transientErrorSignatures = [
    'service unavailable',
    'temporarily unavailable',
    'http error 5',
    'http error 429',
    'error 429',
    'too many requests',
    'rate limit',
    'timed out',
    'timeout',
    'connection reset',
    'connection refused',
    'network is unreachable',
    'temporary failure in name resolution',
  ];

  /// YouTube istek sınırı (HTTP 429) imzaları: geri çekilme süresi bu durumda
  /// çok daha uzun olmalıdır.
  static const List<String> _rateLimitSignatures = [
    'http error 429',
    'error 429',
    'too many requests',
    'rate limit',
  ];

  /// Hata metnini "tekrar denemenin anlamı var mı" sorusuna göre sınıflandırır.
  ///
  /// Eski filtre ham metinde `contains('unavailable')` arıyordu: yt-dlp'nin
  /// "HTTP Error 503: Service Unavailable" çıktısı bu filtreye takılıyor,
  /// GEÇİCİ bir sunucu hatası kalıcı sayılıp hiç tekrar denenmiyordu. Aynı
  /// filtredeki 'yayından kaldırılmış' koşulu ise ölüydü: yt-dlp mesajlarını
  /// İngilizce yazar, o koşul hiçbir zaman eşleşmez.
  static bool isPermanentError(String message) {
    final lower = message.toLowerCase();
    if (_transientErrorSignatures.any(lower.contains)) return false;
    return _permanentErrorSignatures.any(lower.contains);
  }

  /// Başarısız denemeden sonra kuyruğun ne kadar bekleyeceğini hesaplar.
  ///
  /// Sabit 3 saniyelik gecikme, istek sınırına (HTTP 429) takılan bir hesapta
  /// durumu kötüleştiriyordu: saniyeler içinde art arda giden istekler sınırı
  /// uzatıyor ve üç deneme de aynı hatayla yanıyordu. Üstel geri çekilmede her
  /// tekrar bir öncekinin iki katını bekler, 429'da taban süre çok daha uzundur.
  static int retryDelayMs(int retryCount, String errorMessage) {
    final lower = errorMessage.toLowerCase();
    final rateLimited = _rateLimitSignatures.any(lower.contains);
    final baseMs = rateLimited ? 30000 : 3000;
    final step = retryCount <= 1 ? 0 : (retryCount > 6 ? 5 : retryCount - 1);
    final delayMs = baseMs * (1 << step);
    return delayMs > 600000 ? 600000 : delayMs;
  }

  /// Bağlantı olayının "bağlandım" mı "koptum" mu olduğunu söyler.
  ///
  /// Dinleyici gelen değere hiç bakmıyordu, yani bağlantının KOPTUĞU olayda da
  /// kuyruk yeniden başlatılıyordu. "Tüm ağlar" modunda NetworkManager gerçek
  /// bağlantıyı sormadan izin verdiği için indirme kopuk hatta başlıyor ve
  /// görev boşuna hataya düşüyordu.
  static bool isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// İndirmenin asılıp asılmadığını söyler (son ilerleme olayının üzerinden
  /// [threshold] kadar geçtiyse asılmıştır).
  static bool isStalled(
    DateTime? lastProgressTime,
    DateTime now, {
    Duration threshold = stallTimeout,
  }) {
    if (lastProgressTime == null) return false;
    return now.difference(lastProgressTime) > threshold;
  }

  /// Tamamlanan görevin `.meta.json` dosyasının hangi dosyanın yanına
  /// yazılacağını belirler.
  ///
  /// Eşleştirme yt-dlp çıktı şablonuyla (`%(title).50s [%(id)s].%(ext)s`)
  /// birebir hizalıdır. Koşul gevşetilirse (örneğin video kimliği kontrolü
  /// düşerse) YANLIŞ videonun meta kaydı ezilir ve kütüphanede başka bir
  /// videonun başlığı/süresi görünür.
  static bool isDownloadedFileForVideo(String filePath, String videoId) {
    if (videoId.isEmpty) return false;
    if (filePath.endsWith('.meta.json')) return false;
    return filePath.contains('[$videoId].');
  }

  /// Diskten okunan kuyruk kaydını görevlere çevirir.
  ///
  /// Eski kod tüm listeyi TEK bir try/catch ile çözüyordu: sürüm yükseltmesinden
  /// kalan tek bir bozuk kayıt (örneğin tipi değişmiş bir alan) istisna
  /// fırlattığında catch bloğu `tasks.clear()` çağırıyor ve kullanıcının 40
  /// görevlik kuyruğunun TAMAMI sessizce siliniyordu. Artık kayıt başına
  /// çözülür, bozuk olan atlanır ve kaç kaydın kaybedildiği çağırana bildirilir.
  static QueueLoadResult parseStoredTasks(List<dynamic> decoded) {
    final loaded = <DownloadTask>[];
    var dropped = 0;
    for (final item in decoded) {
      try {
        final t = DownloadTask.fromJson(Map<String, dynamic>.from(item as Map));
        if (t.status == DownloadStatus.downloading) {
          // Süreç öldüğü için indirme yarım kaldı; kuyruğa geri al.
          t.status = DownloadStatus.queued;
          t.speed = '';
          t.lastProgressTime = null;
        } else if (t.status == DownloadStatus.fetchingMetadata) {
          // fetchingMetadata da tıpkı downloading gibi YARIM KALMIŞ bir geçiş
          // durumudur: metadata çekimini sürdürecek taraf öldü. Eski kod bunu
          // hiç kurtarmıyordu; görev "Bilgiler alınıyor..." başlığıyla sonsuza
          // kadar kuyrukta kalıyor, üstelik aynı video tekrar eklenemiyordu
          // ("zaten indirme listesinde mevcut"). Uygulamanın metadata çekimi
          // başarısız olduğunda ürettiği durumun aynısına düşürüyoruz ki
          // kullanıcı görsün ve "hataları yeniden dene" ile kurtarabilsin.
          t.status = DownloadStatus.error;
          t.hadPreviousError = true;
          t.errorMessage =
              'Video bilgileri alınamadan uygulama kapandı. Yeniden deneyin.';
        }
        loaded.add(t);
      } catch (_) {
        dropped++;
      }
    }
    return QueueLoadResult(loaded, dropped);
  }

  /// Native taraftan gelen 'started' ve 'progress' olayının uygulanıp
  /// uygulanmayacağına karar verir.
  ///
  /// yt-dlp süreci durdurulduktan sonra bile stdout okuyucusu gecikmiş bir ilerleme
  /// satırı teslim edebilir. Bu olay koşulsuz uygulanırsa, kullanıcının duraklattığı
  /// (veya iptal ettiği) görev sahte biçimde `downloading` durumuna döner ve
  /// [activeTaskId] yeniden dolar. O noktadan sonra [processNextQueue] her çağrıda
  /// erken döner ve süreç zaten öldüğü için durumu düzeltecek yeni bir olay da gelmez:
  /// kuyruk kalıcı olarak kilitlenir.
  ///
  /// Bu yüzden ilerleme yalnız görev gerçekten aktif olabilecek bir durumdayken uygulanır.
  static bool shouldApplyProgressEvent(DownloadStatus current) {
    switch (current) {
      case DownloadStatus.queued:
      case DownloadStatus.fetchingMetadata:
      case DownloadStatus.downloading:
        return true;
      case DownloadStatus.paused:
      case DownloadStatus.completed:
      case DownloadStatus.error:
      case DownloadStatus.cancelled:
        return false;
    }
  }

  /// Native 'cancelled' olayının uygulanıp uygulanmayacağına karar verir.
  ///
  /// Watchdog asılı kalan indirmeyi native tarafta iptal eder ve görevi ya
  /// yeniden denenmek üzere `queued` yapar ya da (sınır dolduysa) `error`
  /// olarak işaretler. Native taraf iptali onaylayan bir 'cancelled' olayı
  /// gönderir; bu olay koşulsuz uygulanırsa kuyruğa yeni alınmış görev
  /// `cancelled` olup bir daha ASLA indirilmez, hataya düşen görev de
  /// "hataları yeniden dene" kapsamından sessizce çıkar.
  ///
  /// Kullanıcının gerçek iptalinde ([cancelTask]) görev zaten yerel olarak
  /// `cancelled` yapılır, yani bu kapı kullanıcı iptalinden hiçbir şey
  /// eksiltmez.
  static bool shouldApplyCancelEvent(DownloadStatus current) {
    switch (current) {
      case DownloadStatus.queued:
      case DownloadStatus.error:
        return false;
      case DownloadStatus.fetchingMetadata:
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
      case DownloadStatus.completed:
      case DownloadStatus.cancelled:
        return true;
    }
  }

  final List<DownloadTask> tasks = [];
  bool isProcessingQueue = false;
  String? activeTaskId;
  bool isQueuePaused = false;
  bool isWifiWaiting = false;
  bool isLoaded = false;

  /// Diskten yüklerken çözülemediği için ATILAN kayıt sayısı. Sıfırdan
  /// büyükse kullanıcıya bir kez uyarı gösterilmelidir; sessiz kayıp,
  /// kullanıcının kuyruğa tekrar eklemediği kayıp demektir.
  int droppedTaskCount = 0;

  /// Kuyruk kaydının tamamı okunamadıysa (JSON'un kendisi bozuksa) true.
  bool queueRecordUnreadable = false;

  /// Kuyruk neden ilerleyemiyor (ağ yok, kota dolu, kota ölçülemedi, servis
  /// başlatılamadı). Engel geçici olduğunda görevler `queued` bırakılır ve
  /// neden burada tutulur; aksi hâlde her başarısız ön kontrol bir görevi
  /// kalıcı hataya yakıyor ve kuyruk gece boyunca eriyordu. null = engel yok.
  String? blockReason;

  AppSettings? lastSettings;

  Timer? _watchdogTimer;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectivitySubscription;

  StreamController<void> _updateController = StreamController<void>.broadcast();
  Stream<void> get onUpdate => _updateController.stream;
  
  void Function()? onLibraryNeedsRefresh;
  
  void notifyListeners() {
    if (!_updateController.isClosed) {
      _updateController.add(null);
    }
  }

  int get activeDownloadCount => activeTaskId != null ? 1 : 0;
  bool get isDownloadingActive => activeTaskId != null;
  DownloadTask? get activeTask {
    if (activeTaskId == null) return null;
    try {
      return tasks.firstWhere((t) => t.id == activeTaskId);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    if (isLoaded) return;
    if (_updateController.isClosed) {
      _updateController = StreamController<void>.broadcast();
    }
    await _loadTasksFromStorage();
    _listenToConnectivity();
    _listenToNativeEvents();
    _startWatchdogTimer();
    isLoaded = true;
    notifyListeners();
  }

  void dispose() {
    isLoaded = false;
    _watchdogTimer?.cancel();
    _eventSubscription?.cancel();
    _connectivitySubscription?.cancel();
    if (!_updateController.isClosed) {
      _updateController.close();
    }
  }

  void onAppResumed() {
    if (isLoaded && !isQueuePaused) {
      processNextQueue();
    }
  }

  Future<void> onSettingsChanged(AppSettings settings) async {
    lastSettings = settings;
    if (!isQueuePaused) {
      await processNextQueue(settings: settings);
    }
  }

  Future<void> saveTasksToStorage() async {
    // Kuyruk diskten YÜKLENMEDEN yazma yapılmaz. Aksi hâlde bellekteki henüz boş olan
    // liste kullanıcının kayıtlı kuyruğunu ezer. İki gerçek yol vardı:
    //   1. DownloadProvider constructor'ı init() çağrısını await etmiyor, yani
    //      _loadTasksFromStorage bitmeden bir kayıt tetiklenebiliyor.
    //   2. WorkManager arka plan izolatı kendi DownloadQueueManager örneğini kurup
    //      aynı SharedPreferences anahtarına yazıyor.
    // Yazmamak veri kaybettirmez, yanlış yazmak kaybettirir.
    if (!isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = tasks.map((t) => t.toJson()).toList();
      await prefs.setString(_tasksPrefKey, jsonEncode(jsonList));
      await prefs.setBool(_queuePausedPrefKey, isQueuePaused);
    } catch (e) {
      // Storage error
    }
  }

  Future<void> _loadTasksFromStorage() async {
    droppedTaskCount = 0;
    queueRecordUnreadable = false;
    try {
      final prefs = await SharedPreferences.getInstance();

      isQueuePaused = prefs.getBool(_queuePausedPrefKey) ?? false;

      final tasksJson = prefs.getString(_tasksPrefKey);
      if (tasksJson != null) {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        final result = parseStoredTasks(decoded);
        tasks
          ..clear()
          ..addAll(result.tasks);
        droppedTaskCount = result.droppedCount;
      }
    } catch (e) {
      // Buraya yalnız kaydın TAMAMI okunamadığında düşülür (yarıda kesilmiş
      // yazma sonrası bozuk JSON gibi). Tek bir bozuk görev artık tüm kuyruğu
      // silmiyor, onu parseStoredTasks tek tek eliyor.
      tasks.clear();
      queueRecordUnreadable = true;
    }
  }

  void _listenToConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        // Bağlantının KOPTUĞUNU bildiren olayda kuyruğu yeniden başlatma
        // (bkz. isOnline): kopuk hatta başlatılan indirme boşuna hataya düşer.
        if (!isOnline(results)) return;
        _evaluateConditionsAndAutoResume();
      },
      onError: (Object error, StackTrace stackTrace) {
        // Abonelik çıplaktı: akış hata verirse otomatik devam etme mekanizması
        // sessizce ölür, kullanıcı Wi-Fi'a bağlansa da kuyruk kendiliğinden
        // ilerlemez ve neden olduğu hiçbir yerde görünmezdi.
        if (kDebugMode) {
          print('Connectivity stream error: $error');
        }
      },
      onDone: () {
        if (kDebugMode) {
          print('Connectivity stream closed');
        }
      },
    );
  }

  Future<void> _evaluateConditionsAndAutoResume() async {
    if (isQueuePaused || isProcessingQueue) return;
    if (tasks.isEmpty || !tasks.any((t) => t.status == DownloadStatus.queued)) return;

    if (lastSettings != null) {
      // Kontrolün zaman aşımı yoktu: yanıtsız kalan bir çağrı bu akışı sonsuza
      // kadar askıda bırakır ve bağlantı geri geldiğinde kuyruk uyanmaz.
      final netCheck = await NetworkManager.instance
          .checkNetworkPermissionAndStatus(lastSettings!)
          .timeout(_networkCheckTimeout, onTimeout: () => {'allowed': false});
      if (netCheck['allowed'] == true) {
        isWifiWaiting = false;
        notifyListeners();
        await processNextQueue(settings: lastSettings);
      }
    }
  }

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(watchdogInterval, (timer) async {
      if (isQueuePaused) return;

      final downloadingTasks = tasks.where((t) => t.status == DownloadStatus.downloading).toList();

      if (downloadingTasks.isEmpty) {
        if (activeTaskId != null) {
          activeTaskId = null;
          notifyListeners();
        }
        final hasQueued = tasks.any((t) => t.status == DownloadStatus.queued);
        if (hasQueued && !isProcessingQueue) {
          processNextQueue();
        }
      } else {
        bool needsUpdate = false;
        bool filledMissingProgressTime = false;
        final now = DateTime.now();
        for (final t in downloadingTasks) {
          if (t.lastProgressTime == null) {
            // If lastProgressTime is somehow null but it's downloading, set it to now.
            t.lastProgressTime = now;
            needsUpdate = true;
            filledMissingProgressTime = true;
            continue;
          }
          if (!isStalled(t.lastProgressTime, now)) continue;

          // Takılma tespiti hiç uygulanmamıştı: ölçüt vardı (lastProgressTime)
          // ama kimse bakmıyordu. yt-dlp DNS/soket takılmasında %0.0'da asılınca
          // görev saatlerce `downloading` kalıyor, activeTaskId dolu olduğu için
          // processNextQueue her çağrıda erken dönüyor ve kuyruk hiç ilerlemiyordu.
          //
          // Durum ÖNCE değiştirilir, native iptal SONRA gönderilir: sıra ters
          // olsaydı yanıtsız kalan bir iptal çağrısı görevi `downloading`
          // bırakır ve her watchdog turu aynı görev için yeni bir iptal daha
          // yollardı. Gecikmiş 'cancelled' onayının görevi öldürmesini
          // shouldApplyCancelEvent engelliyor.
          if (activeTaskId == t.id) {
            activeTaskId = null;
          }
          t.speed = '';
          t.lastProgressTime = null;
          if (t.retryCount < maxRetries) {
            t.retryCount++;
            t.status = DownloadStatus.queued;
            t.errorMessage =
                'İndirme yanıt vermedi, yeniden deneniyor (${t.retryCount}/$maxRetries)...';
          } else {
            t.status = DownloadStatus.error;
            t.hadPreviousError = true;
            t.errorMessage =
                'İndirme yanıt vermediği için durduruldu (${stallTimeout.inMinutes} dakika boyunca ilerleme yok).';
          }
          needsUpdate = true;
          await NativeBridge.instance.cancelDownload(t.id);
        }
        if (needsUpdate) {
          saveTasksToStorage();
          notifyListeners();
        }
        // Takılan görev iptal edildikten sonra kuyruk BİLEREK hemen tetiklenmez:
        // native taraf iptali onaylayan 'cancelled' olayını yollamak üzeredir ve
        // görev yeniden başlatılırsa o olay taze indirmeyi öldürebilir. Bir
        // sonraki watchdog turu (15 sn) görevi zaten kuyruktan alacak.
        if (filledMissingProgressTime) {
          _triggerNextQueue();
        }
      }
    });
  }

  void _listenToNativeEvents() {
    _eventSubscription = NativeBridge.instance.downloadEvents.listen(
      (event) async {
        final data = Map<String, dynamic>.from(event);
        final status = data['type'] as String?;
        final taskId = data['taskId'] as String?;

        if (status == null || taskId == null) return;

        final taskIndex = tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex == -1) {
          if (status == 'downloading') {
            await NativeBridge.instance.cancelDownload(taskId);
          }
          return;
        }

        final task = tasks[taskIndex];

        switch (status) {
          case 'started':
          case 'progress':
            // Duraklatılan veya iptal edilen görevin ölmekte olan sürecinden gelen
            // gecikmiş olay görevi diriltmemeli (bkz. shouldApplyProgressEvent).
            if (!shouldApplyProgressEvent(task.status)) break;
            task.status = DownloadStatus.downloading;
            task.progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
            task.speed = data['speed']?.toString() ?? '';
            
            task.totalSize = data['totalSize']?.toString();
            task.downloadedSize = data['downloadedSize']?.toString();
            
            final etaVal = data['eta'];
            if (etaVal is num) {
              task.etaSeconds = etaVal.toInt();
            } else if (etaVal is String && etaVal.contains(':')) {
              final parts = etaVal.split(':');
              try {
                if (parts.length == 2) {
                  task.etaSeconds = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
                } else if (parts.length == 3) {
                  task.etaSeconds = (int.tryParse(parts[0]) ?? 0) * 3600 + (int.tryParse(parts[1]) ?? 0) * 60 + (int.tryParse(parts[2]) ?? 0);
                }
              } catch (_) {}
            }
            task.lastProgressTime = DateTime.now();
            activeTaskId = taskId;
            notifyListeners();
            break;

          case 'completed':
            task.status = DownloadStatus.completed;
            task.progress = 100.0;
            task.speed = '';
            task.etaSeconds = 0;
            
            if (activeTaskId == taskId) {
              activeTaskId = null;
            }
            saveTasksToStorage();

            // Kaydedilen videonun metadata'sını .meta.json'a yaz (böylece playlistUrl kalıcı olur)
            try {
              final vid = VideoItem.extractVideoId(task.url);
              if (vid != null) {
                final dir = Directory(StorageManager.instance.currentDownloadPath);
                if (dir.existsSync()) {
                  final files = dir.listSync();
                  for (final file in files) {
                    if (file is File && isDownloadedFileForVideo(file.path, vid)) {
                      await StorageManager.instance.saveVideoMetadata(
                        file.path,
                        url: task.url,
                        playlistUrl: task.sourcePlaylistUrl,
                        title: task.title,
                        uploader: task.uploader,
                        uploadDate: task.uploadDate,
                        durationSeconds: task.durationSeconds,
                      );
                      break;
                    }
                  }
                }
              }
            } catch (e) {
              if (kDebugMode) print('Meta save error: $e');
            }
            
            if (onLibraryNeedsRefresh != null) {
              onLibraryNeedsRefresh!();
            }
            
            notifyListeners();
            _triggerNextQueue(delayMs: 2000);
            break;

          case 'error':
            final errorMessage = data['error'] as String? ?? 'Bilinmeyen hata';
            if (!isPermanentError(errorMessage) && task.retryCount < maxRetries) {
              task.retryCount++;
              task.status = DownloadStatus.queued;
              task.errorMessage =
                  'Hata oluştu, tekrar deneniyor (${task.retryCount}/$maxRetries)...';
              if (activeTaskId == taskId) {
                activeTaskId = null;
              }
              saveTasksToStorage();
              notifyListeners();
              _triggerNextQueue(delayMs: retryDelayMs(task.retryCount, errorMessage));
            } else {
              task.status = DownloadStatus.error;
              task.hadPreviousError = true;
              task.errorMessage = errorMessage;
              task.speed = '';
              if (activeTaskId == taskId) {
                activeTaskId = null;
              }
              saveTasksToStorage();
              notifyListeners();
              _triggerNextQueue(delayMs: 1500);
            }
            break;

          case 'cancelled':
            // Watchdog'un yeniden denenmek üzere kuyruğa aldığı görevi, native
            // tarafın gecikmiş iptal onayı öldürmemeli (bkz. shouldApplyCancelEvent).
            if (!shouldApplyCancelEvent(task.status)) break;
            task.status = DownloadStatus.cancelled;
            task.speed = '';
            if (activeTaskId == taskId) {
              activeTaskId = null;
            }
            saveTasksToStorage();
            notifyListeners();
            _triggerNextQueue();
            break;
        }
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          print('Native event stream error: $error');
        }
        for (final t in tasks.where((t) => t.status == DownloadStatus.downloading)) {
          t.status = DownloadStatus.error;
          t.hadPreviousError = true;
          t.errorMessage = 'Platform kanalı hatası: $error';
          if (activeTaskId == t.id) activeTaskId = null;
        }
        saveTasksToStorage();
        notifyListeners();
      },
      onDone: () {
        if (kDebugMode) {
          print('Native event stream closed');
        }
      },
    );
  }

  void _triggerNextQueue({int delayMs = 1200}) {
    if (isQueuePaused) return;

    Future.delayed(Duration(milliseconds: delayMs), () async {
      if (isQueuePaused) return;

      final hasQueuedTasks = tasks.any((t) => t.status == DownloadStatus.queued);

      if (hasQueuedTasks) {
        processNextQueue();
      }
    });
  }

  Future<void> pauseQueue() async {
    isQueuePaused = true;
    if (activeTaskId != null) {
      final currentId = activeTaskId!;
      activeTaskId = null;
      final idx = tasks.indexWhere((t) => t.id == currentId);
      if (idx != -1) {
        tasks[idx].status = DownloadStatus.paused;
        tasks[idx].speed = '';
      }
      await NativeBridge.instance.pauseDownload(currentId);
    }

    for (final t in tasks) {
      if (t.status == DownloadStatus.downloading) {
        t.status = DownloadStatus.paused;
        t.speed = '';
      }
    }

    await NativeBridge.instance.stopDownloadService();
    await saveTasksToStorage();
    notifyListeners();
  }

  Future<void> resumeQueue({AppSettings? settings}) async {
    isQueuePaused = false;

    for (final t in tasks) {
      if (t.status == DownloadStatus.paused || t.status == DownloadStatus.error) {
        t.status = DownloadStatus.queued;
        t.errorMessage = null;
        t.retryCount = 0;
      }
    }

    await saveTasksToStorage();
    notifyListeners();

    await processNextQueue(settings: settings ?? lastSettings);
  }

  Future<void> processNextQueue({AppSettings? settings}) async {
    if (isQueuePaused) return;
    if (isProcessingQueue) return;

    isProcessingQueue = true;
    try {
      final currentSettings = settings ?? lastSettings;
      if (currentSettings == null) {
        // Ayarlar yüklenmeden indirmeye başlamak, "Sadece Wi-Fi" tercihini ve GB
        // kotasını o tur için TAMAMEN atlar: watchdog 15 saniyede bir tetiklendiği
        // için soğuk açılışta yavaş bir SharedPreferences yüklemesi indirmenin
        // mobil veriden başlamasına yeter. Kapının yokluğu izin değildir.
        _blockQueue('Ayarlar henüz yüklenmedi, kuyruk bekletiliyor.');
        return;
      }
      lastSettings = currentSettings;

      final netCheck = await NetworkManager.instance
          .checkNetworkPermissionAndStatus(currentSettings)
          .timeout(_networkCheckTimeout,
              onTimeout: () => {'allowed': false, 'reason': 'Ağ kontrolü zaman aşımına uğradı.'});
      if (netCheck['allowed'] != true) {
        isWifiWaiting = currentSettings.networkMode == NetworkRestrictionMode.anyWifi;
        _blockQueue(netCheck['reason'] as String? ?? 'Ağ izni yok.');
        return;
      }
      isWifiWaiting = false;

      // Kota ölçümleri zaman aşımında GÜVENLİ tarafa düşer. Eskiden ölçüm
      // başarısız olunca kullanım 0 sayılıyordu (onTimeout: () => 0 / => []) ve
      // her iki kota da tam kütüphane büyüdüğü, yani ölçümün yavaşladığı anda
      // AÇILIYORDU. Doğrulanamayan kota, dolmuş kota gibi ele alınır.
      final maxBytes = currentSettings.maxStorageLimitGB * 1024 * 1024 * 1024;
      final int? usedBytes = await StorageManager.instance
          .getUsedStorageBytes()
          .then<int?>((value) => value)
          .timeout(_quotaMeasureTimeout, onTimeout: () => null);
      if (usedBytes == null) {
        _blockQueue(
            'Depolama kullanımı ölçülemedi (zaman aşımı). Kota doğrulanamadığı için indirme başlatılmadı.');
        return;
      }
      if (usedBytes >= maxBytes) {
        _blockQueue('Depolama kotası doldu (${currentSettings.maxStorageLimitGB} GB).');
        return;
      }

      final List<VideoItem>? downloadedVideos = await StorageManager.instance
          .scanDownloadedVideos()
          .then<List<VideoItem>?>((value) => value)
          .timeout(_quotaMeasureTimeout, onTimeout: () => null);
      if (downloadedVideos == null) {
        _blockQueue(
            'Kütüphane taraması zaman aşımına uğradı. Süre kotası doğrulanamadığı için indirme başlatılmadı.');
        return;
      }
      final totalDurationSec =
          downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = currentSettings.maxVideoDurationHours * 3600;
      if (totalDurationSec >= maxDurationSec) {
        _blockQueue('Video süresi kotası doldu (${currentSettings.maxVideoDurationHours} saat).');
        return;
      }

      if (isQueuePaused) return;
      blockReason = null;

      if (activeTaskId != null) {
        final activeIndex = tasks.indexWhere((t) => t.id == activeTaskId);
        if (activeIndex != -1 && tasks[activeIndex].status == DownloadStatus.downloading) {
          return;
        }
      }

      final nextTaskIndex = tasks.indexWhere((t) => t.status == DownloadStatus.queued);

      if (nextTaskIndex == -1) {
        if (!isDownloadingActive) {
          NativeBridge.instance.stopDownloadService();
        }
        return;
      }

      final nextTask = tasks[nextTaskIndex];
      activeTaskId = nextTask.id;
      nextTask.status = DownloadStatus.downloading;
      nextTask.errorMessage = null;
      nextTask.lastProgressTime = DateTime.now();
      notifyListeners();
      saveTasksToStorage();

      // Kanal çağrısının kendi zaman aşımı yoktu: yanıt gelmezse bu await
      // sonsuza kadar askıda kalır, `finally` hiç çalışmaz ve isProcessingQueue
      // true kaldığı için kuyruk KALICI olarak kilitlenir.
      final started = await NativeBridge.instance
          .startDownload(
            taskId: nextTask.id,
            url: nextTask.url,
            title: nextTask.title,
            outputPath: StorageManager.instance.currentDownloadPath,
          )
          .timeout(_startDownloadTimeout, onTimeout: () => false);

      if (!started) {
        // Görevi kalıcı hataya düşürmek tüm kuyruğu zincirleme yakıyordu:
        // Android 12+ uygulama arka plandayken ön plan servisini reddeder
        // (FGS_NOT_ALLOWED), her reddedilen görev error olur, _triggerNextQueue
        // hemen sıradakini dener ve o da yanar. Başlatma hatası GEÇİCİDİR:
        // görevi kuyrukta bırak, nedeni bildir, uygulama ön plana dönünce
        // (onAppResumed) veya bir sonraki watchdog turunda kendiliğinden denensin.
        nextTask.status = DownloadStatus.queued;
        nextTask.speed = '';
        nextTask.lastProgressTime = null;
        activeTaskId = null;
        _blockQueue(
            'İndirme servisi başlatılamadı. Uygulama ön plana alınınca otomatik yeniden denenecek.');
        saveTasksToStorage();
      }
    } finally {
      isProcessingQueue = false;
    }
  }

  /// Kuyruğu geçici bir engel yüzünden ilerletmez ve nedenini kaydeder.
  ///
  /// Eskiden her başarısız ön kontrol sıradaki görevi KALICI hataya düşürüyordu
  /// (_failNextTaskIfAny). Watchdog 15 saniyede, arka plan senkronu 15 dakikada
  /// bir tetiklendiği için "Sadece Wi-Fi" modunda geçen bir gece kuyruğun
  /// tamamını hataya çeviriyordu; sabah Wi-Fi'a bağlanan kullanıcının kuyruğu
  /// kendiliğinden devam etmiyordu. Geçici koşul görevi yakmaz, sadece bekletir.
  void _blockQueue(String reason) {
    blockReason = reason;
    notifyListeners();
  }

  Future<void> retryAllErrors({AppSettings? settings}) async {
    for (final task in tasks) {
      if (task.status == DownloadStatus.error) {
        task.status = DownloadStatus.queued;
        task.errorMessage = null;
        task.retryCount = 0;
      }
    }
    await saveTasksToStorage();
    notifyListeners();
    await processNextQueue(settings: settings ?? lastSettings);
  }

  Future<void> pauseTask(String taskId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      tasks[index].status = DownloadStatus.paused;
      tasks[index].speed = '';
      if (activeTaskId == taskId) {
        activeTaskId = null;
      }
      saveTasksToStorage();
      notifyListeners();
      await NativeBridge.instance.pauseDownload(taskId);
    }
  }

  Future<void> resumeTask(String taskId, [AppSettings? settings]) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      tasks[index].status = DownloadStatus.queued;
      tasks[index].errorMessage = null;
      saveTasksToStorage();
      notifyListeners();

      if (!isQueuePaused) {
        await processNextQueue(settings: settings ?? lastSettings);
      }
    }
  }

  Future<void> cancelTask(String taskId) async {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      tasks[index].status = DownloadStatus.cancelled;
      tasks[index].speed = '';
      if (activeTaskId == taskId) {
        activeTaskId = null;
      }
      saveTasksToStorage();
      notifyListeners();
      await NativeBridge.instance.cancelDownload(taskId);
      _triggerNextQueue();
    }
  }

  Future<void> removeTask(String taskId) async {
    if (activeTaskId == taskId) {
      await NativeBridge.instance.cancelDownload(taskId);
      activeTaskId = null;
    }
    tasks.removeWhere((t) => t.id == taskId);
    saveTasksToStorage();
    notifyListeners();
    if (activeTaskId == null) {
      _triggerNextQueue();
    }
  }

  void prioritizeTask(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = tasks[index];
    
    if (index == 0 || task.status == DownloadStatus.downloading || task.id == activeTaskId) return;

    tasks.removeAt(index);
    
    int insertIndex = 0;
    if (activeTaskId != null) {
      final activeIndex = tasks.indexWhere((t) => t.id == activeTaskId);
      if (activeIndex != -1) {
        insertIndex = activeIndex + 1;
      }
    }
    
    tasks.insert(insertIndex, task);
    saveTasksToStorage();
    notifyListeners();
  }

  void clearErrors() {
    tasks.removeWhere((t) => t.status == DownloadStatus.error);
    saveTasksToStorage();
    notifyListeners();
  }

  void clearCompleted() {
    tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled);
    saveTasksToStorage();
    notifyListeners();
  }
}
