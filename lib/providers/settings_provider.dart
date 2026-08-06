import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../services/native_bridge.dart';
import '../services/settings_manager.dart';
import '../services/storage_manager.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _hasStoragePermission = false;
  bool _isLoading = true;
  Timer? _wifiAutoReenableTimer;

  AppSettings get settings => _settings;
  bool get hasStoragePermission => _hasStoragePermission;
  bool get isLoading => _isLoading;
  bool get isOnlyWifiEnabled =>
      _settings.networkMode == NetworkRestrictionMode.anyWifi;

  SettingsProvider() {
    _init();
  }

  @override
  void dispose() {
    _wifiAutoReenableTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _settings = await SettingsManager.instance.loadSettings();
    await StorageManager.instance.initDirectory(_settings.customDownloadPath);
    await checkPermission();

    // Sadece Wi-Fi 1 saat sonra otomatik tekrar açılma kontrolü
    if (_settings.networkMode == NetworkRestrictionMode.allNetworks) {
      final disabledTime =
          await SettingsManager.instance.getWifiDisabledTimestamp();
      if (disabledTime != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - disabledTime;
        const oneHourMs = 60 * 60 * 1000;
        if (elapsed >= oneHourMs) {
          // 1 saat dolmuş -> Otomatik olarak Sadece Wi-Fi moduna geri al
          await setOnlyWifi(true);
        } else {
          // Kalan süre için zamanlayıcı başlat
          final remainingMs = oneHourMs - elapsed;
          _wifiAutoReenableTimer?.cancel();
          _wifiAutoReenableTimer = Timer(Duration(milliseconds: remainingMs), () {
            setOnlyWifi(true);
          });
        }
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> checkPermission() async {
    _hasStoragePermission = await NativeBridge.instance.hasAllFilesPermission();
    notifyListeners();
  }

  Future<void> requestPermission() async {
    await NativeBridge.instance.requestAllFilesPermission();
    await Future.delayed(const Duration(seconds: 1));
    await checkPermission();
  }

  Future<void> updateStorageLimit(int limitGB) async {
    if (limitGB < 1) limitGB = 1;
    _settings = _settings.copyWith(maxStorageLimitGB: limitGB);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateMaxVideoDuration(int hours) async {
    if (hours < 1) hours = 1;
    _settings = _settings.copyWith(maxVideoDurationHours: hours);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateNetworkMode(NetworkRestrictionMode mode) async {
    _settings = _settings.copyWith(networkMode: mode);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setOnlyWifi(bool onlyWifi) async {
    _wifiAutoReenableTimer?.cancel();

    if (!onlyWifi) {
      // Sadece Wi-Fi kapatıldı (Mobil veri açıldı): 1 saat sonra otomatik olarak tekrar açılacak
      await SettingsManager.instance.saveWifiDisabledTimestamp(
          DateTime.now().millisecondsSinceEpoch);
      _wifiAutoReenableTimer = Timer(const Duration(hours: 1), () {
        setOnlyWifi(true);
      });
    } else {
      await SettingsManager.instance.clearWifiDisabledTimestamp();
    }

    final mode = onlyWifi
        ? NetworkRestrictionMode.anyWifi
        : NetworkRestrictionMode.allNetworks;
    await updateNetworkMode(mode);
  }

  Future<void> toggleAutoDownload(bool enabled) async {
    _settings = _settings.copyWith(autoDownloadOnPaste: enabled);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> togglePlaylistReverse(bool enabled) async {
    _settings = _settings.copyWith(playlistReverseOrder: enabled);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> addSavedPlaylist(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || _settings.savedPlaylists.contains(trimmed)) return;
    final updated = List<String>.from(_settings.savedPlaylists)..add(trimmed);
    _settings = _settings.copyWith(savedPlaylists: updated);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> removeSavedPlaylist(String url) async {
    final updated = List<String>.from(_settings.savedPlaylists)
      ..removeWhere((item) => item == url);
    _settings = _settings.copyWith(savedPlaylists: updated);
    await SettingsManager.instance.saveSettings(_settings);
    notifyListeners();
  }

  Future<bool> updateYtDlp() async {
    return await NativeBridge.instance.updateYtDlp();
  }
}
