import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';

class DownloadProvider extends ChangeNotifier {
  static const String _tasksPrefKey = 'offline_youtube_persisted_tasks_v1';
  static const String _queuePausedPrefKey = 'offline_youtube_queue_paused_state';

  final List<DownloadTask> _tasks = [];
  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectivitySubscription;
  VoidCallback? onLibraryNeedsRefresh;

  String? _activeTaskId;
  bool _isProcessingQueue = false;
  bool _isQueuePaused = false;
  bool _isLoaded = false;
  AppSettings? _lastSettings;
  bool _isWifiWaiting = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get isQueuePaused => _isQueuePaused;
  bool get isLoaded => _isLoaded;
  bool get isWifiWaiting => _isWifiWaiting;

  int get activeDownloadCount => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.fetchingMetadata ||
          t.status == DownloadStatus.queued)
      .length;

  bool get isDownloadingActive =>
      _tasks.any((t) => t.status == DownloadStatus.downloading);

  DownloadTask? get currentDownloadingTask {
    if (_activeTaskId != null) {
      final idx = _tasks.indexWhere((t) => t.id == _activeTaskId);
      if (idx != -1) return _tasks[idx];
    }
    return _tasks.cast<DownloadTask?>().firstWhere(
          (t) => t?.status == DownloadStatus.downloading,
          orElse: () => null,
        );
  }

  DownloadProvider() {
    _loadPersistedState();
    _listenToNativeEvents();
    _listenToConnectivity();
  }

  // --- 1. PERSISTENCE (KALICILIK) ---

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isQueuePaused = prefs.getBool(_queuePausedPrefKey) ?? false;

      final rawList = prefs.getStringList(_tasksPrefKey);
      if (rawList != null && rawList.isNotEmpty) {
        _tasks.clear();
        for (final itemStr in rawList) {
          try {
            final Map<String, dynamic> jsonMap = jsonDecode(itemStr);
            final task = DownloadTask.fromJson(jsonMap);
            // Uygulama kapandığında inmekte olan veya metadata çeken görevleri güvenle 'duraklatıldı' yap
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.fetchingMetadata) {
              task.status = DownloadStatus.paused;
              task.speed = '';
            }
            _tasks.add(task);
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _saveTasksToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_queuePausedPrefKey, _isQueuePaused);

      final strList = _tasks.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_tasksPrefKey, strList);
    } catch (_) {}
  }

  // --- 2. GERÇEK ZAMANLI AĞ VE WI-FI DİNLEME (MOBİL VERİ KORUMASI) ---

  void _listenToConnectivity() {
    _connectivitySubscription =
        NetworkManager.instance.onConnectivityChanged.listen((results) async {
      await _evaluateNetworkGuard();
    });
  }

  Future<void> onSettingsChanged(AppSettings settings) async {
    _lastSettings = settings;
    await _evaluateNetworkGuard();
  }

  Future<void> _evaluateNetworkGuard() async {
    if (_lastSettings == null) return;

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
        // Wi-Fi geri geldi
        if (!_isQueuePaused &&
            _tasks.any((t) => t.status == DownloadStatus.queued)) {
          _triggerNextQueue();
        }
      }
    } else {
      _isWifiWaiting = false;
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
          case 'started':
            task.status = DownloadStatus.downloading;
            break;
          case 'progress':
            task.status = DownloadStatus.downloading;
            task.progress =
                (data['progress'] as num?)?.toDouble() ?? task.progress;
            task.etaSeconds =
                (data['eta'] as num?)?.toInt() ?? task.etaSeconds;
            task.speed = data['speed']?.toString() ?? task.speed;
            break;
          case 'paused':
            task.status = DownloadStatus.paused;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            // DÜZELTME: Duraklatıldığında ASLA bir sonrakine geçilmez!
            _saveTasksToStorage();
            break;
          case 'completed':
            task.status = DownloadStatus.completed;
            task.progress = 100.0;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            onLibraryNeedsRefresh?.call();
            _saveTasksToStorage();
            _triggerNextQueue();
            break;
          case 'cancelled':
            task.status = DownloadStatus.cancelled;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _saveTasksToStorage();
            _triggerNextQueue();
            break;
          case 'error':
            task.status = DownloadStatus.error;
            task.errorMessage = cleanErrorMessage(data['error'] ?? 'Hata oluştu');
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _saveTasksToStorage();
            _triggerNextQueue();
            break;
        }

        notifyListeners();
      },
      onError: (err) {},
    );
  }

  void _triggerNextQueue() {
    if (_isQueuePaused) return;

    Future.delayed(const Duration(milliseconds: 1500), () {
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

    // Duraklatılmış olan kuyruk görevlerini tekrar 'queued' yap
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
      // Ağ kontrolü
      final netCheck = await NetworkManager.instance
          .checkNetworkPermissionAndStatus(currentSettings);
      if (netCheck['allowed'] != true) {
        _isWifiWaiting = currentSettings.networkMode == NetworkRestrictionMode.anyWifi;
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

    final lower = trimmed.toLowerCase();
    final isHttp = lower.startsWith('http://') || lower.startsWith('https://');
    final isYoutubeDomain = lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('yt.be');

    return isHttp && isYoutubeDomain;
  }

  static String cleanErrorMessage(dynamic error) {
    var msg = error.toString();
    if (msg.contains('PlatformException(')) {
      msg = msg
          .replaceAll(RegExp(r'PlatformException\([^,]+,\s*'), '')
          .replaceAll(RegExp(r',\s*null,\s*null\)'), '');
    }
    if (msg.contains('ERROR:')) {
      msg = msg.substring(msg.indexOf('ERROR:') + 6);
    }
    final lines = msg
        .split('\n')
        .where((l) =>
            !l.trim().startsWith('WARNING:') &&
            !l.trim().startsWith('It is strongly') &&
            !l.trim().startsWith('Run "') &&
            !l.trim().startsWith('To suppress'))
        .join('\n');
    return lines.trim().isNotEmpty ? lines.trim() : 'Video bilgisi alınamadı.';
  }

  // --- 6. İNDİRME EKLEME İŞLEMLERİ ---

  Future<String?> addDownload({
    required String url,
    required AppSettings settings,
    required int currentStorageUsedBytes,
  }) async {
    _lastSettings = settings;
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || !isValidYouTubeUrl(cleanUrl)) {
      return 'Geçersiz YouTube bağlantısı. Lütfen geçerli bir video veya oynatma listesi URL\'si girin.';
    }

    final netCheck = await NetworkManager.instance
        .checkNetworkPermissionAndStatus(settings);
    if (netCheck['allowed'] != true) {
      return netCheck['reason'] as String? ?? 'Ağ kısıtlaması engeli.';
    }

    final maxQuotaBytes = settings.maxStorageLimitGB * 1024 * 1024 * 1024;
    if (currentStorageUsedBytes >= maxQuotaBytes) {
      return 'Depolama alanı kotası (${settings.maxStorageLimitGB} GB) dolmuştur. Yeni video indirilemez.';
    }

    final isPlaylist = cleanUrl.contains('list=') ||
        cleanUrl.contains('/playlist') ||
        cleanUrl.contains('/@') ||
        cleanUrl.contains('/channel/');

    if (isPlaylist) {
      return _addPlaylistDownload(
        url: cleanUrl,
        settings: settings,
      );
    } else {
      return _addSingleVideoDownload(
        url: cleanUrl,
        settings: settings,
      );
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
      final duration = metadata['duration'] as int? ?? 0;

      final maxDurationSeconds = settings.maxVideoDurationHours * 3600;
      if (duration > 0 && duration > maxDurationSeconds) {
        task.status = DownloadStatus.error;
        task.errorMessage =
            'Video süresi (${(duration / 3600).toStringAsFixed(1)} sa), belirlenen sınırı (${settings.maxVideoDurationHours} sa) aşıyor.';
        _saveTasksToStorage();
        notifyListeners();
        return task.errorMessage;
      }

      task.title = title;
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

      final maxDurationSeconds = settings.maxVideoDurationHours * 3600;
      int addedCount = 0;
      int skippedCount = 0;

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final videoUrl = entry['url'] as String? ?? '';
        final title = entry['title'] as String? ?? 'Video ${i + 1}';
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;

        if (videoUrl.isEmpty) continue;

        if (duration > 0 && duration > maxDurationSeconds) {
          skippedCount++;
          continue;
        }

        final taskId = '${DateTime.now().millisecondsSinceEpoch}_$i';
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
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
        return 'Tüm videolar ($skippedCount adet) belirlenen süre sınırını (${settings.maxVideoDurationHours} sa) aştığı için eklenmedi.';
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
    if (index == -1) return;

    _tasks[index].status = DownloadStatus.paused;
    _tasks[index].speed = '';
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    await _saveTasksToStorage();
    notifyListeners();

    await NativeBridge.instance.pauseDownload(taskId);
    // DÜZELTME: pauseTask sonrasında ASLA _triggerNextQueue() çağrılmaz!
  }

  Future<void> resumeTask(String taskId, AppSettings settings) async {
    _lastSettings = settings;
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _tasks[index].status = DownloadStatus.queued;
    _tasks[index].errorMessage = null;
    _isQueuePaused = false; // Kullanıcı açıkça bir görevi başlattıysa kuyruğu da aç
    await _saveTasksToStorage();
    notifyListeners();

    await processNextQueue(settings: settings);
  }

  Future<void> cancelTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _tasks[index].status = DownloadStatus.cancelled;
    _tasks[index].speed = '';
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    await _saveTasksToStorage();
    notifyListeners();

    await NativeBridge.instance.cancelDownload(taskId);
    if (!_isQueuePaused) {
      _triggerNextQueue();
    }
  }

  void removeTask(String taskId) {
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    _tasks.removeWhere((t) => t.id == taskId);
    _saveTasksToStorage();
    notifyListeners();
    if (!_isQueuePaused) {
      _triggerNextQueue();
    }
  }

  void clearErrors() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.error);
    _saveTasksToStorage();
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled ||
        t.status == DownloadStatus.error);
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
