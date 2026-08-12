import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/download_task.dart';
import '../models/video_item.dart';
import '../providers/library_provider.dart';
import '../services/native_bridge.dart';
import '../services/network_manager.dart';
import '../services/storage_manager.dart';

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
  static const String _tasksPrefKey = 'offline_youtube_persisted_tasks_v3';
  static const String _queuePausedPrefKey = 'offline_youtube_queue_paused_v3';

  final List<DownloadTask> _tasks = [];
  bool _isProcessingQueue = false;
  String? _activeTaskId;
  bool _isQueuePaused = false;
  bool _isWifiWaiting = false;
  bool _isLoaded = false;
  bool _isAutoUpdatingEngine = false;
  bool _isSyncingPlaylists = false;
  AppSettings? _lastSettings;
  VoidCallback? onLibraryNeedsRefresh;

  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _watchdogTimer;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get isProcessingQueue => _isProcessingQueue;
  String? get activeTaskId => _activeTaskId;
  bool get isQueuePaused => _isQueuePaused;
  bool get isWifiWaiting => _isWifiWaiting;
  bool get isLoaded => _isLoaded;
  bool get isSyncingPlaylists => _isSyncingPlaylists;

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
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedState();
    _listenToNativeEvents();
    _listenToConnectivity();
    _startWatchdogTimer();
  }

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _runWatchdogCheck();
    });
  }

  Future<void> _runWatchdogCheck() async {
    if (!_isLoaded || _isQueuePaused) return;

    final hasPendingTasks = _tasks.any(
      (t) =>
          // FIX(backoff): Tasks in 429 exponential backoff carry a scheduled
          // retry message; the watchdog must NOT restart them early, otherwise
          // the 15/30/60/120/300s backoff is bypassed and all retries burn out.
          (t.status == DownloadStatus.queued &&
              t.errorMessage?.contains('yeniden deneniyor') != true) ||
          (t.status == DownloadStatus.paused &&
              (t.errorMessage?.contains('Mobil veri') == true ||
                  t.errorMessage?.contains('Wi-Fi') == true ||
                  t.errorMessage?.contains('Ağ bağlantısı') == true ||
                  t.errorMessage?.contains('İnternet') == true)),
    );

    if (hasPendingTasks) {
      await _evaluateConditionsAndAutoResume();
      if (_activeTaskId == null && !isDownloadingActive) {
        processNextQueue();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runWatchdogCheck();
    }
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

            // Başlık null veya geçersiz ise düzelt
            final cleanTitle = task.title.trim();
            if (cleanTitle.isEmpty ||
                cleanTitle.toLowerCase() == 'null' ||
                cleanTitle.toLowerCase() == 'null null') {
              final vid = VideoItem.extractVideoId(task.url);
              task.title = vid != null ? 'Video ($vid)' : 'YouTube Videosu';
            }

            // Silinmiş/gizli videoları kuyruktan tamamen temizle
            final lowerTitle = task.title.toLowerCase();
            if (lowerTitle.contains('[deleted') ||
                lowerTitle.contains('[private') ||
                lowerTitle.contains('[unavailable')) {
              continue;
            }

            // Uygulama kapatılıp açıldığında bitmemiş olan tüm görevleri (downloading, paused, fetching)
            // 'queued' durumuna alarak kuyruğun otomatik devam etmesini sağla
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.fetchingMetadata ||
                task.status == DownloadStatus.paused) {
              task.status = DownloadStatus.queued;
              task.speed = '';
              task.errorMessage = null;
            }
            // Tekrar eden (duplicate) görevleri kuyruğa ekleme
            final taskVid = VideoItem.extractVideoId(task.url);
            final isDuplicate = _tasks.any((existing) {
              final existingVid = VideoItem.extractVideoId(existing.url);
              return existing.url == task.url ||
                  (taskVid != null && existingVid == taskVid);
            });
            if (isDuplicate) {
              continue;
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

      // Açılışta bekleyen veya hatalı görevler varsa ve master pause yoksa hemen kuyruğu başlat
      if (!_isQueuePaused &&
          _tasks.any((t) =>
              t.status == DownloadStatus.queued ||
              t.status == DownloadStatus.error)) {
        if (_lastSettings != null) {
          await _evaluateConditionsAndAutoResume();
          processNextQueue(settings: _lastSettings);
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
    if (!_isQueuePaused &&
        _tasks.any((t) =>
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.error)) {
      processNextQueue(settings: settings);
    }
  }

  /// Duraklatılmış bir görevin koşullar düzelince otomatik yeniden başlatılıp
  /// başlatılamayacağını belirler (ağ + kota mesajları).
  /// FIX(quota-resume): Kota nedeniyle duraklatılan görevler de dahil edildi —
  /// önceden yalnızca ağ mesajlı görevler yeniden kuyruğa alınıyor, depolama/süre
  /// kotası mesajlı görevler sonsuza dek duraklı kalıyordu.
  bool _isAutoResumablePausedTask(DownloadTask t) {
    final msg = t.errorMessage;
    if (msg == null) return false;
    return msg.contains('Mobil veri') ||
        msg.contains('Wi-Fi') ||
        msg.contains('Ağ bağlantısı') ||
        msg.contains('İnternet') ||
        msg.contains('kotası') ||
        msg.contains('doldu');
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
                _isAutoResumablePausedTask(t)) {
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
        // FIX(connectivity): Sadece gerçek bir bağlantı varsa görevleri kuyruğa
        // al; bağlantı yoksa "Ağ bağlantısı kesildi" mesajı açıklama olarak
        // kalsın (yoksa kullanıcı çevrimdışıyken görev sessizce "sırada" görünür).
        final connectivity = await NetworkManager.instance.getCurrentConnectivity();
        final hasConnection = connectivity.contains(ConnectivityResult.wifi) ||
            connectivity.contains(ConnectivityResult.mobile);
        if (hasConnection) {
          for (final t in _tasks) {
            if (t.status == DownloadStatus.paused &&
                _isAutoResumablePausedTask(t)) {
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
      // FIX(async): callback async — completed dalında disk taraması await ile
      // yapılır (UI thread'i bloklamaz).
      (data) async {
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
            final totalSize = data['totalSize']?.toString() ?? '';
            final downloadedSize = data['downloadedSize']?.toString() ?? '';

            if (task.status == DownloadStatus.downloading) {
              task.progress = progress;
              task.etaSeconds = eta;
              task.speed = speed;
              if (totalSize.isNotEmpty) task.totalSize = totalSize;
              if (downloadedSize.isNotEmpty) task.downloadedSize = downloadedSize;
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
            // FIX(match): Eşleştirme artık benzersiz [videoId] işaretine
            // öncelik veriyor; alt-dize (substring) başlık eşleşmesi, başlığı
            // diğerinin öneki olan iki videoda YANLIŞ dosyaya metadata yazıyordu.
            // FIX(perf): listSync() yerine asenkron list() — ana izolate bloklanmaz.
            try {
              final dir = Directory(StorageManager.instance.currentDownloadPath);
              if (dir.existsSync()) {
                final files = await dir.list().toList();
                final cleanTaskTitle = task.title
                    .replaceAll(RegExp(r'[^a-zA-Z0-9ığüşöçİĞÜŞÖÇ]'), '')
                    .toLowerCase();
                final vid = VideoItem.extractVideoId(task.url);
                for (final f in files) {
                  if (f is File) {
                    final ext = f.path.split('.').last.toLowerCase();
                    if (['mp4', 'mkv', 'webm', 'ts', '3gp', 'm4a'].contains(ext)) {
                      final name = f.path.split(Platform.pathSeparator).last;
                      final cleanName = name
                          .replaceAll(RegExp(r'[^a-zA-Z0-9ığüşöçİĞÜŞÖÇ]'), '')
                          .toLowerCase();
                      // yt-dlp şablonu her zaman "Başlık [videoId].ext" üretir.
                      final matchesVid = vid != null && name.contains('[$vid]');
                      // YouTube dışı URL'ler (vid == null) için güvenli önek eşleşmesi.
                      final matchesPrefixFallback = vid == null &&
                          cleanTaskTitle.isNotEmpty &&
                          cleanName.startsWith(cleanTaskTitle);
                      if (matchesVid || matchesPrefixFallback) {
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
                task.hadPreviousError = true;
                task.speed = '';
                task.errorMessage =
                    '⚠️ Ağ bağlantısı kesildi. İnternet sağlandığında otomatik devam edecek.';
                if (_activeTaskId == taskId) {
                  _activeTaskId = null;
                }
                if (_lastSettings?.networkMode == NetworkRestrictionMode.anyWifi) {
                  _isWifiWaiting = true;
                }
                _saveTasksToStorage();
                notifyListeners();
                // Ağ yokken diğer görevleri peş peşe hata durumuna düşürmemek için kuyruğu durdur
                return;
              }

              final isRateLimit = rawError.contains('429') ||
                  rawError.toLowerCase().contains('too many requests');

              if (isRateLimit && task.retryCount < 5) {
                // YouTube rate limit (429) - Exponential backoff: 15s, 30s, 60s, 120s, 300s
                final backoffSeconds = [15, 30, 60, 120, 300];
                final waitSeconds = backoffSeconds[task.retryCount.clamp(0, backoffSeconds.length - 1)];
                task.retryCount++;
                task.status = DownloadStatus.queued;
                task.hadPreviousError = true;
                task.speed = '';
                task.errorMessage = '⏳ İstek limiti (429). ${waitSeconds}s sonra yeniden deneniyor... (${task.retryCount}/5)';
                if (_activeTaskId == taskId) {
                  _activeTaskId = null;
                }
                _saveTasksToStorage();
                notifyListeners();
                _triggerNextQueue(delayMs: waitSeconds * 1000);
                return;
              }

              if (task.retryCount < 1) {
                // 1 kez otomatik hızlı tekrar dene
                task.retryCount++;
                task.status = DownloadStatus.queued;
                task.hadPreviousError = true;
                task.speed = '';
                task.errorMessage = null;
                if (_activeTaskId == taskId) {
                  _activeTaskId = null;
                }
                _saveTasksToStorage();
                notifyListeners();
                _triggerNextQueue(delayMs: 2000);
                return;
              }

              // Normal denemeler tükendi: Motoru güncelle ve güncellenirse yeniden dene
              if (!_isAutoUpdatingEngine) {
                _isAutoUpdatingEngine = true;
                task.status = DownloadStatus.fetchingMetadata;
                task.speed = '';
                task.errorMessage = 'İndirme motoru güncelleniyor...';
                notifyListeners();

                NativeBridge.instance.updateYtDlp().then((updated) {
                  _isAutoUpdatingEngine = false;
                  if (updated) {
                    task.retryCount = 0;
                    task.status = DownloadStatus.queued;
                    task.hadPreviousError = true;
                    task.errorMessage = null;
                    if (_activeTaskId == taskId) {
                      _activeTaskId = null;
                    }
                    _saveTasksToStorage();
                    notifyListeners();
                    _triggerNextQueue(delayMs: 1500);
                  } else {
                    task.status = DownloadStatus.error;
                    task.hadPreviousError = true;
                    task.speed = '';
                    task.errorMessage = cleanErrorMessage(rawError);
                    if (_activeTaskId == taskId) {
                      _activeTaskId = null;
                    }
                    _saveTasksToStorage();
                    notifyListeners();
                    _triggerNextQueue(delayMs: 1500);
                  }
                }).catchError((_) {
                  _isAutoUpdatingEngine = false;
                  task.status = DownloadStatus.error;
                  task.hadPreviousError = true;
                  task.speed = '';
                  task.errorMessage = cleanErrorMessage(rawError);
                  if (_activeTaskId == taskId) {
                    _activeTaskId = null;
                  }
                  _saveTasksToStorage();
                  notifyListeners();
                  _triggerNextQueue(delayMs: 1500);
                });
              } else {
                task.status = DownloadStatus.error;
                task.hadPreviousError = true;
                task.speed = '';
                task.errorMessage = cleanErrorMessage(rawError);
                if (_activeTaskId == taskId) {
                  _activeTaskId = null;
                }
                _saveTasksToStorage();
                notifyListeners();
                _triggerNextQueue(delayMs: 1500);
              }
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
      onError: (error) {
        // Event channel hatası
      },
    );
  }

  void _triggerNextQueue({int delayMs = 1200}) {
    if (_isQueuePaused) return;

    Future.delayed(Duration(milliseconds: delayMs), () {
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

    await NativeBridge.instance.stopDownloadService();
    await _saveTasksToStorage();
    notifyListeners();
  }

  Future<void> resumeQueue({AppSettings? settings}) async {
    _isQueuePaused = false;

    for (final t in _tasks) {
      if (t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.error) {
        t.status = DownloadStatus.queued;
        t.errorMessage = null;
        t.retryCount = 0;
      }
    }

    await _saveTasksToStorage();
    notifyListeners();

    await processNextQueue(settings: settings ?? _lastSettings);
  }

  Future<void> processNextQueue({AppSettings? settings}) async {
    if (_isQueuePaused) return;
    if (_isProcessingQueue) return;

    // FIX(race): Set the processing flag BEFORE the first await. Previously the
    // flag was set after slow network/storage checks, so two concurrent callers
    // (watchdog + connectivity event) could both pass the guard and start the
    // SAME task twice on the native side (two yt-dlp processes, one output file).
    _isProcessingQueue = true;
    try {
      final currentSettings = settings ?? _lastSettings;
      if (currentSettings != null) {
        _lastSettings = currentSettings;

        // 1. Ağ kontrolü
        final netCheck = await NetworkManager.instance
            .checkNetworkPermissionAndStatus(currentSettings)
            .timeout(const Duration(seconds: 5), onTimeout: () => {'allowed': false, 'reason': 'Ağ kontrolü zaman aşımına uğradı.'});
        if (netCheck['allowed'] != true) {
          _isWifiWaiting =
              currentSettings.networkMode == NetworkRestrictionMode.anyWifi;
          _failNextTaskIfAny(netCheck['reason'] ?? 'Ağ izni yok.');
          notifyListeners();
          return;
        }

        // 2. Depolama kotası kontrolü
        final maxBytes = currentSettings.maxStorageLimitGB * 1024 * 1024 * 1024;
        final usedBytes = await StorageManager.instance.getUsedStorageBytes()
            .timeout(const Duration(seconds: 5), onTimeout: () => 0);
        if (usedBytes >= maxBytes) {
          _failNextTaskIfAny('Depolama kotası doldu (${currentSettings.maxStorageLimitGB} GB).');
          notifyListeners();
          return;
        }

        // 3. Toplam video süresi kotası kontrolü
        final downloadedVideos =
            await StorageManager.instance.scanDownloadedVideos()
            .timeout(const Duration(seconds: 10), onTimeout: () => []);
        final totalDurationSec = downloadedVideos.fold<int>(
            0, (sum, v) => sum + (v.durationSeconds ?? 0));
        final maxDurationSec = currentSettings.maxVideoDurationHours * 3600;
        if (totalDurationSec >= maxDurationSec) {
          _failNextTaskIfAny('Video süresi kotası doldu (${currentSettings.maxVideoDurationHours} saat).');
          notifyListeners();
          return;
        }
      }

      // FIX(race): Re-check the master pause after the awaited checks above —
      // the user may have paused the whole queue while we were scanning.
      if (_isQueuePaused) return;

      if (_activeTaskId != null) {
        final activeIndex = _tasks.indexWhere((t) => t.id == _activeTaskId);
        if (activeIndex != -1 &&
            _tasks[activeIndex].status == DownloadStatus.downloading) {
          return;
        }
      }

      // Sıradaki ilk 'queued' görevi seç
      final nextTaskIndex = _tasks.indexWhere(
        (t) => t.status == DownloadStatus.queued,
      );

      if (nextTaskIndex == -1) {
        if (!isDownloadingActive) {
          NativeBridge.instance.stopDownloadService();
        }
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
        nextTask.hadPreviousError = true;
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

  void _failNextTaskIfAny(String errorMessage) {
    final nextTaskIndex = _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
    if (nextTaskIndex != -1) {
      _tasks[nextTaskIndex].status = DownloadStatus.error;
      _tasks[nextTaskIndex].hadPreviousError = true;
      _tasks[nextTaskIndex].errorMessage = errorMessage;
      _saveTasksToStorage();
    }
  }

  // --- 5. URL DOĞRULAMA VE HATA TEMİZLEME ---

  static String? extractYouTubeUrl(String input) {
    // URL'yi metin içinden Regex ile çıkar
    final regex = RegExp(r'(https?://[^\s]+)');
    final match = regex.firstMatch(input);
    if (match != null) {
      final url = match.group(0);
      if (url != null) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
          final host = uri.host.toLowerCase();
          final validHosts = [
            'youtube.com',
            'www.youtube.com',
            'm.youtube.com',
            'music.youtube.com',
            'youtu.be',
          ];
          if (validHosts.contains(host) || host.endsWith('.youtube.com')) {
            if (uri.path.isNotEmpty) {
              return url;
            }
          }
        }
      }
    }
    
    // 2. Eğer URL formatında değilse (http ile başlamıyorsa), kullanıcı muhtemelen 
    // eksik bir link kopyaladı (örneğin sadece "W_XeikiQY_y2&si=..." gibi bir ID kısmı)
    final cleanInput = input.trim();
    if (!cleanInput.toLowerCase().startsWith('http')) {
      // & veya ? işaretinden sonrasını (parametreleri) at
      var rawId = cleanInput.split('&')[0].split('?')[0];
      
      // Sadece a-z, A-Z, 0-9, _, - karakterlerini içeriyorsa bu muhtemelen bir video ID'sidir
      // (10-12 karakter uzunluğundaysa)
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
        result.toLowerCase().contains('confirms you\'re not a bot') ||
        result.toLowerCase().contains('botguard') ||
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
        result.toLowerCase().contains('too many requests') ||
        result.toLowerCase().contains('http error 429') ||
        result.toLowerCase().contains('rate limit')) {
      return 'YouTube istek sınırı aşıldı. Uygulama otomatik yeniden deneyecek.';
    }

    // Depolama / Dosya Sistemi Hatası (invalid argument tek başına yeterli değil, dosya bağlamıyla birlikte olmalı)
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
        task.retryCount = 0;
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
    final videoId = VideoItem.extractVideoId(url);
    
    // Check if already in queue
    final isAlreadyInQueue = _tasks.any((t) {
      final tId = VideoItem.extractVideoId(t.url);
      return t.url == url || (videoId != null && tId == videoId);
    });
    if (isAlreadyInQueue) {
      return 'Bu video zaten indirme listesinde mevcut.';
    }

    // Check if already downloaded
    final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
    final isAlreadyDownloaded = downloadedVideos.any((v) {
      return v.sourceUrl == url || 
             (videoId != null && (v.youtubeId == videoId || v.id == videoId));
    });
    if (isAlreadyDownloaded) {
      return 'Bu video zaten indirilmiş durumda.';
    }

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
        // FIX(quota): Kota aşıldığında görevi kuyruktan TAMAMEN kaldır (daha
        // önce hata durumunda kuyrukta kalıyor, "Hata Oluştu" filtresinde
        // kirlilik yaratıyor ve retryAllErrors bu videoyu yanlışlıkla tekrar
        // indiriyordu).
        _tasks.removeWhere((t) => t.id == task.id);
        final totalHours =
            ((currentTotalSec + duration) / 3600).toStringAsFixed(1);
        _saveTasksToStorage();
        notifyListeners();
        return 'Toplam video süresi ($totalHours sa), belirlenen toplam kotayı (${settings.maxVideoDurationHours} sa) aşacağı için eklenmedi.';
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
      int unavailableCount = 0;

      // fetchPlaylistEntries returns entries in YouTube's default (newest-first) order,
      // so reversing is only needed when the setting is OFF (oldest first).
      // Mirrors syncSavedPlaylists ordering.
      final effectiveEntries = settings.playlistReverseOrder
          ? entries
          : entries.reversed.toList();

      for (int i = 0; i < effectiveEntries.length; i++) {
        final entry = effectiveEntries[i];
        final videoUrl = (entry['url'] as String? ?? '').trim();
        var title = (entry['title'] as String? ?? '').trim();
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        var thumbnail = (entry['thumbnail'] as String? ?? '').trim();
        var uploader = (entry['uploader'] as String? ?? '').trim();

        if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') {
          unavailableCount++;
          continue;
        }

        final lowerTitle = title.toLowerCase();
        if (lowerTitle.contains('[deleted') ||
            lowerTitle.contains('[private') ||
            lowerTitle.contains('[unavailable') || 
            title.isEmpty || 
            lowerTitle == 'null' || 
            lowerTitle == 'null null') {
          unavailableCount++;
          continue;
        }

        if (thumbnail.isEmpty || thumbnail.toLowerCase() == 'null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          thumbnail = vid != null ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '';
        }

        if (uploader.toLowerCase() == 'null') {
          uploader = '';
        }

        // Check if already in queue or downloaded
        final entryVid = VideoItem.extractVideoId(videoUrl);
        final isAlreadyInQueue = _tasks.any((t) {
          final tVid = VideoItem.extractVideoId(t.url);
          return t.url == videoUrl || (entryVid != null && tVid == entryVid);
        });
        final isAlreadyDownloaded = downloadedVideos.any((v) {
          return v.sourceUrl == videoUrl || 
                 (entryVid != null && (v.youtubeId == entryVid || v.id == entryVid));
        });

        if (isAlreadyInQueue || isAlreadyDownloaded) {
          continue; // Skip duplicate video
        }

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
          thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
          durationSeconds: duration,
          uploader: uploader.isNotEmpty ? uploader : null,
          status: DownloadStatus.queued,
          // FIX(sync): Görevin kaynak listesini işaretle — senkron temizliği
          // yalnızca bu listeye ait görevleri kaldırabilir.
          sourcePlaylistUrl: url,
        );

        _tasks.add(newTask);
        addedCount++;
      }

      await _saveTasksToStorage();
      notifyListeners();

      if (!_isQueuePaused) {
        await processNextQueue(settings: settings);
      }

      if (unavailableCount > 0) {
        return addedCount > 0 
            ? 'Gizli veya silinmiş $unavailableCount video atlandı, $addedCount video kuyruğa eklendi.'
            : 'Gizli veya silinmiş $unavailableCount video atlandı. Eklenecek başka video bulunamadı.';
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

  /// Kayıtlı oynatma listelerini YouTube ile senkronize eder:
  /// - YouTube'dan silinmiş videoları kuyruktan (bekleyen/duraklı görevler) temizler.
  /// - Yeni eklenen videoları kuyruğun en tepesine ekler.
  /// - İndirme kurallarını (Wi-Fi, kota, saat) harfiyen uygular.
  /// Not: İndirilmiş dosyalar asla otomatik silinmez (kullanıcı güvenliği).
  Future<PlaylistSyncResult> syncSavedPlaylists({
    required AppSettings settings,
    required LibraryProvider libraryProvider,
  }) async {
    if (_isSyncingPlaylists) {
      return const PlaylistSyncResult(
        success: false,
        message: 'Senkronizasyon zaten devam ediyor',
      );
    }
    if (settings.savedPlaylists.isEmpty) {
      return const PlaylistSyncResult(
        success: false,
        message: 'Kayıtlı oynatma listesi bulunamadı',
      );
    }

    _isSyncingPlaylists = true;
    notifyListeners();

    int deletedCount = 0;
    int addedCount = 0;
    bool anyPlaylistSucceeded = false;

    try {
      final downloadedVideos =
          await StorageManager.instance.scanDownloadedVideos();
      final currentQueueTasks = List<DownloadTask>.from(_tasks);

      final Set<String> currentOnlineVideoIds = {};
      final Set<String> currentOnlineUrls = {};
      final Set<String> currentOnlineTitles = {};
      final List<Map<String, dynamic>> allNewEntries = [];

      for (final playlistUrl in settings.savedPlaylists) {
        if (playlistUrl.trim().isEmpty) continue;
        try {
          final entries =
              await NativeBridge.instance.fetchPlaylistEntries(playlistUrl);
          if (entries.isNotEmpty) {
            anyPlaylistSucceeded = true;
          }
          for (final entry in entries) {
            final u = (entry['url'] as String? ?? '').trim();
            final vid = VideoItem.extractVideoId(u) ??
                (entry['id'] as String? ?? '').trim();
            if (vid.isNotEmpty) currentOnlineVideoIds.add(vid);
            if (u.isNotEmpty) currentOnlineUrls.add(u);
            final t = (entry['title'] as String? ?? '').trim();
            if (t.isNotEmpty &&
                !t.toLowerCase().contains('[deleted') &&
                !t.toLowerCase().contains('[private')) {
              currentOnlineTitles.add(t.toLowerCase());
            }

            final isAlreadyDownloaded = downloadedVideos.any((v) =>
                (v.youtubeId != null && v.youtubeId == vid) ||
                (v.sourceUrl != null && v.sourceUrl == u) ||
                v.title.trim().toLowerCase() == t.toLowerCase());

            final isAlreadyInQueue = currentQueueTasks.any((t) =>
                (VideoItem.extractVideoId(t.url) != null &&
                    VideoItem.extractVideoId(t.url) == vid) ||
                t.url == u);

            final isAlreadyInBatch = allNewEntries.any((e) {
              final eUrl = (e['url'] as String? ?? '').trim();
              final eVid = VideoItem.extractVideoId(eUrl) ??
                  (e['id'] as String? ?? '').trim();
              return (vid.isNotEmpty && eVid == vid) || (u.isNotEmpty && eUrl == u);
            });

            if (!isAlreadyDownloaded && !isAlreadyInQueue && !isAlreadyInBatch) {
              // FIX(sync): Kaynak playlist URL'sini entry ile birlikte sakla ki
              // oluşturulan görev doğru listeye bağlanabilsin.
              allNewEntries.add({
                ...entry,
                '_sourcePlaylistUrl': playlistUrl,
              });
            }
          }
        } catch (_) {
          // Bir listede hata olursa diğerlerine devam et
        }
      }

      // FIX(sync-cleanup): YouTube'dan artık çevrimiçi olmayan videoları
      // kuyruktan (queued/paused görevler) temizle. Önceden deletedCount hep 0
      // kalıyor ve docstring'in vaat ettiği temizlik hiç gerçekleşmiyordu.
      // Yalnızca kayıtlı listelerden gelen görevler silinir — elle eklenen
      // tek videolar ve indirilen dosyalar asla dokunulmaz (kullanıcı güvenliği).
      for (final t in List.of(_tasks)) {
        final belongsToSavedPlaylist = t.sourcePlaylistUrl != null &&
            settings.savedPlaylists.contains(t.sourcePlaylistUrl);
        if (!belongsToSavedPlaylist) continue;
        if (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.paused) {
          final tVid = VideoItem.extractVideoId(t.url);
          final stillOnline =
              (tVid != null && currentOnlineVideoIds.contains(tVid)) ||
                  currentOnlineUrls.contains(t.url);
          if (!stillOnline) {
            _tasks.remove(t);
            deletedCount++;
          }
        }
      }

      // Not: İndirilen videolar asla otomatik silinmez (kullanıcı güvenliği)

      // 2. YENİ EKLENEN videoları kuyruğun EN BAŞINA (Öncelikli) ekle
      final maxDurationSec = settings.maxVideoDurationHours * 3600;
      final refreshedDownloads =
          await StorageManager.instance.scanDownloadedVideos();
      int runningTotalSec = refreshedDownloads.fold<int>(
          0, (sum, v) => sum + (v.durationSeconds ?? 0));

      final effectiveNewEntries = settings.playlistReverseOrder
          ? allNewEntries
          : allNewEntries.reversed.toList();

      for (int i = effectiveNewEntries.length - 1; i >= 0; i--) {
        final entry = effectiveNewEntries[i];
        final videoUrl = (entry['url'] as String? ?? '').trim();
        var title = (entry['title'] as String? ?? '').trim();
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        var thumbnail = (entry['thumbnail'] as String? ?? '').trim();
        var uploader = (entry['uploader'] as String? ?? '').trim();

        if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') continue;

        final lowerTitle = title.toLowerCase();
        if (lowerTitle.contains('[deleted') ||
            lowerTitle.contains('[private') ||
            lowerTitle.contains('[unavailable')) {
          continue;
        }

        if (title.isEmpty || lowerTitle == 'null' || lowerTitle == 'null null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          title = vid != null ? 'Video ($vid)' : 'YouTube Videosu';
        }

        if (thumbnail.isEmpty || thumbnail.toLowerCase() == 'null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          thumbnail =
              vid != null ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '';
        }

        if (uploader.toLowerCase() == 'null') {
          uploader = '';
        }

        if (duration > 0 && (runningTotalSec + duration) > maxDurationSec) {
          continue;
        }

        runningTotalSec += duration;
        final taskId = '${DateTime.now().millisecondsSinceEpoch}_sync_$i';
        final entrySourcePlaylist =
            (entry['_sourcePlaylistUrl'] as String? ?? '').trim();
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
          thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
          durationSeconds: duration,
          uploader: uploader.isNotEmpty ? uploader : null,
          status: DownloadStatus.queued,
          // FIX(sync): Görevin kaynak listesini işaretle — senkron temizliği
          // yalnızca bu listeye ait görevleri kaldırabilir.
          sourcePlaylistUrl:
              entrySourcePlaylist.isNotEmpty ? entrySourcePlaylist : null,
        );

        _tasks.insert(0, newTask);
        addedCount++;
      }

      await _saveTasksToStorage();
      notifyListeners();

      if (!_isQueuePaused) {
        await processNextQueue(settings: settings);
      }

      return PlaylistSyncResult(
        success: anyPlaylistSucceeded,
        newVideosAdded: addedCount,
        deletedVideosRemoved: deletedCount,
      );
    } catch (e) {
      return PlaylistSyncResult(
        success: false,
        message: e.toString(),
      );
    } finally {
      _isSyncingPlaylists = false;
      notifyListeners();
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

  Future<void> removeTask(String taskId) async {
    // FIX(orphan): If the removed task is the ACTIVE download, cancel the native
    // process first. Previously the task was removed but yt-dlp kept running in
    // the foreground service (invisible download + a second download could then
    // start concurrently and both would write into the same folder).
    if (_activeTaskId == taskId) {
      await NativeBridge.instance.cancelDownload(taskId);
      _activeTaskId = null;
    }
    _tasks.removeWhere((t) => t.id == taskId);
    _saveTasksToStorage();
    notifyListeners();
    if (_activeTaskId == null) {
      _triggerNextQueue();
    }
  }

  void prioritizeTask(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _tasks[index];
    
    // Don't reorder if it's already at index 0 or downloading
    if (index == 0 || task.status == DownloadStatus.downloading || task.id == _activeTaskId) return;

    _tasks.removeAt(index);
    
    int insertIndex = 0;
    // Find index after active/downloading tasks
    if (_activeTaskId != null) {
      final activeIndex = _tasks.indexWhere((t) => t.id == _activeTaskId);
      if (activeIndex != -1) {
        insertIndex = activeIndex + 1;
      }
    }
    
    _tasks.insert(insertIndex, task);
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
    WidgetsBinding.instance.removeObserver(this);
    _watchdogTimer?.cancel();
    _eventSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
