import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/video_item.dart';
import 'native_bridge.dart';

class StorageManager {
  static final StorageManager instance = StorageManager._internal();
  StorageManager._internal();

  static const String defaultHiddenPath =
      '/storage/emulated/0/Download/.offlineyoutube';

  String _currentDownloadPath = defaultHiddenPath;
  String get currentDownloadPath => _currentDownloadPath;

  Future<void> initDirectory([String? customPath]) async {
    if (customPath != null && customPath.isNotEmpty) {
      _currentDownloadPath = customPath;
    }

    try {
      Directory dir = Directory(_currentDownloadPath);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          // If permission is not yet granted or Android restricted, fallback to external files dir
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            _currentDownloadPath = '${extDir.path}/.offlineyoutube';
            dir = Directory(_currentDownloadPath);
            await dir.create(recursive: true);
          }
        }
      }

      // Ensure .nomedia file exists to hide from gallery
      final noMedia = File('${dir.path}/.nomedia');
      if (!await noMedia.exists()) {
        await noMedia.create();
      }
    } catch (e) {
      // Handled gracefully
    }
  }

  Future<int> getUsedStorageBytes() async {
    try {
      return await NativeBridge.instance.getFolderSize(_currentDownloadPath);
    } catch (e) {
      try {
        final dir = Directory(_currentDownloadPath);
        if (!await dir.exists()) return 0;
        var total = 0;
        await for (final file in dir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            total += await file.length();
          }
        }
        return total;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<List<VideoItem>> scanDownloadedVideos() async {
    final List<VideoItem> videos = [];
    try {
      final dir = Directory(_currentDownloadPath);
      if (!await dir.exists()) return videos;

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (['mp4', 'mkv', 'webm', 'ts', '3gp', 'm4a'].contains(ext)) {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            final stat = await entity.stat();
            final title = fileName.substring(0, fileName.lastIndexOf('.'));

            videos.add(VideoItem(
              id: entity.path.hashCode.toString(),
              title: title,
              filePath: entity.path,
              fileSizeBytes: stat.size,
              downloadedAt: stat.modified,
            ));
          }
        }
      }

      // Sort newest first
      videos.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    } catch (e) {
      // Ignored
    }
    return videos;
  }

  Future<bool> deleteVideo(VideoItem item) async {
    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }
}
