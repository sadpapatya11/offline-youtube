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
      await updateTaskConstraints(settings.networkMode == NetworkRestrictionMode.anyWifi);
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
        frequency: const Duration(hours: 24),
        constraints: Constraints(
          networkType: isWifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      if (kDebugMode) {
        print('BackgroundSyncManager: register periodic task failed: $e');
      }
    }
  }
}
