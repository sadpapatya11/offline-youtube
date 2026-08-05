import 'package:flutter/foundation.dart';
import '../models/video_item.dart';
import '../services/storage_manager.dart';

class LibraryProvider extends ChangeNotifier {
  List<VideoItem> _videos = [];
  int _totalUsedBytes = 0;
  bool _isLoading = false;

  List<VideoItem> get videos => _videos;
  int get totalUsedBytes => _totalUsedBytes;
  bool get isLoading => _isLoading;

  LibraryProvider() {
    refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    _videos = await StorageManager.instance.scanDownloadedVideos();
    _totalUsedBytes = await StorageManager.instance.getUsedStorageBytes();
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> deleteVideo(VideoItem item) async {
    final success = await StorageManager.instance.deleteVideo(item);
    if (success) {
      _videos.removeWhere((v) => v.id == item.id);
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
}
