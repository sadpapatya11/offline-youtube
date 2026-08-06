import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';

class DownloadProvider extends ChangeNotifier {
  static const String _tasksPrefKey = 'offline_youtube_persisted_tasks_v3';
  static const String _queuePausedPrefKey = 'offline_youtube_queue_paused_v3';

  final List<DownloadTask> _tasks = [];
  bool _isProcessingQueue = false;
  String? _activeTaskId;
  bool _isQueuePaused = false;
  bool _isWifiWaiting = false;
  bool _isLoaded = false;
  AppSettings? _lastSettings;
  VoidCallback? onLibraryNeedsRefresh;

  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectivitySubscription;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get isProcessingQueue => _isProcessingQueue;
  String? get activeTaskId => _activeTaskId;
  bool get isQueuePaused => _isQueuePaused;
  bool get isWifiWaiting => _isWifiWaiting;
  bool get isLoaded => _isLoaded;

  int get queuedCount =>
      _tasks.where((t) => t.status == DownloadStatus.queued).length;

  int get downloadingCount =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  int get completedCount =>
      _tasks.where((t) => t.status == DownloadStatus.completed).length;

  int get activeDownloadCount => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued)
      .length;

  bool get isDownloadingActive =>
      _tasks.any((t) => t.status == DownloadStatus.downloading);

  DownloadTask? get activeTask {
    if (_activeTaskId == null) return null;
    return _tasks.firstWhere(
      (t) => t.id == _activeTaskId,
      orElse: () => _tasks.firstWhere(
        (t) => t.status == DownloadStatus.downloading,
        orElse: () => _tasks.isNotEmpty ? _tasks.first : DownloadTask(
          id: '',
          url: '',
          title: '',
          status: DownloadStatus.queued,
        ),
      ),
    );
  }

  DownloadProvider() {
    _loadPersistedState();
    _listenToNativeEvents();
    _listenToConnectivity();
  }

  // --- 1. PERSISTENCE (KALICI HAFIZA) & AÇILIŞTA OTOMATİK BAŞLATMA ---

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isQueuePaused = prefs.getBool(_queuePausedPrefKey) ?? false;

      // Hem v3 hem de önceki v2 anahtarını kontrol ederek geriye dönük veri kaybını önle
      List<String>? rawList = prefs.getStringList(_tasksPrefKey);
      rawList ??= prefs.getStringList('offline_youtube_persisted_tasks_v2');

      if (rawList != null && rawList.isNotEmpty) {
        _tasks.clear();
        for (final itemStr in rawList) {
          try {
            final Map<String, dynamic> jsonMap = jsonDecode(itemStr);
            final task = DownloadTask.fromJson(jsonMap);

            // Uygulama kapatılıp açıldığında bitmemiş olan tüm görevleri (downloading, paused, fetching)
            // 'queued' durumuna alarak kuyruğun otomatik devam etmesini sağla
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.fetchingMetadata ||
                task.status == DownloadStatus.paused) {
              task.status = DownloadStatus.queued;
              task.speed = '';
              task.errorMessage = null;
            }
            _tasks.add(task);
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      _isLoaded = true;
      notifyListeners();

      // Hafızayı hemen güncel normalize edilmiş durumla kaydet
      await _saveTasksToStorage();

      // Açılışta bekleyen görevler varsa ve master pause yoksa hemen kuyruğu başlat
      if (!_isQueuePaused &&
          _tasks.any((t) => t.status == DownloadStatus.queued)) {
        if (_lastSettings != null) {
          await _evaluateConditionsAndAutoResume();
        } else {
          _triggerNextQueue();
        }
      }
    }
  }

  Future<void> _saveTasksToStorage() async {
    // KRİTİK: Hafıza diskten henüz okunmadıysa asla boş listeyle diski ezme!
    if (!_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_queuePausedPrefKey, _isQueuePaused);

      final strList = _tasks.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_tasksPrefKey, strList);
    } catch (_) {}
  }

  // --- 2. GERÇEK ZAMANLI AĞ VE WI-FI DİNLEME (AUTO-RESUME) ---

  void _listenToConnectivity() {
    _connectivitySubscription =
        NetworkManager.instance.onConnectivityChanged.listen((results) async {
      await _evaluateConditionsAndAutoResume();
    });
  }

  Future<void> onSettingsChanged(AppSettings settings) async {
    _lastSettings = settings;
    if (!_isLoaded) return;
    await _evaluateConditionsAndAutoResume();
  }

  Future<void> _evaluateConditionsAndAutoResume() async {
    if (_lastSettings == null || !_isLoaded) return;

    // 1. Depolama kotası kontrolü
    final maxBytes = _lastSettings!.maxStorageLimitGB * 1024 * 1024 * 1024;
    final usedBytes = await StorageManager.instance.getUsedStorageBytes();
    if (usedBytes >= maxBytes) {
      if (_activeTaskId != null || isDownloadingActive) {
        await _pauseForMobileDataGuard(
          '⚠️ Belirlenen depolama kotası (${_lastSettings!.maxStorageLimitGB} GB) doldu. İndirme duraklatıldı.',
        );
      }
      notifyListeners();
      return;
    }

    // 2. Toplam video süresi kotası kontrolü
    final downloadedVideos =
        await StorageManager.instance.scanDownloadedVideos();
    final totalDurationSec = downloadedVideos.fold<int>(
        0, (sum, v) => sum + (v.durationSeconds ?? 0));
    final maxDurationSec = _lastSettings!.maxVideoDurationHours * 3600;
    if (totalDurationSec >= maxDurationSec) {
      if (_activeTaskId != null || isDownloadingActive) {
        await _pauseForMobileDataGuard(
          '⚠️ Belirlenen toplam video süresi kotası (${_lastSettings!.maxVideoDurationHours} Saat) doldu. İndirme duraklatıldı.',
        );
      }
      notifyListeners();
      return;
    }

    // 3. Ağ kontrolü
    if (_lastSettings!.networkMode == NetworkRestrictionMode.anyWifi) {
      final isWifi = await NetworkManager.instance.isWifiConnected();
      _isWifiWaiting = !isWifi;

      if (!isWifi) {
        // Wi-Fi bağlı değil ve Sadece Wi-Fi kuralı aktif -> Varsa aktif indirmeyi HEMEN duraklat!
        if (_activeTaskId != null || isDownloadingActive) {
          await _pauseForMobileDataGuard(
            '⚠️ Wi-Fi bağlantısı kesildi. Mobil veri koruması nedeniyle indirme anında duraklatıldı.',
          );
        }
      } else {
        // Wi-Fi bağlandı -> Koşullar sağlandı, bekleyen görevleri otomatik başlat!
        if (!_isQueuePaused) {
          for (final t in _tasks) {
            if (t.status == DownloadStatus.paused &&
                (t.errorMessage?.contains('Mobil veri') == true ||
                    t.errorMessage?.contains('Wi-Fi') == true ||
                    t.errorMessage?.contains('Ağ bağlantısı') == true ||
                    t.errorMessage?.contains('İnternet') == true)) {
              t.status = DownloadStatus.queued;
              t.errorMessage = null;
            }
          }
          await _saveTasksToStorage();
          if (_tasks.any((t) => t.status == DownloadStatus.queued)) {
            _triggerNextQueue();
          }
        }
      }
    } else {
      // Tüm Ağlar izinli (Wi-Fi veya Mobil Veri farketmeksizin)
      _isWifiWaiting = false;
      if (!_isQueuePaused) {
        for (final t in _tasks) {
          if (t.status == DownloadStatus.paused &&
              (t.errorMessage?.contains('Mobil veri') == true ||
                  t.errorMessage?.contains('Wi-Fi') == true ||
                  t.errorMessage?.contains('Ağ bağlantısı') == true ||
                  t.errorMessage?.contains('İnternet') == true)) {
            t.status = DownloadStatus.queued;
            t.errorMessage = null;
          }
        }
        await _saveTasksToStorage();
        if (_tasks.any((t) => t.status == DownloadStatus.queued)) {
          _triggerNextQueue();
        }
      }
    }
    notifyListeners();
  }

  Future<void> _pauseForMobileDataGuard(String reason) async {
    if (_activeTaskId != null) {
      final taskId = _activeTaskId!;
      _activeTaskId = null;
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx].status = DownloadStatus.paused;
        _tasks[idx].speed = '';
        _tasks[idx].errorMessage = reason;
      }
      await NativeBridge.instance.pauseDownload(taskId);
    }

    for (final task in _tasks) {
      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.paused;
        task.speed = '';
      }
    }

    _saveTasksToStorage();
    notifyListeners();
  }

  // --- 3. NATIVE OLAY DİNLEYİCİSİ ---

  void _listenToNativeEvents() {
    _eventSubscription = NativeBridge.instance.downloadEvents.listen(
      (data) {
        final taskId = data['taskId']?.toString();
        if (taskId == null) return;

        final index = _tasks.indexWhere((t) => t.id == taskId);
        if (index == -1) return;

        final task = _tasks[index];
        final type = data['type']?.toString();

        switch (type) {
          case 'progress':
            final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
            final eta = (data['eta'] as num?)?.toInt() ?? 0;
            final speed = data['speed']?.toString() ?? '';

            if (task.status == DownloadStatus.downloading) {
              task.progress = progress;
              task.etaSeconds = eta;
              task.speed = speed;
              notifyListeners();
            }
            break;

          case 'completed':
            task.status = DownloadStatus.completed;
            task.progress = 100.0;
            task.speed = '';
            task.etaSeconds = 0;
            task.errorMessage = null;

            // Video metadata kaydet (süreyi disk taramasında hatırlamak için)
            try {
              final dir = Directory(StorageManager.instance.currentDownloadPath);
              if (dir.existsSync()) {
                final files = dir.listSync();
                for (final f in files) {
                  if (f is File) {
                    final name = f.path.split(Platform.pathSeparator).last;
                    if (name.contains(task.title) ||
                        (task.id.isNotEmpty && name.contains(task.id))) {
                      StorageManager.instance.saveVideoMetadata(
                        f.path,
                        durationSeconds: task.durationSeconds,
                        uploader: task.uploader,
                        title: task.title,
                        url: task.url,
                      );
                    }
                  }
                }
              }
            } catch (_) {}

            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _saveTasksToStorage();
            notifyListeners();
            onLibraryNeedsRefresh?.call();
            _triggerNextQueue();
            break;

          case 'error':
            if (task.status != DownloadStatus.paused &&
                task.status != DownloadStatus.cancelled) {
              final rawError = data['error']?.toString() ??
                  data['message']?.toString() ??
                  '';
              final isNetError = isNetworkRelatedError(rawError);

              if (isNetError) {
                // Ağ / DNS hatası: Görevi kırmızı kalıcı hataya atmak yerine duraklat ve bekle
                task.status = DownloadStatus.paused;
                task.speed = '';
                task.errorMessage =
                    '⚠️ Ağ bağlantısı kesildi. İnternet/Wi-Fi sağlandığında indirme otomatik devam edecek.';
                if (_activeTaskId == taskId) {
                  _activeTaskId = null;
                }
                if (_lastSettings?.networkMode == NetworkRestrictionMode.anyWifi) {
                  _isWifiWaiting = true;
                }
                _saveTasksToStorage();
                notifyListeners();
                // Ağ yokken diğer görevleri peş peşe patlatmamak için beklet
                return;
              }

              task.status = DownloadStatus.error;
              task.speed = '';
              task.errorMessage = cleanErrorMessage(rawError);
              if (_activeTaskId == taskId) {
                _activeTaskId = null;
              }
              _saveTasksToStorage();
              notifyListeners();
              _triggerNextQueue();
            }
            break;

          case 'cancelled':
            task.status = DownloadStatus.cancelled;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _saveTasksToStorage();
            notifyListeners();
            _triggerNextQueue();
            break;
        }
      },
      onError: (e) {
        // Event channel hatası
      },
    );
  }

  void _triggerNextQueue() {
    if (_isQueuePaused) return;

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!_isQueuePaused) {
        processNextQueue();
      }
    });
  }

  // --- 4. MASTER VE SIRALI KUYRUK MOTORU ---

  Future<void> pauseQueue() async {
    _isQueuePaused = true;
    if (_activeTaskId != null) {
      final currentId = _activeTaskId!;
      _activeTaskId = null;
      final idx = _tasks.indexWhere((t) => t.id == currentId);
      if (idx != -1) {
        _tasks[idx].status = DownloadStatus.paused;
        _tasks[idx].speed = '';
      }
      await NativeBridge.instance.pauseDownload(currentId);
    }

    for (final t in _tasks) {
      if (t.status == DownloadStatus.downloading) {
        t.status = DownloadStatus.paused;
        t.speed = '';
      }
    }

    await _saveTasksToStorage();
    notifyListeners();
  }

  Future<void> resumeQueue({AppSettings? settings}) async {
    _isQueuePaused = false;

    for (final t in _tasks) {
      if (t.status == DownloadStatus.paused) {
        t.status = DownloadStatus.queued;
        t.errorMessage = null;
      }
    }

    await _saveTasksToStorage();
    notifyListeners();

    await processNextQueue(settings: settings ?? _lastSettings);
  }

  Future<void> processNextQueue({AppSettings? settings}) async {
    if (_isQueuePaused) return;
    if (_isProcessingQueue) return;

    final currentSettings = settings ?? _lastSettings;
    if (currentSettings != null) {
      _lastSettings = currentSettings;

      // 1. Ağ kontrolü
      final netCheck = await NetworkManager.instance
          .checkNetworkPermissionAndStatus(currentSettings);
      if (netCheck['allowed'] != true) {
        _isWifiWaiting =
            currentSettings.networkMode == NetworkRestrictionMode.anyWifi;
        notifyListeners();
        return;
      }

      // 2. Depolama kotası kontrolü
      final maxBytes = currentSettings.maxStorageLimitGB * 1024 * 1024 * 1024;
      final usedBytes = await StorageManager.instance.getUsedStorageBytes();
      if (usedBytes >= maxBytes) {
        notifyListeners();
        return;
      }

      // 3. Toplam video süresi kotası kontrolü
      final downloadedVideos =
          await StorageManager.instance.scanDownloadedVideos();
      final totalDurationSec = downloadedVideos.fold<int>(
          0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = currentSettings.maxVideoDurationHours * 3600;
      if (totalDurationSec >= maxDurationSec) {
        notifyListeners();
        return;
      }
    }

    if (_activeTaskId != null) {
      final activeIndex = _tasks.indexWhere((t) => t.id == _activeTaskId);
      if (activeIndex != -1 &&
          _tasks[activeIndex].status == DownloadStatus.downloading) {
        return;
      }
    }

    _isProcessingQueue = true;
    try {
      final nextTaskIndex =
          _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
      if (nextTaskIndex == -1) {
        _isProcessingQueue = false;
        return;
      }

      final nextTask = _tasks[nextTaskIndex];
      _activeTaskId = nextTask.id;
      nextTask.status = DownloadStatus.downloading;
      nextTask.errorMessage = null;
      notifyListeners();
      _saveTasksToStorage();

      final started = await NativeBridge.instance.startDownload(
        taskId: nextTask.id,
        url: nextTask.url,
        title: nextTask.title,
        outputPath: StorageManager.instance.currentDownloadPath,
      );

      if (!started) {
        nextTask.status = DownloadStatus.error;
        nextTask.errorMessage = 'İndirme başlatılamadı.';
        _activeTaskId = null;
        _saveTasksToStorage();
        notifyListeners();
        _triggerNextQueue();
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // --- 5. URL DOĞRULAMA VE HATA TEMİZLEME ---

  static bool isValidYouTubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;

    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final validHosts = [
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtu.be',
    ];

    if (!validHosts.contains(host) && !host.endsWith('.youtube.com')) {
      return false;
    }

    return uri.path.isNotEmpty;
  }

  static bool isPlaylistUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('list=') || lower.contains('/playlist');
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
        lower.contains('errno 7');
  }

  static String cleanErrorMessage(dynamic error) {
    if (error == null) return 'Bilinmeyen bir hata oluştu.';
    String result = error.toString().trim();

    // Strip PlatformException wrapper if present
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

    // Ağ ve Bağlantı Hataları
    if (isNetworkRelatedError(result)) {
      return 'İnternet / DNS bağlantısı kurulamadı. Ağ bağlantısı bekleniyor.';
    }

    // Bot / Doğrulama
    if (result.toLowerCase().contains('sign in to confirm') ||
        result.toLowerCase().contains('bot')) {
      return 'YouTube bot doğrulaması istedi. Ayarlardan yt-dlp motorunu güncelleyin.';
    }

    // Yayından kaldırılmış / Gizli
    if (result.toLowerCase().contains('video unavailable') ||
        result.toLowerCase().contains('this video is unavailable')) {
      return 'Video yayından kaldırılmış veya gizli.';
    }
    if (result.toLowerCase().contains('private video')) {
      return 'Bu video gizli olarak ayarlanmış.';
    }

    // İstek Limiti
    if (result.toLowerCase().contains('429') ||
        result.toLowerCase().contains('too many requests')) {
      return 'YouTube istek sınırı aşıldı. Lütfen biraz bekleyin.';
    }

    // Remove yt-dlp update warnings
    result = result.replaceAll(
        RegExp(r'WARNING:\s*Your yt-dlp version is older than \d+ days!.*?(ERROR:|$)',
            caseSensitive: false),
        r'$1');
    result = result.replaceAll(
        RegExp(r'WARNING:\s*.*?deprecationwarning.*?(ERROR:|$)',
            caseSensitive: false),
        r'$1');

    if (result.contains('ERROR:')) {
      result = result.substring(result.indexOf('ERROR:'));
    }

    result = result.replaceAll(RegExp(r',\s*null,\s*null\)?$'), '').trim();

    return result.isEmpty ? 'İndirme işlemi sırasında bir hata oluştu.' : result;
  }

  /// Hatalı görevleri tekrar kuyruğa alıp indirmeyi başlatır
  Future<void> retryAllErrors({AppSettings? settings}) async {
    for (final task in _tasks) {
      if (task.status == DownloadStatus.error) {
        task.status = DownloadStatus.queued;
        task.errorMessage = null;
      }
    }
    await _saveTasksToStorage();
    notifyListeners();
    await processNextQueue(settings: settings ?? _lastSettings);
  }

  // --- 6. VİDEO VE OYNATMA LİSTESİ EKLEME ---

  Future<String?> addDownload({
    required String url,
    required AppSettings settings,
    int? currentStorageUsedBytes,
  }) async {
    _lastSettings = settings;

    // 1. Ağ Kısıtlama Kontrolü
    final netCheck = await NetworkManager.instance
        .checkNetworkPermissionAndStatus(settings);
    if (netCheck['allowed'] != true) {
      return netCheck['reason'] as String? ??
          'Ağ ayarlarınız indirme yapılmasına izin vermiyor.';
    }

    // 2. Depolama Kotası Kontrolü
    final currentUsed = currentStorageUsedBytes ??
        await StorageManager.instance.getUsedStorageBytes();
    final maxBytes = settings.maxStorageLimitGB * 1024 * 1024 * 1024;
    if (currentUsed >= maxBytes) {
      return 'Mevcut indirmeler belirlenen depolama sınırını (${settings.maxStorageLimitGB} GB) aşmış durumda. Lütfen yer açın veya kotayı artırın.';
    }

    // 3. Toplam Süre Kotası Kontrolü
    final downloadedVideos =
        await StorageManager.instance.scanDownloadedVideos();
    final currentTotalSec = downloadedVideos.fold<int>(
        0, (sum, v) => sum + (v.durationSeconds ?? 0));
    final maxDurationSec = settings.maxVideoDurationHours * 3600;
    if (currentTotalSec >= maxDurationSec) {
      return 'Mevcut indirmeler belirlenen toplam süre kotasını (${settings.maxVideoDurationHours} Saat) doldurmuş durumda. Lütfen video silin veya süreyi artırın.';
    }

    // 4. YouTube URL Doğrulama
    if (!isValidYouTubeUrl(url)) {
      return 'Geçersiz YouTube bağlantısı. Lütfen geçerli bir video veya oynatma listesi URL\'si girin.';
    }

    final isPlaylist = isPlaylistUrl(url);
    if (isPlaylist) {
      return await _addPlaylistDownload(url: url, settings: settings);
    } else {
      return await _addSingleVideoDownload(url: url, settings: settings);
    }
  }

  Future<String?> _addSingleVideoDownload({
    required String url,
    required AppSettings settings,
  }) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: taskId,
      url: url,
      title: 'Bilgiler alınıyor...',
      status: DownloadStatus.fetchingMetadata,
    );

    _tasks.insert(0, task);
    _saveTasksToStorage();
    notifyListeners();

    try {
      final metadata = await NativeBridge.instance.fetchMetadata(url);
      final title = metadata['title'] as String? ?? 'Video $taskId';
      final duration = (metadata['duration'] as num?)?.toInt() ?? 0;
      final thumbnail = metadata['thumbnail'] as String?;
      final uploader = metadata['uploader'] as String?;

      final downloadedVideos =
          await StorageManager.instance.scanDownloadedVideos();
      final currentTotalSec = downloadedVideos.fold<int>(
          0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = settings.maxVideoDurationHours * 3600;

      if (duration > 0 && (currentTotalSec + duration) > maxDurationSec) {
        task.status = DownloadStatus.error;
        final totalHours =
            ((currentTotalSec + duration) / 3600).toStringAsFixed(1);
        task.errorMessage =
            'Toplam video süresi ($totalHours sa), belirlenen toplam kotayı (${settings.maxVideoDurationHours} sa) aşacağı için eklenmedi.';
        _saveTasksToStorage();
        notifyListeners();
        return task.errorMessage;
      }

      task.title = title;
      task.durationSeconds = duration;
      task.thumbnail = thumbnail;
      task.uploader = uploader;
      task.status = DownloadStatus.queued;
      _saveTasksToStorage();
      notifyListeners();

      if (!_isQueuePaused) {
        await processNextQueue(settings: settings);
      }
      return null;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = 'Hata: ${cleanErrorMessage(e)}';
      _saveTasksToStorage();
      notifyListeners();
      return task.errorMessage;
    }
  }

  Future<String?> _addPlaylistDownload({
    required String url,
    required AppSettings settings,
  }) async {
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final loadingTask = DownloadTask(
      id: tempId,
      url: url,
      title: 'Oynatma listesi ayrıştırılıyor...',
      status: DownloadStatus.fetchingMetadata,
    );

    _tasks.insert(0, loadingTask);
    notifyListeners();

    try {
      final entries = await NativeBridge.instance.fetchPlaylistEntries(url);
      _tasks.removeWhere((t) => t.id == tempId);

      if (entries.isEmpty) {
        _saveTasksToStorage();
        notifyListeners();
        return 'Oynatma listesinde indirilebilir video bulunamadı.';
      }

      final downloadedVideos =
          await StorageManager.instance.scanDownloadedVideos();
      int runningTotalSec = downloadedVideos.fold<int>(
          0, (sum, v) => sum + (v.durationSeconds ?? 0));
      final maxDurationSec = settings.maxVideoDurationHours * 3600;
      int addedCount = 0;
      int skippedCount = 0;

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final videoUrl = entry['url'] as String? ?? '';
        final title = entry['title'] as String? ?? 'Video ${i + 1}';
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        final thumbnail = entry['thumbnail'] as String?;
        final uploader = entry['uploader'] as String?;

        if (videoUrl.isEmpty) continue;

        if (duration > 0 && (runningTotalSec + duration) > maxDurationSec) {
          skippedCount++;
          continue;
        }

        runningTotalSec += duration;
        final taskId = '${DateTime.now().millisecondsSinceEpoch}_$i';
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
          thumbnail: thumbnail,
          durationSeconds: duration,
          uploader: uploader,
          status: DownloadStatus.queued,
        );

        _tasks.add(newTask);
        addedCount++;
      }

      await _saveTasksToStorage();
      notifyListeners();

      if (!_isQueuePaused) {
        await processNextQueue(settings: settings);
      }

      if (addedCount == 0 && skippedCount > 0) {
        return 'Tüm videolar ($skippedCount adet) belirlenen toplam süre kotasını (${settings.maxVideoDurationHours} sa) aşacağı için eklenmedi.';
      }

      return null;
    } catch (e) {
      loadingTask.status = DownloadStatus.error;
      loadingTask.errorMessage = 'Hata: ${cleanErrorMessage(e)}';
      _saveTasksToStorage();
      notifyListeners();
      return loadingTask.errorMessage;
    }
  }

  // --- 7. TEKİL GÖREV İŞLEMLERİ ---

  Future<void> pauseTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index].status = DownloadStatus.paused;
      _tasks[index].speed = '';
      if (_activeTaskId == taskId) {
        _activeTaskId = null;
      }
      _saveTasksToStorage();
      notifyListeners();
      await NativeBridge.instance.pauseDownload(taskId);
    }
  }

  Future<void> resumeTask(String taskId, [AppSettings? settings]) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index].status = DownloadStatus.queued;
      _tasks[index].errorMessage = null;
      _saveTasksToStorage();
      notifyListeners();

      if (!_isQueuePaused) {
        await processNextQueue(settings: settings ?? _lastSettings);
      }
    }
  }

  Future<void> cancelTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index].status = DownloadStatus.cancelled;
      _tasks[index].speed = '';
      if (_activeTaskId == taskId) {
        _activeTaskId = null;
      }
      _saveTasksToStorage();
      notifyListeners();
      await NativeBridge.instance.cancelDownload(taskId);
      _triggerNextQueue();
    }
  }

  void removeTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    _saveTasksToStorage();
    notifyListeners();
  }

  void clearErrors() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.error);
    _saveTasksToStorage();
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled);
    _saveTasksToStorage();
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
