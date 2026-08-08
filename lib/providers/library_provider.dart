import 'package:flutter/foundation.dart';
import '../models/trashed_video_item.dart';
import '../models/video_item.dart';
import '../services/storage_manager.dart';

class LibraryProvider extends ChangeNotifier {
  List<VideoItem> _videos = [];
  List<TrashedVideoItem> _trashedVideos = [];
  int _totalUsedBytes = 0;
  bool _isLoading = false;

  List<VideoItem> get videos => _videos;
  List<TrashedVideoItem> get trashedVideos => _trashedVideos;
  int get totalUsedBytes => _totalUsedBytes;
  bool get isLoading => _isLoading;
  int get trashCount => _trashedVideos.length;

  LibraryProvider() {
    refresh();
    _bootstrap();
  }

  // FIX(startup-race): İlk tarama, indirme klasörü oluşturulmadan önce çalışıp
  // boş liste döndürebiliyordu (SettingsProvider._init ile yarış). Klasör
  // hazır olunca kütüphaneyi bir kez daha tara.
  Future<void> _bootstrap() async {
    try {
      await StorageManager.instance.initDirectory();
      await refresh();
    } catch (_) {
      // Init hataları sessizce geçilir; kullanıcı elle yenileyebilir.
    }
  }

  Future<void> refresh() async {
    if (_videos.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }

    // 24 saati geçmiş çöpleri otomatik temizle
    _trashedVideos = await StorageManager.instance.purgeExpiredTrash();
    _videos = await StorageManager.instance.scanDownloadedVideos();
    _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
    _isLoading = false;
    notifyListeners();
  }

  /// Videoyu Geri Dönüşüm Kutusuna taşır (24 saat sonra otomatik silinir)
  Future<bool> deleteVideo(VideoItem item) async {
    final success = await StorageManager.instance.moveToTrash(item);
    if (success) {
      _videos.removeWhere((v) => v.id == item.id);
      _trashedVideos = await StorageManager.instance.loadTrashIndex();
      _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
      notifyListeners();
    }
    return success;
  }

  /// ID ile videoyu Geri Dönüşüm Kutusuna taşır
  Future<bool> deleteVideoById(String videoId) async {
    final match = _videos.where((v) => v.id == videoId).firstOrNull;
    if (match != null) {
      return await deleteVideo(match);
    }
    return false;
  }

  /// Birden fazla videoyu topluca Geri Dönüşüm Kutusuna taşır
  Future<int> bulkMoveToTrash(List<String> videoIds) async {
    int deletedCount = 0;
    for (final id in videoIds) {
      final match = _videos.where((v) => v.id == id).firstOrNull;
      if (match != null) {
        final ok = await StorageManager.instance.moveToTrash(match);
        if (ok) {
          _videos.removeWhere((v) => v.id == id);
          deletedCount++;
        }
      }
    }
    if (deletedCount > 0) {
      _trashedVideos = await StorageManager.instance.loadTrashIndex();
      _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
      notifyListeners();
    }
    return deletedCount;
  }

  /// Videoyu Geri Dönüşüm Kutusundan geri yükler
  Future<bool> restoreVideo(TrashedVideoItem trashed) async {
    final success = await StorageManager.instance.restoreFromTrash(trashed);
    if (success) {
      await refresh();
    }
    return success;
  }

  /// Belirli bir çöpü hemen kalıcı olarak siler
  Future<bool> deletePermanently(TrashedVideoItem trashed) async {
    final success = await StorageManager.instance.permanentlyDelete(trashed);
    if (success) {
      _trashedVideos.removeWhere((t) => t.video.id == trashed.video.id);
      _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
      notifyListeners();
    }
    return success;
  }

  /// Geri Dönüşüm Kutusundaki tüm videoları kalıcı olarak siler
  Future<bool> emptyTrash() async {
    final success = await StorageManager.instance.emptyTrash();
    if (success) {
      _trashedVideos.clear();
      _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
      notifyListeners();
    }
    return success;
  }

  String get formattedTotalUsed {
    if (_totalUsedBytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = _totalUsedBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  int get totalDurationSeconds =>
      _videos.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));

  String get formattedTotalDuration {
    final totalSec = totalDurationSeconds;
    if (totalSec <= 0) return '0 dk';
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
    }
    return '$minutes dk';
  }
}
