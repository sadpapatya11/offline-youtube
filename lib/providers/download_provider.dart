import 'dart:async';
import 'package:flutter/widgets.dart';
import '../services/youtube_api_service.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../models/video_item.dart';
import '../models/playlist_entry.dart';
import '../providers/library_provider.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';
import '../services/download_queue_manager.dart';

class PlaylistSyncResult {
  final bool success;
  final int newVideosAdded;
  final int deletedVideosRemoved;
  final String? message;

  const PlaylistSyncResult({
    required this.success,
    this.newVideosAdded = 0,
    this.deletedVideosRemoved = 0,
    this.message,
  });
}

class DownloadProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const int maxPlaylistEntries = 250;
  static const int defaultVideoDurationSeconds = 180;

  /// Eşitleme turunda eklenen görevler için ÇAKIŞMAYAN kimlik üretir.
  ///
  /// Döngü senkron çalıştığı için [epochMs] aynı turdaki tüm görevlerde aynı olur;
  /// benzersizliği sağlayan tek şey [index]'tir. Sabit bir son ek kullanılırsa
  /// aynı turda eklenen görevlerin hepsi aynı kimliği alır ve kuyruktan tek bir
  /// videoyu silmek hepsini birden siler.
  static String buildSyncTaskId(int epochMs, int index) => '${epochMs}_jit_$index';

  /// Toplam süre kotası ZATEN dolu mu (eklenecek videonun süresine bakmadan).
  ///
  /// Kota kuralı üç ayrı ekleme yolunda satır içi yazıldığı sürece hiçbir test onu
  /// koruyamıyordu: kapıyı komple açan bir mutasyon tüm paketi yeşil bırakıyordu.
  /// Kural artık tek yerde tanımlı ve doğrudan test edilebilir.
  static bool isDurationQuotaFull({
    required int currentTotalSeconds,
    required int maxDurationSeconds,
  }) =>
      currentTotalSeconds >= maxDurationSeconds;

  /// Süresi [videoSeconds] olan bir video toplam süre kotasına sığıyor mu.
  ///
  /// [videoSeconds] sıfır veya negatifse süre BİLİNMİYOR demektir. Bilinmeyen süre
  /// kapıyı kapatmaz: yoksa süresi okunamayan tek bir video yüzünden ekleme yolu
  /// tamamen tıkanırdı. Toplu ekleme yollarında bilinmeyen süre yerine
  /// [effectiveDurationSeconds] tahmini geçilir, çünkü orada "bilinmiyor"u sıfır
  /// saymak kotayı yüzlerce video boyunca sessizce deler.
  static bool fitsInDurationQuota({
    required int currentTotalSeconds,
    required int videoSeconds,
    required int maxDurationSeconds,
  }) {
    if (videoSeconds <= 0) return true;
    return currentTotalSeconds + videoSeconds <= maxDurationSeconds;
  }

  /// Kota hesabında kullanılacak süre.
  ///
  /// `--flat-playlist` girdilerin çoğunda süre döndürmez. Bilinmeyen süreyi sıfır
  /// saymak, oynatma listesi ve eşitleme yollarında kotayı tamamen etkisiz kılar:
  /// 200 videoluk bir liste "toplam 0 saniye" sayılıp olduğu gibi kuyruğa girer.
  static int effectiveDurationSeconds(int rawSeconds) =>
      rawSeconds > 0 ? rawSeconds : defaultVideoDurationSeconds;

  /// Eşitleme sırasında bir videonun veya görevin kaldırılıp kaldırılmayacağına karar verir.
  ///
  /// Kritik kural: karar YALNIZ çevrimiçi listesi BAŞARIYLA çekilebilmiş oynatma
  /// listeleri için verilebilir. Bir liste ağ hatası, 429 veya botguard yüzünden
  /// çekilemediyse o listenin içeriği bilinmiyor demektir; "listede görünmüyor" bilgisi
  /// yoktur, dolayısıyla yokluğu silme gerekçesi sayılamaz. Aksi hâlde geçici bir ağ
  /// kesintisi kullanıcının indirilmiş kütüphanesini çöpe atar ve kuyruğunu siler.
  static bool shouldRemoveFromSync({
    required String? sourcePlaylistUrl,
    required Set<String> successfulPlaylists,
    required bool stillOnline,
  }) {
    if (sourcePlaylistUrl == null || sourcePlaylistUrl.isEmpty) return false;
    if (!successfulPlaylists.contains(sourcePlaylistUrl)) return false;
    return !stillOnline;
  }

  /// Eşitleme turunda çekilemeyen listeler için kullanıcıya gösterilecek uyarı.
  ///
  /// Çekim hatası yutulduğunda kullanıcı yalnız "Eşitleme tamamlandı" görüyordu:
  /// listedeki yeni videolar gelmediğinde bunun ağ kesintisi mi yoksa YouTube'da
  /// gerçekten değişiklik olmaması mı olduğunu ayırt edemiyordu. Hata sayısı sıfırsa
  /// `null` döner, böylece başarılı turda mesaj kirliliği olmaz.
  static String? buildSyncFailureNotice({
    required int attemptedCount,
    required int failedCount,
  }) {
    if (failedCount <= 0) return null;
    if (attemptedCount > 0 && failedCount >= attemptedCount) {
      return 'Hiçbir oynatma listesi çekilemedi (ağ veya YouTube hatası). '
          'Güvenlik gereği hiçbir video silinmedi.';
    }
    return '$attemptedCount listeden $failedCount tanesi çekilemedi. '
        'Çekilemeyen listelere ait videolar güvenlik gereği silinmedi.';
  }

  final DownloadQueueManager _manager = DownloadQueueManager.instance;
  StreamSubscription? _updateSub;
  bool _disposed = false;
  bool _isSyncingPlaylists = false;

  /// Dispose edilmiş provider'da dinleyici uyarmayı engeller.
  ///
  /// [syncSavedPlaylists] onlarca saniye sürebilen ağ turları yapar (her kayıtlı
  /// liste için yt-dlp çekimi, eksik tarihler için ayrıca metadata). Kullanıcı bu
  /// sırada uygulamadan çıkarsa veya provider ağacı yeniden kurulursa dispose
  /// çalışır; ağ işi bittiğinde çıplak notifyListeners "dispose edilmiş nesne
  /// kullanıldı" hatası fırlatır ve arka plan turu ekranı kırmızıya boyar.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<DownloadTask> get tasks => _manager.tasks;
  bool get isProcessingQueue => _manager.isProcessingQueue;
  String? get activeTaskId => _manager.activeTaskId;
  bool get isQueuePaused => _manager.isQueuePaused;
  bool get isWifiWaiting => _manager.isWifiWaiting;
  bool get isLoaded => _manager.isLoaded;
  bool get isSyncingPlaylists => _isSyncingPlaylists;

  /// Kuyruğun neden ilerlemediği; engel yoksa null.
  ///
  /// Bu geçit olmadan sinyal ölüydü: [DownloadQueueManager] geçici engelde
  /// (ağ izni yok, kota ölçülemedi, ön plan servisi reddetti) artık sıradaki
  /// görevi hataya DÜŞÜRMÜYOR, `queued` bırakıp nedeni `blockReason`'a yazıyor.
  /// Neden hiçbir ekrana taşınmazsa kuyruk kullanıcıya sebepsiz donmuş görünür:
  /// eskiden hiç değilse kırmızı bir hata satırı çıkıyordu.
  String? get blockReason => _manager.blockReason;

  /// Diskten yüklenirken çözülemediği için ATILAN görev sayısı.
  int get droppedTaskCount => _manager.droppedTaskCount;

  /// Kuyruk kaydının tamamı okunamadıysa true.
  bool get queueRecordUnreadable => _manager.queueRecordUnreadable;

  /// Kullanıcı açılıştaki kayıp uyarısını gördü; bir daha gösterilmez.
  ///
  /// Bayrakları temizlemek yalnız gösterim kararını etkiler, kuyruk verisine
  /// dokunmaz; yeniden yükleme olduğunda [DownloadQueueManager] ikisini de
  /// baştan hesaplar.
  void acknowledgeQueueLoadNotice() {
    _manager.droppedTaskCount = 0;
    _manager.queueRecordUnreadable = false;
    _safeNotify();
  }

  int get queuedCount => _manager.tasks.where((t) => t.status == DownloadStatus.queued).length;
  int get downloadingCount => _manager.tasks.where((t) => t.status == DownloadStatus.downloading).length;
  int get completedCount => _manager.tasks.where((t) => t.status == DownloadStatus.completed).length;

  int get activeDownloadCount => _manager.activeDownloadCount;
  bool get isDownloadingActive => _manager.isDownloadingActive;
  DownloadTask? get activeTask => _manager.activeTask;

  void Function()? get onLibraryNeedsRefresh => _manager.onLibraryNeedsRefresh;
  set onLibraryNeedsRefresh(void Function()? callback) => _manager.onLibraryNeedsRefresh = callback;

  DownloadProvider() {
    WidgetsBinding.instance.addObserver(this);
    _manager.init();
    _updateSub = _manager.onUpdate.listen((_) {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _updateSub?.cancel();
    _manager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _manager.onAppResumed();
    }
  }

  Future<void> onSettingsChanged(AppSettings settings) async {
    await _manager.onSettingsChanged(settings);
  }

  Future<void> pauseQueue() => _manager.pauseQueue();
  Future<void> resumeQueue({AppSettings? settings}) => _manager.resumeQueue(settings: settings);
  Future<void> processNextQueue({AppSettings? settings}) => _manager.processNextQueue(settings: settings);
  Future<void> retryAllErrors({AppSettings? settings}) => _manager.retryAllErrors(settings: settings);
  Future<void> pauseTask(String taskId) => _manager.pauseTask(taskId);
  Future<void> resumeTask(String taskId, [AppSettings? settings]) => _manager.resumeTask(taskId, settings);
  Future<void> cancelTask(String taskId) => _manager.cancelTask(taskId);
  Future<void> removeTask(String taskId) => _manager.removeTask(taskId);
  void prioritizeTask(String taskId) => _manager.prioritizeTask(taskId);
  void clearErrors() => _manager.clearErrors();
  void clearCompleted() => _manager.clearCompleted();

  // --- 5. URL DOĞRULAMA VE HATA TEMİZLEME ---

  static String? extractYouTubeUrl(String input) {
    final regex = RegExp(r'(https?://[^\s]+)');
    final match = regex.firstMatch(input);
    if (match != null) {
      final url = match.group(0);
      if (url != null) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
          final host = uri.host.toLowerCase();
          final validHosts = [
            'youtube.com', 'www.youtube.com', 'm.youtube.com',
            'music.youtube.com', 'youtu.be',
          ];
          if (validHosts.contains(host) || host.endsWith('.youtube.com')) {
            if (uri.path.isNotEmpty) return url;
          }
        }
      }
    }
    
    final cleanInput = input.trim();
    if (!cleanInput.toLowerCase().startsWith('http')) {
      var rawId = cleanInput.split('&')[0].split('?')[0];
      if (RegExp(r'^[a-zA-Z0-9_-]{10,12}$').hasMatch(rawId)) {
        return 'https://youtu.be/$rawId';
      }
    }
    return null;
  }

  static bool isValidYouTubeUrl(String input) {
    return extractYouTubeUrl(input) != null;
  }

  static bool isPlaylistUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('list=') ||
        lower.contains('/playlist') ||
        lower.contains('/@') ||
        lower.contains('/channel/') ||
        lower.contains('/c/') ||
        lower.contains('/user/');
  }

  static bool isNetworkRelatedError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('no address associated with hostname') ||
        lower.contains('network is unreachable') ||
        lower.contains('temporary failure in name resolution') ||
        lower.contains('transportererror') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('socketexception') ||
        lower.contains('failed to connect') ||
        lower.contains('unable to download api page') ||
        lower.contains('incompleteread') ||
        lower.contains('remotedisconnected') ||
        lower.contains('ssl: handshake') ||
        lower.contains('certificate verify failed') ||
        lower.contains('err_empty_response') ||
        lower.contains('errno 7');
  }

  static String cleanErrorMessage(dynamic error) {
    if (error == null) return 'Bilinmeyen bir hata oluştu.';
    String result = error.toString().trim();

    if (result.startsWith('PlatformException(')) {
      final firstComma = result.indexOf(',');
      if (firstComma != -1) {
        final rest = result.substring(firstComma + 1).trim();
        final lastComma = rest.lastIndexOf(',');
        if (lastComma != -1) {
          result = rest.substring(0, lastComma).trim();
        } else {
          result = rest;
        }
      }
    }

    if (isNetworkRelatedError(result)) {
      return 'İnternet / DNS bağlantısı kurulamadı. Ağ bağlantısı bekleniyor.';
    }

    // Çıplak contains('bot') KULLANILMAZ: kelime sınırı olmadığı için "Bottom",
    // "robot", "sabotage" geçen her başlık ve yol bot doğrulaması sanılıyordu.
    // Bu kontrol listenin başında olduğundan alakasız hatanın gerçek nedeni
    // ("video unavailable", depolama hatası) hiç görünmüyor ve kullanıcı boşuna
    // yt-dlp motorunu güncellemeye yönlendiriliyordu.
    if (result.toLowerCase().contains('sign in to confirm') ||
        result.toLowerCase().contains('not a bot') ||
        result.toLowerCase().contains('botguard')) {
      return 'YouTube bot doğrulaması istedi. Ayarlardan yt-dlp motorunu güncelleyin.';
    }

    if (result.toLowerCase().contains('video unavailable') ||
        result.toLowerCase().contains('this video is unavailable')) {
      return 'Video yayından kaldırılmış veya gizli.';
    }
    if (result.toLowerCase().contains('private video')) {
      return 'Bu video gizli olarak ayarlanmış.';
    }

    if (result.toLowerCase().contains('429') ||
        result.toLowerCase().contains('too many requests') ||
        result.toLowerCase().contains('http error 429') ||
        result.toLowerCase().contains('rate limit')) {
      return 'YouTube istek sınırı aşıldı. Uygulama otomatik yeniden deneyecek.';
    }

    if (result.contains('Errno 2') ||
        result.contains('Errno 22') ||
        result.toLowerCase().contains('no such file or directory') ||
        result.toLowerCase().contains('filename too long') ||
        (result.toLowerCase().contains('invalid argument') &&
            (result.toLowerCase().contains('file') ||
             result.toLowerCase().contains('path') ||
             result.toLowerCase().contains('errno')))) {
      final rawHint = result.length > 400 ? result.substring(0, 400) : result;
      return 'Depolama erişim hatası: Klasör bulunamadı veya yazma izni reddedildi. Uygulamayı yeniden başlatarak otomatik düzeltilmesini sağlayın.\nHam hata: $rawHint';
    }

    result = result.replaceAll(RegExp(r'WARNING:\s*Your yt-dlp version is older than \d+ days!.*?(ERROR:|$)', caseSensitive: false), r'$1');
    result = result.replaceAll(RegExp(r'WARNING:\s*.*?deprecationwarning.*?(ERROR:|$)', caseSensitive: false), r'$1');

    if (result.contains('ERROR:')) {
      result = result.substring(result.indexOf('ERROR:'));
    }

    result = result.replaceAll(RegExp(r',\s*null,\s*null\)?$'), '').trim();
    return result.isEmpty ? 'İndirme işlemi sırasında bir hata oluştu.' : result;
  }

  // --- 6. VİDEO VE OYNATMA LİSTESİ EKLEME ---

  Future<String?> addDownload({
    required String url,
    required AppSettings settings,
    int? currentStorageUsedBytes,
  }) async {
    _manager.lastSettings = settings;

    final netCheck = await NetworkManager.instance.checkNetworkPermissionAndStatus(settings);
    if (netCheck['allowed'] != true) {
      return netCheck['reason'] as String? ?? 'Ağ ayarlarınız indirme yapılmasına izin vermiyor.';
    }

    final currentUsed = currentStorageUsedBytes ?? await StorageManager.instance.getUsedStorageBytes();
    final maxBytes = settings.maxStorageLimitGB * 1024 * 1024 * 1024;
    if (currentUsed >= maxBytes) {
      return 'Mevcut indirmeler belirlenen depolama sınırını (${settings.maxStorageLimitGB} GB) aşmış durumda. Lütfen yer açın veya kotayı artırın.';
    }

    final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
    final currentTotalSec = downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
    final maxDurationSec = settings.maxVideoDurationHours * 3600;
    if (isDurationQuotaFull(
      currentTotalSeconds: currentTotalSec,
      maxDurationSeconds: maxDurationSec,
    )) {
      return 'Mevcut indirmeler belirlenen toplam süre kotasını (${settings.maxVideoDurationHours} Saat) doldurmuş durumda. Lütfen video silin veya süreyi artırın.';
    }

    if (!isValidYouTubeUrl(url)) {
      return 'Geçersiz YouTube bağlantısı. Lütfen geçerli bir video veya oynatma listesi URL\'si girin.';
    }

    if (isPlaylistUrl(url)) {
      return 'PLAYLIST_URL';
    } else {
      return await _addSingleVideoDownload(url: url, settings: settings);
    }
  }

  Future<String?> _addSingleVideoDownload({
    required String url,
    required AppSettings settings,
  }) async {
    final videoId = VideoItem.extractVideoId(url);
    
    final isAlreadyInQueue = _manager.tasks.any((t) {
      final tId = VideoItem.extractVideoId(t.url);
      return t.url == url || (videoId != null && tId == videoId);
    });
    if (isAlreadyInQueue) return 'Bu video zaten indirme listesinde mevcut.';

    final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
    final isAlreadyDownloaded = downloadedVideos.any((v) {
      return v.sourceUrl == url || (videoId != null && (v.youtubeId == videoId || v.id == videoId));
    });
    if (isAlreadyDownloaded) return 'Bu video zaten indirilmiş durumda.';

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: taskId,
      url: url,
      title: 'Bilgiler alınıyor...',
      status: DownloadStatus.fetchingMetadata,
    );

    _manager.tasks.insert(0, task);
    _manager.saveTasksToStorage();
    _manager.notifyListeners(); // Will notify UI

    try {
      final metadata = await NativeBridge.instance.fetchMetadata(url);
      final title = metadata['title'] as String? ?? 'Video $taskId';
      final duration = (metadata['duration'] as num?)?.toInt() ?? 0;
      final thumbnail = metadata['thumbnail'] as String?;
      final uploader = metadata['uploader'] as String?;
      final uploadDate = metadata['uploadDate'] as String?;

      final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
      final currentTotalSec = downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = settings.maxVideoDurationHours * 3600;

      if (!fitsInDurationQuota(
        currentTotalSeconds: currentTotalSec,
        videoSeconds: duration,
        maxDurationSeconds: maxDurationSec,
      )) {
        _manager.tasks.removeWhere((t) => t.id == task.id);
        final totalHours = ((currentTotalSec + duration) / 3600).toStringAsFixed(1);
        _manager.saveTasksToStorage();
        _manager.notifyListeners();
        return 'Toplam video süresi ($totalHours sa), belirlenen toplam kotayı (${settings.maxVideoDurationHours} sa) aşacağı için eklenmedi.';
      }

      task.title = title;
      task.durationSeconds = duration;
      task.thumbnail = thumbnail;
      task.uploader = uploader;
      task.uploadDate = uploadDate;
      task.status = DownloadStatus.queued;
      _manager.saveTasksToStorage();
      _manager.notifyListeners();

      if (!_manager.isQueuePaused) {
        await _manager.processNextQueue(settings: settings);
      }
      return null;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = 'Hata: ${cleanErrorMessage(e)}';
      _manager.saveTasksToStorage();
      _manager.notifyListeners();
      return task.errorMessage;
    }
  }

  Future<PlaylistFetchResult> resolvePlaylist({
    required String url,
    required AppSettings settings,
  }) async {
    List<Map<String, dynamic>> rawEntries = [];
    try {
      rawEntries = await NativeBridge.instance.fetchPlaylistEntries(url);
    } catch (e) {
      debugPrint('resolvePlaylist native error: $e');
      throw Exception('Liste çekilemedi: Hata oluştu veya desteklenmeyen format. Detay: $e');
    }

    if (rawEntries.isEmpty) {
      return PlaylistFetchResult(entries: const [], totalCount: 0, sourceUrl: url);
    }

    final ordered = rawEntries;
    final totalCount = ordered.length;
    final limited = totalCount > maxPlaylistEntries ? ordered.sublist(0, maxPlaylistEntries) : ordered;

    final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();

    final entries = <PlaylistEntry>[];
    for (var i = 0; i < limited.length; i++) {
      final entry = _normalizePlaylistEntry(limited[i], i, downloadedVideos);
      if (entry != null) entries.add(entry);
    }

    return PlaylistFetchResult(
      entries: entries,
      totalCount: totalCount,
      sourceUrl: url,
    );
  }

  PlaylistEntry? _normalizePlaylistEntry(Map<String, dynamic> raw, int index, List<VideoItem> downloadedVideos) {
    // Ham URL doğrudan kuyruğa ve oradan yt-dlp argümanına giriyordu. Liste
    // çıktısındaki bozuk bir değer (boş, "null", göreli yol, YouTube olmayan alan
    // adı, çıplak video kimliği) ancak indirme anında hata veriyor; kullanıcı
    // listede neden indirilemeyen bir satır olduğunu göremiyordu. Kaynağında
    // normalize edip doğrula, doğrulanamayanı listeye hiç alma.
    final videoUrl = extractYouTubeUrl((raw['url'] as String? ?? '').trim()) ?? '';
    if (videoUrl.isEmpty) return null;

    var title = (raw['title'] as String? ?? '').trim();
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('[deleted') || lowerTitle.contains('[private') || lowerTitle.contains('[unavailable')) return null;

    final vid = VideoItem.extractVideoId(videoUrl);
    if (title.isEmpty || lowerTitle == 'null' || lowerTitle == 'null null') {
      title = vid != null ? 'Video ($vid)' : 'Video ${index + 1}';
    }

    var thumbnail = (raw['thumbnail'] as String? ?? '').trim();
    if (thumbnail.isEmpty || thumbnail.toLowerCase() == 'null') {
      thumbnail = vid != null ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '';
    }

    var uploader = (raw['uploader'] as String? ?? '').trim();
    if (uploader.toLowerCase() == 'null') uploader = '';

    final inQueue = _manager.tasks.any((t) {
      final tVid = VideoItem.extractVideoId(t.url);
      return t.url == videoUrl || (vid != null && tVid == vid);
    });
    final inLibrary = downloadedVideos.any(
      (v) => v.sourceUrl == videoUrl || (vid != null && v.youtubeId == vid),
    );

    if (inQueue || inLibrary) return null;

    return PlaylistEntry(
      url: videoUrl,
      title: title,
      durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
      thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
      uploader: uploader.isNotEmpty ? uploader : null,
      alreadyPresent: inQueue || inLibrary,
    );
  }

  Future<String?> addSelectedEntries({
    required List<PlaylistEntry> entries,
    required AppSettings settings,
    required String sourcePlaylistUrl,
    int truncatedCount = 0,
    int totalCount = 0,
  }) async {
    if (entries.isEmpty) return 'Seçili video yok.';

    final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
    int runningTotalSec = downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
    final maxDurationSec = settings.maxVideoDurationHours * 3600;

    int addedCount = 0;
    int skippedCount = 0;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final effectiveDuration = effectiveDurationSeconds(entry.durationSeconds);

      if (!fitsInDurationQuota(
        currentTotalSeconds: runningTotalSec,
        videoSeconds: effectiveDuration,
        maxDurationSeconds: maxDurationSec,
      )) {
        skippedCount++;
        continue;
      }

      final vid = VideoItem.extractVideoId(entry.url);
      final isAlreadyInQueue = _manager.tasks.any((t) {
        final tVid = VideoItem.extractVideoId(t.url);
        return t.url == entry.url || (vid != null && tVid == vid);
      });

      if (isAlreadyInQueue) {
        skippedCount++;
        continue;
      }

      runningTotalSec += effectiveDuration;
      _manager.tasks.add(DownloadTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        url: entry.url,
        title: entry.title,
        durationSeconds: entry.durationSeconds,
        thumbnail: entry.thumbnail,
        uploader: entry.uploader,
        uploadDate: entry.uploadDate,
        status: DownloadStatus.queued,
        sourcePlaylistUrl: sourcePlaylistUrl,
      ));
      addedCount++;
    }

    if (addedCount > 0) {
      _manager.saveTasksToStorage();
      _manager.notifyListeners();
      if (!_manager.isQueuePaused) {
        await _manager.processNextQueue(settings: settings);
      }
    }

    if (addedCount == 0 && skippedCount > 0) {
      return 'Kütüphane süre sınırına ulaşıldı (${settings.maxVideoDurationHours} saat). Seçilen videolar eklenemedi.';
    }
    if (skippedCount > 0) {
      return 'Kütüphane süre sınırı nedeniyle ${entries.length} videodan sadece $addedCount tanesi eklendi ($skippedCount atlandı).';
    }
    return null;
  }

  Future<PlaylistSyncResult> syncSavedPlaylists({
    required AppSettings settings,
    required LibraryProvider libraryProvider,
  }) async {
    if (_isSyncingPlaylists) return const PlaylistSyncResult(success: false, message: 'Senkronizasyon zaten devam ediyor');
    if (settings.savedPlaylists.isEmpty) return const PlaylistSyncResult(success: false, message: 'Kayitli oynatma listesi bulunamadi');

    _isSyncingPlaylists = true;
    _safeNotify();

    int trashedCount = 0;
    int queueDeletedCount = 0;
    int addedCount = 0;
    bool anyPlaylistSucceeded = false;
    int attemptedPlaylistCount = 0;
    // Çekilemeyen listeler sessizce yutulamaz: kullanıcı hangi listenin
    // eşitlenemediğini bilmezse, eksik kalan videoların YouTube'dan mı silindiğini
    // yoksa ağın mı koptuğunu ayırt edemez.
    int failedPlaylistCount = 0;

    try {
      final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
      final currentQueueTasks = List<DownloadTask>.from(_manager.tasks);
      final Set<String> allOnlineVideoIds = {};
      final Set<String> allOnlineUrls = {};
      final List<Map<String, dynamic>> orderedNewEntries = [];
      // Silme kararı liste BAZINDA verilir: yalnız burada biriken listelerin
      // çevrimiçi içeriği gerçekten bilinir (bkz. shouldRemoveFromSync).
      final Set<String> successfulPlaylists = {};

      for (final playlistUrl in settings.savedPlaylists) {
        if (playlistUrl.trim().isEmpty) continue;
        attemptedPlaylistCount++;
        try {
          final pid = Uri.tryParse(playlistUrl)?.queryParameters['list'];
          Map<String, DateTime>? apiDates;
          if (pid != null) {
            apiDates = await YoutubeApiService().fetchPlaylistVideos(pid);
          }

          final entries = await NativeBridge.instance.fetchPlaylistEntries(playlistUrl);
          if (entries.isNotEmpty) {
            anyPlaylistSucceeded = true;
            successfulPlaylists.add(playlistUrl);
          }
          for (final entry in entries) {
            final u = (entry['url'] as String? ?? '').trim();
            final vid = VideoItem.extractVideoId(u) ?? (entry['id'] as String? ?? '').trim();
            if (vid.isNotEmpty) allOnlineVideoIds.add(vid);
            if (u.isNotEmpty) allOnlineUrls.add(u);

            final t = (entry['title'] as String? ?? '').trim();
            if (t.toLowerCase().contains('[deleted') || t.toLowerCase().contains('[private') || t.toLowerCase().contains('[unavailable')) continue;

            final isAlreadyDownloaded = downloadedVideos.any((v) => (v.youtubeId != null && v.youtubeId == vid) || (v.sourceUrl != null && v.sourceUrl == u));
            final isAlreadyInQueue = currentQueueTasks.any((t) => (VideoItem.extractVideoId(t.url) != null && VideoItem.extractVideoId(t.url) == vid) || t.url == u);
            final isAlreadyInBatch = orderedNewEntries.any((e) {
              final eUrl = (e['url'] as String? ?? '').trim();
              final eVid = VideoItem.extractVideoId(eUrl) ?? (e['id'] as String? ?? '').trim();
              return (vid.isNotEmpty && eVid == vid) || (u.isNotEmpty && eUrl == u);
            });

            if (!isAlreadyDownloaded && !isAlreadyInQueue && !isAlreadyInBatch) {
              final newEntry = {...entry, '_sourcePlaylistUrl': playlistUrl};
              if (apiDates != null && vid.isNotEmpty && apiDates.containsKey(vid)) {
                newEntry['uploadDate'] = apiDates[vid]!.toIso8601String();
              }
              orderedNewEntries.add(newEntry);
            }
          }
        } catch (e) {
          failedPlaylistCount++;
          debugPrint('syncSavedPlaylists: liste çekilemedi ($playlistUrl): $e');
        }
      }

      for (final video in downloadedVideos) {
        if (video.playlistUrl == null || video.playlistUrl!.isEmpty) continue;
        if (!settings.savedPlaylists.contains(video.playlistUrl)) continue;
        final vid = video.youtubeId;
        final stillInPlaylist = (vid != null && allOnlineVideoIds.contains(vid)) || allOnlineUrls.contains(video.sourceUrl);
        if (shouldRemoveFromSync(
          sourcePlaylistUrl: video.playlistUrl,
          successfulPlaylists: successfulPlaylists,
          stillOnline: stillInPlaylist,
        )) {
          final moved = await StorageManager.instance.moveToTrash(video);
          if (moved) trashedCount++;
        }
      }
      if (trashedCount > 0) _manager.onLibraryNeedsRefresh?.call();

      for (final t in List.of(_manager.tasks)) {
        if (t.sourcePlaylistUrl == null || !settings.savedPlaylists.contains(t.sourcePlaylistUrl)) continue;
        if (t.status != DownloadStatus.queued && t.status != DownloadStatus.paused) continue;
        final tVid = VideoItem.extractVideoId(t.url);
        final stillOnline = (tVid != null && allOnlineVideoIds.contains(tVid)) || allOnlineUrls.contains(t.url);
        if (shouldRemoveFromSync(
          sourcePlaylistUrl: t.sourcePlaylistUrl,
          successfulPlaylists: successfulPlaylists,
          stillOnline: stillOnline,
        )) {
          _manager.tasks.remove(t);
          queueDeletedCount++;
        }
      }

      // Metadata Fallback for missing uploadDate
      for (var i = 0; i < orderedNewEntries.length; i++) {
         final d = orderedNewEntries[i]['uploadDate']?.toString() ?? '';
         if (d.isEmpty) {
             final u = (orderedNewEntries[i]['url'] as String? ?? '').trim();
             if (u.isNotEmpty) {
                 try {
                     final meta = await NativeBridge.instance.fetchMetadata(u);
                     orderedNewEntries[i]['uploadDate'] = meta['uploadDate'];
                 } catch(_) {}
             }
         }
      }

      orderedNewEntries.sort((a, b) {
          final da = (a['uploadDate']?.toString() ?? '').replaceAll('-', '');
          final db = (b['uploadDate']?.toString() ?? '').replaceAll('-', '');
          if (da.isNotEmpty && db.isNotEmpty) return db.compareTo(da);
          return 0;
      });

      final maxDurationSec = settings.maxVideoDurationHours * 3600;
      final refreshedDownloads = await StorageManager.instance.scanDownloadedVideos();
      int runningTotalSec = refreshedDownloads.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));

      final syncEpochMs = DateTime.now().millisecondsSinceEpoch;
      var syncTaskIndex = 0;
      for (final entry in orderedNewEntries) {
        final videoUrl = (entry['url'] as String? ?? '').trim();
        var title = (entry['title'] as String? ?? '').trim();
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        var thumbnail = (entry['thumbnail'] as String? ?? '').trim();
        var uploader = (entry['uploader'] as String? ?? '').trim();

        if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') continue;
        // Süresi bilinmeyen girdi kotadan MUAF DEĞİLDİR. `--flat-playlist` çoğu
        // girdide süre döndürmediğinden ham süreyi kullanmak kotayı tamamen
        // etkisiz kılıyordu: 10 saatlik sınır konmuş olsa bile eşitleme yüzlerce
        // videoyu "toplam 0 saniye" sayıp kuyruğa döküyordu. Toplu ekleme
        // (addSelectedEntries) ile aynı kural uygulanır.
        final effectiveDuration = effectiveDurationSeconds(duration);
        if (!fitsInDurationQuota(
          currentTotalSeconds: runningTotalSec,
          videoSeconds: effectiveDuration,
          maxDurationSeconds: maxDurationSec,
        )) {
          continue;
        }

        if (title.isEmpty || title.toLowerCase() == 'null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          title = vid != null ? 'Video ($vid)' : 'YouTube Videosu';
        }

        final vid = VideoItem.extractVideoId(videoUrl);
        final isAlreadyInQueueFinal = _manager.tasks.any((t) {
          final tVid = VideoItem.extractVideoId(t.url);
          return t.url == videoUrl || (vid != null && tVid == vid);
        });
        if (isAlreadyInQueueFinal) continue;

        runningTotalSec += effectiveDuration;
        final taskIndex = syncTaskIndex++;
        final taskId = buildSyncTaskId(syncEpochMs, taskIndex);
        final entrySourcePlaylist = (entry['_sourcePlaylistUrl'] as String? ?? '').trim();
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
          thumbnail: thumbnail.isNotEmpty && thumbnail.toLowerCase() != 'null' ? thumbnail : null,
          durationSeconds: duration,
          uploader: uploader.isNotEmpty && uploader.toLowerCase() != 'null' ? uploader : null,
          uploadDate: entry['uploadDate']?.toString(),
          status: DownloadStatus.queued,
          sourcePlaylistUrl: entrySourcePlaylist.isNotEmpty ? entrySourcePlaylist : null,
        );

        // insert(0) DEĞİL: her görevi 0. indekse koymak, yukarıda yeniden eskiye
        // sıralanan listeyi tam tersine çeviriyordu; en eski video kuyruğun başına
        // geçiyor ve sıralamanın amacı sessizce iptal oluyordu. Artan indekse
        // eklemek hem sıralamayı korur hem de eşitleme partisini blok hâlinde tutar.
        _manager.tasks.insert(taskIndex, newTask);
        addedCount++;
      }

      await _manager.saveTasksToStorage();
      _manager.notifyListeners();
      if (!_manager.isQueuePaused && addedCount > 0) {
        await _manager.processNextQueue(settings: settings);
      }

      return PlaylistSyncResult(
        success: anyPlaylistSucceeded,
        newVideosAdded: addedCount,
        deletedVideosRemoved: trashedCount + queueDeletedCount,
        message: buildSyncFailureNotice(
          attemptedCount: attemptedPlaylistCount,
          failedCount: failedPlaylistCount,
        ),
      );
    } catch (e) {
      return PlaylistSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncingPlaylists = false;
      _safeNotify();
    }
  }
}
