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
            break;
          case 'completed':
            task.status = DownloadStatus.completed;
            task.progress = 100.0;
            task.speed = '';
            onLibraryNeedsRefresh?.call();
            break;
          case 'cancelled':
            task.status = DownloadStatus.cancelled;
            task.speed = '';
            break;
          case 'error':
            task.status = DownloadStatus.error;
            task.errorMessage = data['error']?.toString() ?? 'Hata oluştu';
            task.speed = '';
            break;
        }

        notifyListeners();
      },
      onError: (err) {
        // Ignored
      },
    );
  }

  Future<String?> addDownload({
    required String url,
    required AppSettings settings,
    required int currentStorageUsedBytes,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return 'Lütfen geçerli bir video URL\'si girin.';
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

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: taskId,
      url: cleanUrl,
      title: 'Bilgiler alınıyor...',
      status: DownloadStatus.fetchingMetadata,
    );

    _tasks.insert(0, task);
    notifyListeners();

    try {
      // 3. Metadata Çekme ve Süre Kontrolü
      final metadata = await NativeBridge.instance.fetchMetadata(cleanUrl);
      final title = metadata['title'] as String? ?? 'Video $taskId';
      final duration = metadata['duration'] as int? ?? 0;

      // Maksimum Video Uzunluğu Kontrolü
      final maxDurationSeconds = settings.maxVideoDurationHours * 3600;
      if (duration > 0 && duration > maxDurationSeconds) {
        task.status = DownloadStatus.error;
        task.errorMessage =
            'Video süresi (${(duration / 3600).toStringAsFixed(1)} sa), belirlenen maksimum sınırı (${settings.maxVideoDurationHours} sa) aşıyor.';
        notifyListeners();
        return task.errorMessage;
      }

      task.title = title;
      task.status = DownloadStatus.downloading;
      notifyListeners();

      // 4. İndirmeyi Başlat
      final started = await NativeBridge.instance.startDownload(
        taskId: taskId,
        url: cleanUrl,
        title: title,
        outputPath: StorageManager.instance.currentDownloadPath,
      );

      if (!started) {
        task.status = DownloadStatus.error;
        task.errorMessage = 'İndirme servisi başlatılamadı.';
        notifyListeners();
        return task.errorMessage;
      }

      return null; // Başarılı
    } catch (e) {
      task.status = DownloadStatus.error;
      task.errorMessage = 'Video bilgisi alınamadı: ${e.toString()}';
      notifyListeners();
      return task.errorMessage;
    }
  }

  Future<void> pauseTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    _tasks[index].status = DownloadStatus.paused;
    notifyListeners();
    await NativeBridge.instance.pauseDownload(taskId);
  }

  Future<void> resumeTask(String taskId, AppSettings settings) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _tasks[index];
    task.status = DownloadStatus.downloading;
    notifyListeners();

    await NativeBridge.instance.resumeDownload(
      taskId: task.id,
      url: task.url,
      title: task.title,
      outputPath: StorageManager.instance.currentDownloadPath,
    );
  }

  Future<void> cancelTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    _tasks[index].status = DownloadStatus.cancelled;
    notifyListeners();
    await NativeBridge.instance.cancelDownload(taskId);
  }

  void removeTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
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
