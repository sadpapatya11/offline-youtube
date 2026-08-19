import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';
import 'package:flutter/foundation.dart';
class DownloadQueueManager {
  static final DownloadQueueManager instance = DownloadQueueManager._internal();
  DownloadQueueManager._internal();

  static const String _tasksPrefKey = 'offline_youtube_persisted_tasks_v3';
  static const String _queuePausedPrefKey = 'offline_youtube_queue_paused_v3';

  final List<DownloadTask> tasks = [];
  bool isProcessingQueue = false;
  String? activeTaskId;
  bool isQueuePaused = false;
  bool isWifiWaiting = false;
  bool isLoaded = false;
  
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
    try {
      final prefs = await SharedPreferences.getInstance();
      
      isQueuePaused = prefs.getBool(_queuePausedPrefKey) ?? false;

      final tasksJson = prefs.getString(_tasksPrefKey);
      if (tasksJson != null) {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        tasks.clear();
        for (var item in decoded) {
          final t = DownloadTask.fromJson(item);
          if (t.status == DownloadStatus.downloading) {
            t.status = DownloadStatus.queued;
            t.speed = '';
          }
          tasks.add(t);
        }
      }
    } catch (e) {
      tasks.clear();
    }
  }

  void _listenToConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      _evaluateConditionsAndAutoResume();
    });
  }

  Future<void> _evaluateConditionsAndAutoResume() async {
    if (isQueuePaused || isProcessingQueue) return;
    if (tasks.isEmpty || !tasks.any((t) => t.status == DownloadStatus.queued)) return;

    if (lastSettings != null) {
      final netCheck = await NetworkManager.instance.checkNetworkPermissionAndStatus(lastSettings!);
      if (netCheck['allowed'] == true) {
        isWifiWaiting = false;
        notifyListeners();
        await processNextQueue(settings: lastSettings);
      }
    }
  }

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
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
        final now = DateTime.now();
        for (final t in downloadingTasks) {
          if (t.lastProgressTime != null) {
            final diff = now.difference(t.lastProgressTime!).inSeconds;
            // FFmpeg ile video/ses birleştirmesi veya yavaş ağlar için zaman aşımını 300s yaptık.
            if (diff > 300) {
              t.status = DownloadStatus.error;
              t.hadPreviousError = true;
              t.errorMessage = 'İndirme zaman aşımına uğradı (5 dk işlem yapılmadı).';
              if (activeTaskId == t.id) activeTaskId = null;
              needsUpdate = true;
            }
          } else {
            // If lastProgressTime is somehow null but it's downloading, set it to now so it gets caught next time,
            // or just kill it if we consider it an error state.
            t.lastProgressTime = now;
          }
        }
        if (needsUpdate) {
          saveTasksToStorage();
          notifyListeners();
          _triggerNextQueue();
        }
      }
    });
  }

  void _listenToNativeEvents() {
    _eventSubscription = NativeBridge.instance.downloadEvents.listen(
      (event) async {
        final data = Map<String, dynamic>.from(event);
        final status = data['status'] as String?;
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
          case 'downloading':
            task.status = DownloadStatus.downloading;
            task.progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
            task.speed = data['speed'] as String? ?? '';
            final etaStr = data['eta'] as String?;
            if (etaStr != null && etaStr.contains(':')) {
              final parts = etaStr.split(':');
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
            
            if (onLibraryNeedsRefresh != null) {
              onLibraryNeedsRefresh!();
            }
            
            notifyListeners();
            _triggerNextQueue(delayMs: 2000);
            break;

          case 'error':
            final errorMessage = data['error'] as String? ?? 'Bilinmeyen hata';
            if (!errorMessage.toLowerCase().contains('yayından kaldırılmış') &&
                !errorMessage.toLowerCase().contains('private') &&
                !errorMessage.toLowerCase().contains('unavailable') &&
                task.retryCount < 2) {
              task.retryCount++;
              task.status = DownloadStatus.queued;
              task.errorMessage = 'Hata oluştu, tekrar deneniyor (${task.retryCount}/2)...';
              if (activeTaskId == taskId) {
                activeTaskId = null;
              }
              saveTasksToStorage();
              notifyListeners();
              _triggerNextQueue(delayMs: 3000);
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
      if (currentSettings != null) {
        lastSettings = currentSettings;

        final netCheck = await NetworkManager.instance
            .checkNetworkPermissionAndStatus(currentSettings)
            .timeout(const Duration(seconds: 5), onTimeout: () => {'allowed': false, 'reason': 'Ağ kontrolü zaman aşımına uğradı.'});
        if (netCheck['allowed'] != true) {
          isWifiWaiting = currentSettings.networkMode == NetworkRestrictionMode.anyWifi;
          _failNextTaskIfAny(netCheck['reason'] ?? 'Ağ izni yok.');
          notifyListeners();
          return;
        }

        final maxBytes = currentSettings.maxStorageLimitGB * 1024 * 1024 * 1024;
        final usedBytes = await StorageManager.instance.getUsedStorageBytes()
            .timeout(const Duration(seconds: 5), onTimeout: () => 0);
        if (usedBytes >= maxBytes) {
          _failNextTaskIfAny('Depolama kotası doldu (${currentSettings.maxStorageLimitGB} GB).');
          notifyListeners();
          return;
        }

        final downloadedVideos = await StorageManager.instance.scanDownloadedVideos()
            .timeout(const Duration(seconds: 10), onTimeout: () => []);
        final totalDurationSec = downloadedVideos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));
        final maxDurationSec = currentSettings.maxVideoDurationHours * 3600;
        if (totalDurationSec >= maxDurationSec) {
          _failNextTaskIfAny('Video süresi kotası doldu (${currentSettings.maxVideoDurationHours} saat).');
          notifyListeners();
          return;
        }
      }

      if (isQueuePaused) return;

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

      final started = await NativeBridge.instance.startDownload(
        taskId: nextTask.id,
        url: nextTask.url,
        title: nextTask.title,
        outputPath: StorageManager.instance.currentDownloadPath,
      );

      if (!started) {
        nextTask.status = DownloadStatus.error;
        nextTask.hadPreviousError = true;
        nextTask.errorMessage = 'İndirme başlatılamadı.';
        activeTaskId = null;
        saveTasksToStorage();
        notifyListeners();
        _triggerNextQueue();
      }
    } finally {
      isProcessingQueue = false;
    }
  }

  void _failNextTaskIfAny(String errorMessage) {
    final nextTaskIndex = tasks.indexWhere((t) => t.status == DownloadStatus.queued);
    if (nextTaskIndex != -1) {
      tasks[nextTaskIndex].status = DownloadStatus.error;
      tasks[nextTaskIndex].hadPreviousError = true;
      tasks[nextTaskIndex].errorMessage = errorMessage;
      saveTasksToStorage();
    }
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
