import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';

class DownloadProvider extends ChangeNotifier {
  final List<DownloadTask> _tasks = [];
  StreamSubscription? _eventSubscription;
  VoidCallback? onLibraryNeedsRefresh;

  String? _activeTaskId;
  bool _isProcessingQueue = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get activeDownloadCount => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.fetchingMetadata ||
          t.status == DownloadStatus.queued)
      .length;

  DownloadProvider() {
    _listenToNativeEvents();
  }

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
            task.progress = (data['progress'] as num?)?.toDouble() ?? task.progress;
            task.etaSeconds = (data['eta'] as num?)?.toInt() ?? task.etaSeconds;
            task.speed = data['speed']?.toString() ?? task.speed;
            break;
          case 'paused':
            task.status = DownloadStatus.paused;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _triggerNextQueue();
            break;
          case 'completed':
            task.status = DownloadStatus.completed;
            task.progress = 100.0;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            onLibraryNeedsRefresh?.call();
            _triggerNextQueue();
            break;
          case 'cancelled':
            task.status = DownloadStatus.cancelled;
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _triggerNextQueue();
            break;
          case 'error':
            task.status = DownloadStatus.error;
            task.errorMessage = data['error']?.toString() ?? 'Hata oluştu';
            task.speed = '';
            if (_activeTaskId == taskId) {
              _activeTaskId = null;
            }
            _triggerNextQueue();
            break;
        }

        notifyListeners();
      },
      onError: (err) {
        // Ignored
      },
    );
  }

  void _triggerNextQueue() {
    // Küçük doğal bekleme (2 sn) ile sıradaki videoya geçiş (Anti-ban insan davranışı)
    Future.delayed(const Duration(seconds: 2), () {
      processNextQueue();
    });
  }

  Future<void> processNextQueue({AppSettings? settings}) async {
    if (_isProcessingQueue) return;
    if (_activeTaskId != null) {
      final activeIndex = _tasks.indexWhere((t) => t.id == _activeTaskId);
      if (activeIndex != -1 &&
          _tasks[activeIndex].status == DownloadStatus.downloading) {
        return; // Halen indirme devam ediyor (Sıralı tek tek indirme kuralı)
      }
    }

    _isProcessingQueue = true;
    try {
      final nextTaskIndex = _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
      if (nextTaskIndex == -1) {
        _isProcessingQueue = false;
        return;
      }

      final nextTask = _tasks[nextTaskIndex];
      _activeTaskId = nextTask.id;
      nextTask.status = DownloadStatus.downloading;
      notifyListeners();

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
        notifyListeners();
        _triggerNextQueue();
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<String?> addDownload({
    required String url,
    required AppSettings settings,
    required int currentStorageUsedBytes,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return 'Lütfen geçerli bir video veya oynatma listesi URL\'si girin.';
    }

    // 1. Ağ Kısıtlaması Kontrolü
    final netCheck = await NetworkManager.instance
        .checkNetworkPermissionAndStatus(settings);
    if (netCheck['allowed'] != true) {
      return netCheck['reason'] as String? ?? 'Ağ kısıtlaması engeli.';
    }

    // 2. Kota Yöneticisi Kontrolü
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
    notifyListeners();

    try {
      final metadata = await NativeBridge.instance.fetchMetadata(url);
      final title = metadata['title'] as String? ?? 'Video $taskId';
      final duration = metadata['duration'] as int? ?? 0;

      // Maksimum Video Uzunluğu Kontrolü
      final maxDurationSeconds = settings.maxVideoDurationHours * 3600;
      if (duration > 0 && duration > maxDurationSeconds) {
        task.status = DownloadStatus.error;
        task.errorMessage =
            'Video süresi (${(duration / 3600).toStringAsFixed(1)} sa), belirlenen sınırı (${settings.maxVideoDurationHours} sa) aşıyor.';
        notifyListeners();
        return task.errorMessage;
      }

      task.title = title;
      task.status = DownloadStatus.queued;
      notifyListeners();

      await processNextQueue(settings: settings);
      return null;
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = 'Video bilgisi alınamadı: ${e.toString()}';
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

        // Süre kotası kontrolü: Süreyi aşan videoları otomatik atla
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

      notifyListeners();
      await processNextQueue(settings: settings);

      if (addedCount == 0 && skippedCount > 0) {
        return 'Tüm videolar ($skippedCount adet) belirlenen süre sınırını (${settings.maxVideoDurationHours} sa) aştığı için eklenmedi.';
      }

      return null;
    } catch (e) {
      loadingTask.status = DownloadStatus.error;
      loadingTask.errorMessage = 'Liste alınamadı: ${e.toString()}';
      notifyListeners();
      return loadingTask.errorMessage;
    }
  }

  Future<void> pauseTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _tasks[index].status = DownloadStatus.paused;
    _tasks[index].speed = '';
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    notifyListeners();

    await NativeBridge.instance.pauseDownload(taskId);
    _triggerNextQueue();
  }

  Future<void> resumeTask(String taskId, AppSettings settings) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _tasks[index].status = DownloadStatus.queued;
    _tasks[index].errorMessage = null;
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
    notifyListeners();

    await NativeBridge.instance.cancelDownload(taskId);
    _triggerNextQueue();
  }

  void removeTask(String taskId) {
    if (_activeTaskId == taskId) {
      _activeTaskId = null;
    }
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
    _triggerNextQueue();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled ||
        t.status == DownloadStatus.error);
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
