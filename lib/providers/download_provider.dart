import 'dart:async';
import 'package:flutter/widgets.dart';
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

  final DownloadQueueManager _manager = DownloadQueueManager.instance;
  StreamSubscription? _updateSub;
  bool _disposed = false;
  bool _isSyncingPlaylists = false;

  List<DownloadTask> get tasks => _manager.tasks;
  bool get isProcessingQueue => _manager.isProcessingQueue;
  String? get activeTaskId => _manager.activeTaskId;
  bool get isQueuePaused => _manager.isQueuePaused;
  bool get isWifiWaiting => _manager.isWifiWaiting;
  bool get isLoaded => _manager.isLoaded;
  bool get isSyncingPlaylists => _isSyncingPlaylists;

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

    if (result.toLowerCase().contains('sign in to confirm') ||
        result.toLowerCase().contains('confirms you\'re not a bot') ||
        result.toLowerCase().contains('botguard') ||
        result.toLowerCase().contains('bot')) {
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
    if (currentTotalSec >= maxDurationSec) {
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

      final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
      final currentTotalSec = downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = settings.maxVideoDurationHours * 3600;

      if (duration > 0 && (currentTotalSec + duration) > maxDurationSec) {
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
      print('resolvePlaylist native error: $e');
      throw Exception('Liste çekilemedi: Hata oluştu veya desteklenmeyen format. Detay: $e');
    }

    if (rawEntries.isEmpty) {
      return PlaylistFetchResult(entries: const [], totalCount: 0, sourceUrl: url);
    }

    // Kullanıcı eğer "En yeni videoları önce indir" ayarını açtıysa tersine çeviriyoruz.
    // Ancak kullanıcı YouTube üzerinden listeyi zaten "En yeni" olarak sıraladıysa, 
    // bu ayarı kapatması gerekir. Aksi takdirde en yeniler en sona gider.
    bool shouldReverse = settings.playlistReverseOrder;
    
    final ordered = shouldReverse ? rawEntries.reversed.toList() : rawEntries;
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
    final videoUrl = (raw['url'] as String? ?? '').trim();
    if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') return null;

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
      final effectiveDuration = entry.hasDuration ? entry.durationSeconds : defaultVideoDurationSeconds;

      if ((runningTotalSec + effectiveDuration) > maxDurationSec) {
        skippedCount++;
        continue;
      }

      runningTotalSec += effectiveDuration;
      _manager.tasks.add(DownloadTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        url: entry.url,
        title: 'Bilgiler alınıyor...',
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
    if (settings.savedPlaylists.isEmpty) return const PlaylistSyncResult(success: false, message: 'Kayıtlı oynatma listesi bulunamadı');

    _isSyncingPlaylists = true;
    notifyListeners();

    int trashedCount = 0;
    int queueDeletedCount = 0;
    int addedCount = 0;
    bool anyPlaylistSucceeded = false;

    try {
      final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
      final currentQueueTasks = List<DownloadTask>.from(_manager.tasks);
      final Set<String> allOnlineVideoIds = {};
      final Set<String> allOnlineUrls = {};
      final List<Map<String, dynamic>> orderedNewEntries = [];

      for (final playlistUrl in settings.savedPlaylists) {
        if (playlistUrl.trim().isEmpty) continue;
        try {
          final entries = await NativeBridge.instance.fetchPlaylistEntries(playlistUrl);
          if (entries.isNotEmpty) anyPlaylistSucceeded = true;
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
              orderedNewEntries.add({...entry, '_sourcePlaylistUrl': playlistUrl});
            }
          }
        } catch (_) {}
      }

      if (anyPlaylistSucceeded) {
        for (final video in downloadedVideos) {
          if (video.playlistUrl == null || video.playlistUrl!.isEmpty || !settings.savedPlaylists.contains(video.playlistUrl)) continue;
          final vid = video.youtubeId;
          final stillInPlaylist = (vid != null && allOnlineVideoIds.contains(vid)) || allOnlineUrls.contains(video.sourceUrl);
          if (!stillInPlaylist) {
            final moved = await StorageManager.instance.moveToTrash(video);
            if (moved) trashedCount++;
          }
        }
        if (trashedCount > 0) _manager.onLibraryNeedsRefresh?.call();
      }

      for (final t in List.of(_manager.tasks)) {
        final belongsToSavedPlaylist = t.sourcePlaylistUrl != null && settings.savedPlaylists.contains(t.sourcePlaylistUrl);
        if (!belongsToSavedPlaylist) continue;
        if (t.status == DownloadStatus.queued || t.status == DownloadStatus.paused) {
          final tVid = VideoItem.extractVideoId(t.url);
          final stillOnline = (tVid != null && allOnlineVideoIds.contains(tVid)) || allOnlineUrls.contains(t.url);
          if (!stillOnline) {
            _manager.tasks.remove(t);
            queueDeletedCount++;
          }
        }
      }

      final maxDurationSec = settings.maxVideoDurationHours * 3600;
      final refreshedDownloads = await StorageManager.instance.scanDownloadedVideos();
      int runningTotalSec = refreshedDownloads.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final effectiveNewEntries = settings.playlistReverseOrder ? orderedNewEntries.reversed.toList() : orderedNewEntries;

      for (final entry in effectiveNewEntries) {
        final videoUrl = (entry['url'] as String? ?? '').trim();
        var title = (entry['title'] as String? ?? '').trim();
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        var thumbnail = (entry['thumbnail'] as String? ?? '').trim();
        var uploader = (entry['uploader'] as String? ?? '').trim();

        if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') continue;
        final lowerTitle = title.toLowerCase();
        if (lowerTitle.contains('[deleted') || lowerTitle.contains('[private') || lowerTitle.contains('[unavailable')) continue;

        if (title.isEmpty || lowerTitle == 'null' || lowerTitle == 'null null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          title = vid != null ? 'Video ($vid)' : 'YouTube Videosu';
        }
        if (thumbnail.isEmpty || thumbnail.toLowerCase() == 'null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          thumbnail = vid != null ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '';
        }
        if (uploader.toLowerCase() == 'null') uploader = '';
        if (duration > 0 && (runningTotalSec + duration) > maxDurationSec) continue;

        runningTotalSec += duration;
        final taskId = '${DateTime.now().millisecondsSinceEpoch}_jit_0';
        final entrySourcePlaylist = (entry['_sourcePlaylistUrl'] as String? ?? '').trim();
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
          thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
          durationSeconds: duration,
          uploader: uploader.isNotEmpty ? uploader : null,
          status: DownloadStatus.queued,
          sourcePlaylistUrl: entrySourcePlaylist.isNotEmpty ? entrySourcePlaylist : null,
        );

        _manager.tasks.insert(0, newTask);
        addedCount++;
        break;
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
      );
    } catch (e) {
      return PlaylistSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncingPlaylists = false;
      notifyListeners();
    }
  }
}
