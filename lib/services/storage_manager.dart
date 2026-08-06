import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/trashed_video_item.dart';
import '../models/video_item.dart';
import 'native_bridge.dart';

class StorageManager {
  static final StorageManager instance = StorageManager._internal();
  StorageManager._internal();

  static const String defaultHiddenPath =
      '/storage/emulated/0/Download/.offlineyoutube';

  String _currentDownloadPath = defaultHiddenPath;
  String get currentDownloadPath => _currentDownloadPath;
  String get trashPath => '$_currentDownloadPath/.trash';

  Future<void> initDirectory([String? customPath]) async {
    if (customPath != null && customPath.isNotEmpty) {
      _currentDownloadPath = customPath;
    }

    try {
      Directory dir = Directory(_currentDownloadPath);
      bool created = false;
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        created = await dir.exists();
      } catch (_) {
        created = false;
      }

      if (!created) {
        // Fallback to app external storage directory
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          _currentDownloadPath = '${extDir.path}/.offlineyoutube';
          dir = Directory(_currentDownloadPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          final appDocDir = await getApplicationDocumentsDirectory();
          _currentDownloadPath = '${appDocDir.path}/.offlineyoutube';
          dir = Directory(_currentDownloadPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // Ensure .nomedia file exists in main download dir
      try {
        final noMedia = File('${dir.path}/.nomedia');
        if (!await noMedia.exists()) {
          await noMedia.create();
        }
      } catch (_) {}

      // Ensure .trash directory and .nomedia exist
      try {
        final trashDir = Directory(trashPath);
        if (!await trashDir.exists()) {
          await trashDir.create(recursive: true);
        }
        final trashNoMedia = File('${trashDir.path}/.nomedia');
        if (!await trashNoMedia.exists()) {
          await trashNoMedia.create();
        }
      } catch (_) {}
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

  Future<void> saveVideoMetadata(
    String videoFilePath, {
    int? durationSeconds,
    String? uploader,
    String? title,
    String? url,
  }) async {
    try {
      final dotIndex = videoFilePath.lastIndexOf('.');
      if (dotIndex == -1) return;
      final baseWithoutExt = videoFilePath.substring(0, dotIndex);
      final metaFile = File('$baseWithoutExt.meta.json');
      final data = {
        'durationSeconds': durationSeconds,
        'uploader': uploader,
        'title': title,
        'url': url,
      };
      await metaFile.writeAsString(jsonEncode(data));
    } catch (_) {}
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

            final baseWithoutExt =
                entity.path.substring(0, entity.path.lastIndexOf('.'));
            String? thumbPath;
            for (final imgExt in ['jpg', 'jpeg', 'webp', 'png']) {
              final candidate = '$baseWithoutExt.$imgExt';
              if (File(candidate).existsSync()) {
                thumbPath = candidate;
                break;
              }
            }

            int? durationSeconds;
            String? uploader;
            final metaFile = File('$baseWithoutExt.meta.json');
            if (await metaFile.exists()) {
              try {
                final content = await metaFile.readAsString();
                final metaJson = jsonDecode(content) as Map<String, dynamic>;
                durationSeconds = metaJson['durationSeconds'] as int?;
                uploader = metaJson['uploader'] as String?;
              } catch (_) {}
            }

            videos.add(VideoItem(
              id: entity.path.hashCode.toString(),
              title: title,
              filePath: entity.path,
              fileSizeBytes: stat.size,
              durationSeconds: durationSeconds,
              uploader: uploader,
              downloadedAt: stat.modified,
              thumbnailPath: thumbPath,
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

  // --- GERİ DÖNÜŞÜM KUTUSU (TRASH) YÖNETİMİ ---

  File get _trashIndexFile => File('$trashPath/trash_index.json');

  Future<List<TrashedVideoItem>> loadTrashIndex() async {
    try {
      final file = _trashIndexFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((item) => TrashedVideoItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveTrashIndex(List<TrashedVideoItem> items) async {
    try {
      final file = _trashIndexFile;
      final jsonList = items.map((i) => i.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // Non-fatal
    }
  }

  /// Videoyu Geri Dönüşüm Kutusu (.trash) klasörüne taşır
  Future<bool> moveToTrash(VideoItem item) async {
    try {
      final trashDir = Directory(trashPath);
      if (!await trashDir.exists()) {
        await trashDir.create(recursive: true);
      }

      final srcFile = File(item.filePath);
      if (!await srcFile.exists()) return false;

      final fileName = item.filePath.split(Platform.pathSeparator).last;
      final destFilePath = '$trashPath/$fileName';

      await srcFile.rename(destFilePath);

      // Taşı: .meta.json
      final srcMeta = File('${item.filePath.substring(0, item.filePath.lastIndexOf('.'))}.meta.json');
      if (await srcMeta.exists()) {
        final destMeta = File('${destFilePath.substring(0, destFilePath.lastIndexOf('.'))}.meta.json');
        await srcMeta.rename(destMeta.path);
      }

      String? destThumbPath;
      if (item.thumbnailPath != null) {
        final srcThumb = File(item.thumbnailPath!);
        if (await srcThumb.exists()) {
          final thumbName =
              item.thumbnailPath!.split(Platform.pathSeparator).last;
          destThumbPath = '$trashPath/$thumbName';
          await srcThumb.rename(destThumbPath);
        }
      }

      final trashedVideo = VideoItem(
        id: item.id,
        title: item.title,
        filePath: destFilePath,
        fileSizeBytes: item.fileSizeBytes,
        durationSeconds: item.durationSeconds,
        uploader: item.uploader,
        downloadedAt: item.downloadedAt,
        thumbnailPath: destThumbPath,
      );

      final currentTrash = await loadTrashIndex();
      currentTrash.removeWhere((t) => t.video.id == item.id);
      currentTrash.insert(
        0,
        TrashedVideoItem(video: trashedVideo, deletedAt: DateTime.now()),
      );
      await _saveTrashIndex(currentTrash);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Videoyu Geri Dönüşüm Kutusundan ana indirme klasörüne geri yükler
  Future<bool> restoreFromTrash(TrashedVideoItem trashed) async {
    try {
      final srcFile = File(trashed.video.filePath);
      final fileName =
          trashed.video.filePath.split(Platform.pathSeparator).last;
      final destFilePath = '$_currentDownloadPath/$fileName';

      if (await srcFile.exists()) {
        await srcFile.rename(destFilePath);
      }

      // Taşı geri: .meta.json
      final srcMeta = File('${trashed.video.filePath.substring(0, trashed.video.filePath.lastIndexOf('.'))}.meta.json');
      if (await srcMeta.exists()) {
        final destMeta = File('${destFilePath.substring(0, destFilePath.lastIndexOf('.'))}.meta.json');
        await srcMeta.rename(destMeta.path);
      }

      if (trashed.video.thumbnailPath != null) {
        final srcThumb = File(trashed.video.thumbnailPath!);
        final thumbName =
            trashed.video.thumbnailPath!.split(Platform.pathSeparator).last;
        final destThumbPath = '$_currentDownloadPath/$thumbName';
        if (await srcThumb.exists()) {
          await srcThumb.rename(destThumbPath);
        }
      }

      final currentTrash = await loadTrashIndex();
      currentTrash.removeWhere((t) => t.video.id == trashed.video.id);
      await _saveTrashIndex(currentTrash);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 24 saati (86400 saniye) dolduran çöpleri diskten kalıcı olarak temizler
  Future<List<TrashedVideoItem>> purgeExpiredTrash() async {
    try {
      final currentTrash = await loadTrashIndex();
      final List<TrashedVideoItem> activeTrash = [];

      for (final item in currentTrash) {
        if (item.isExpired) {
          // Kalıcı sil
          try {
            final f = File(item.video.filePath);
            if (await f.exists()) await f.delete();
            final mf = File('${item.video.filePath.substring(0, item.video.filePath.lastIndexOf('.'))}.meta.json');
            if (await mf.exists()) await mf.delete();
            if (item.video.thumbnailPath != null) {
              final tf = File(item.video.thumbnailPath!);
              if (await tf.exists()) await tf.delete();
            }
          } catch (_) {}
        } else {
          // Dosya gerçekten mevcutsa aktif çöp listesinde tut
          if (File(item.video.filePath).existsSync()) {
            activeTrash.add(item);
          }
        }
      }

      await _saveTrashIndex(activeTrash);
      return activeTrash;
    } catch (e) {
      return [];
    }
  }

  /// Belirli bir videoyu Geri Dönüşüm Kutusundan kalıcı olarak siler
  Future<bool> permanentlyDelete(TrashedVideoItem trashed) async {
    try {
      final f = File(trashed.video.filePath);
      if (await f.exists()) await f.delete();
      final mf = File('${trashed.video.filePath.substring(0, trashed.video.filePath.lastIndexOf('.'))}.meta.json');
      if (await mf.exists()) await mf.delete();
      if (trashed.video.thumbnailPath != null) {
        final tf = File(trashed.video.thumbnailPath!);
        if (await tf.exists()) await tf.delete();
      }

      final currentTrash = await loadTrashIndex();
      currentTrash.removeWhere((t) => t.video.id == trashed.video.id);
      await _saveTrashIndex(currentTrash);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Geri Dönüşüm Kutusundaki tüm videoları kalıcı olarak siler
  Future<bool> emptyTrash() async {
    try {
      final currentTrash = await loadTrashIndex();
      for (final item in currentTrash) {
        try {
          final f = File(item.video.filePath);
          if (await f.exists()) await f.delete();
          final mf = File('${item.video.filePath.substring(0, item.video.filePath.lastIndexOf('.'))}.meta.json');
          if (await mf.exists()) await mf.delete();
          if (item.video.thumbnailPath != null) {
            final tf = File(item.video.thumbnailPath!);
            if (await tf.exists()) await tf.delete();
          }
        } catch (_) {}
      }
      await _saveTrashIndex([]);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Eski doğrudan silme metodu (geriye dönük uyumluluk)
  Future<bool> deleteVideo(VideoItem item) async {
    return await moveToTrash(item);
  }
}
