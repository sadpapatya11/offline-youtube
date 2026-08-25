import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../services/settings_manager.dart';
import '../models/app_settings.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (kDebugMode) {
        print('BackgroundSyncManager: Task started ($task)');
      }
      
      final downloadProvider = DownloadProvider();
      final libraryProvider = LibraryProvider();
      final settings = await SettingsManager.instance.loadSettings();
      
      await downloadProvider.syncSavedPlaylists(
        settings: settings,
        libraryProvider: libraryProvider,
      );
      
      if (kDebugMode) {
        print('BackgroundSyncManager: Task completed successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('BackgroundSyncManager: Task failed with error: $e');
      }
      return false;
    }
  });
}

class BackgroundSyncManager {
  static const String _taskName = "playlistSyncTask";
  static const String _taskUniqueName = "offline_youtube_playlist_sync";

  static Future<void> initialize() async {
    try {
      Workmanager().initialize(
        callbackDispatcher,
      );
      
      final settings = await SettingsManager.instance.loadSettings();
      await syncWithSettings(settings);
    } catch (e) {
      if (kDebugMode) {
        print('BackgroundSyncManager: Initialization failed: $e');
      }
    }
  }

  static Future<void> updateTaskConstraints(bool isWifiOnly) async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskUniqueName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: isWifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresStorageNotLow: true,
        ),
        // update, keep DEĞİL: keep ile mevcut bir iş kayıtlıysa yeni kısıtlar hiç
        // uygulanmıyordu. Kullanıcı "Sadece Wi-Fi"yi açsa bile eski connected kısıtı
        // yürürlükte kalıyor ve senkron mobil veriden çalışmaya devam ediyordu.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      if (kDebugMode) {
        print('BackgroundSyncManager: register periodic task failed: $e');
      }
    }
  }

  /// Arka plan eşitlemesini tamamen durdurur.
  ///
  /// Kayıtlı oynatma listesi kalmadığında iş kayıtlı bırakılırsa, cihaz uygulama hiç
  /// açılmadan her 15 dakikada bir FlutterEngine ayağa kaldırıp hiçbir işe yaramayan
  /// bir tur atar. Kullanıcının pil raporunda görünen tüketimin karşılığı yoktur.
  static Future<void> cancelSync() async {
    try {
      await Workmanager().cancelByUniqueName(_taskUniqueName);
    } catch (e) {
      if (kDebugMode) {
        print('BackgroundSyncManager: cancel failed: $e');
      }
    }
  }

  /// Eşitleme işini yalnız gerçekten yapılacak iş varken kayıtlı tutar.
  static Future<void> syncWithSettings(AppSettings settings) async {
    if (settings.savedPlaylists.isEmpty) {
      await cancelSync();
      return;
    }
    await updateTaskConstraints(settings.networkMode == NetworkRestrictionMode.anyWifi);
  }
}
