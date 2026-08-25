import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/trashed_video_item.dart';
import '../models/video_item.dart';
import 'native_bridge.dart';
import 'playback_manager.dart';

/// [StorageManager.purgeExpiredTrash] sonucu.
///
/// İki listeyi AYRI tutmak zorunludur: [purged] gerçekten kalıcı olarak silinenler,
/// [remaining] ise çöpte duran ve kullanıcının hâlâ geri alabileceği kayıtlar.
/// Tek liste döndürmek, çağıranın yanlış kümeyi YouTube silme kuyruğuna vermesine
/// yol açıyordu (2026-08-25 denetimi).
class TrashPurgeResult {
  final List<TrashedVideoItem> purged;
  final List<TrashedVideoItem> remaining;

  const TrashPurgeResult({required this.purged, required this.remaining});
}

class StorageManager {
  static final StorageManager instance = StorageManager._internal();
  StorageManager._internal();

  static const String defaultHiddenPath =
      '/storage/emulated/0/Download/.offlineyoutube';

  String _currentDownloadPath = defaultHiddenPath;
  String get currentDownloadPath => _currentDownloadPath;
  String get trashPath => '$_currentDownloadPath/.trash';

  Future<void> initDirectory([String? customPath]) async {
    // Eski gizli klasör yolu sorunlara yol açtığı için, kullanıcı ayarlarında
    // kayıtlı olsa bile bunu yoksay ve güvenli app-private klasöre zorla.
    if (customPath != null && customPath.isNotEmpty && customPath != defaultHiddenPath) {
      _currentDownloadPath = customPath;
    } else {
      // FIX(storage): Download/.offlineyoutube MediaProvider tarafından
      // yönetilir; silinen dosyalar .trash'e taşınır ve isimleri FUSE'da
      // kilitli kalır — yt-dlp'nin .part -> final rename'i "Operation not
      // permitted"/"File exists" ile patlar. App-private klasörde
      // MediaProvider yok: rename serbest ve içerik galeriye görünmez.
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          _currentDownloadPath = '${extDir.path}/.movies';
        }
      } catch (_) {
        // Fallback: defaultHiddenPath kullanılmaya devam edilir
      }
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
          _currentDownloadPath = '${extDir.path}/.movies';
          dir = Directory(_currentDownloadPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          final appDocDir = await getApplicationDocumentsDirectory();
          _currentDownloadPath = '${appDocDir.path}/.movies';
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
      
      // Eski klasörden göç et
      await _migrateOldDownloads();
    } catch (e) {
      // Handled gracefully
    }
  }

  Future<void> _migrateOldDownloads() async {
    try {
      final newDir = Directory(_currentDownloadPath);
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // 1. Eski klasör yolları listesi
      final List<String> oldPaths = [defaultHiddenPath];
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          oldPaths.add('${extDir.path}/offlineyoutube');
        }
      } catch (_) {}

      for (final oldPath in oldPaths) {
        final oldDir = Directory(oldPath);
        if (!await oldDir.exists()) continue;

        // Tüm dosya ve klasörleri (recursive olarak) taşı
        await for (final entity in oldDir.list(recursive: false)) {
          final newPath = '${newDir.path}/${entity.path.split(Platform.pathSeparator).last}';
          try {
            if (entity is File) {
              await entity.rename(newPath);
            } else if (entity is Directory) {
              // .trash gibi klasörler
              final newSubDir = Directory(newPath);
              if (!await newSubDir.exists()) {
                await newSubDir.create(recursive: true);
              }
              await for (final subEntity in entity.list(recursive: false)) {
                if (subEntity is File) {
                  final newSubPath = '${newSubDir.path}/${subEntity.path.split(Platform.pathSeparator).last}';
                  await subEntity.rename(newSubPath);
                }
              }
            }
          } catch (_) {}
        }

        // trash_index.json içindeki eski mutlak yolları güncelle
        try {
          final trashIndex = File('${newDir.path}/.trash/trash_index.json');
          if (await trashIndex.exists()) {
            final content = await trashIndex.readAsString();
            final updatedContent = content.replaceAll(oldPath, _currentDownloadPath);
            await trashIndex.writeAsString(updatedContent);
          }
        } catch (_) {}

        // İşlem bitince eski boş klasörü silmeye çalış
        try {
          await oldDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
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
    String? uploadDate,
    String? title,
    String? url,
    String? playlistUrl,
  }) async {
    try {
      final dotIndex = videoFilePath.lastIndexOf('.');
      if (dotIndex == -1) return;
      final baseWithoutExt = videoFilePath.substring(0, dotIndex);
      final metaFile = File('$baseWithoutExt.meta.json');
      final data = {
        'durationSeconds': durationSeconds,
        'uploader': uploader,
        'uploadDate': uploadDate,
        'title': title,
        'url': url,
        'playlistUrl': playlistUrl,
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
            // FIX(fragments): Başarısız ffmpeg birleştirmelerinin bıraktığı
            // "Title [id].f137.mp4" / ".f140.m4a" parça dosyalarını kütüphanede
            // sahte video olarak gösterme.
            if (RegExp(r'\.f\d+\.(mp4|m4a)$').hasMatch(fileName)) continue;
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

            // Türkçe Altyazı dosyası arama (.tr.vtt, .tr.srt, .vtt, .srt)
            String? subtitlePath;
            for (final subExt in [
              'tr.vtt',
              'tr-orig.vtt',
              'tr-TR.vtt',
              'tr.srt',
              'vtt',
              'srt'
            ]) {
              final subCandidate = '$baseWithoutExt.$subExt';
              if (File(subCandidate).existsSync()) {
                subtitlePath = subCandidate;
                break;
              }
            }

            int exactSize = 0;
            try {
              exactSize = await entity.length();
            } catch (_) {
              exactSize = stat.size;
            }

            int? durationSeconds;
            String? uploader;
            String? uploadDate;
            String? sourceUrl;
            String? playlistUrl;
            String displayTitle = title;
            final metaFile = File('$baseWithoutExt.meta.json');
            if (await metaFile.exists()) {
              try {
                final content = await metaFile.readAsString();
                final metaJson = jsonDecode(content) as Map<String, dynamic>;
                durationSeconds = metaJson['durationSeconds'] as int?;
                uploader = metaJson['uploader'] as String?;
                uploadDate = metaJson['uploadDate'] as String?;
                sourceUrl = metaJson['url'] as String?;
                playlistUrl = metaJson['playlistUrl'] as String?;
                if (metaJson['title'] != null &&
                    (metaJson['title'] as String).trim().isNotEmpty) {
                  displayTitle = (metaJson['title'] as String).trim();
                }
              } catch (_) {}
            }

            final vid = VideoItem.extractVideoId(sourceUrl);
            final stableId = (vid != null && vid.isNotEmpty) ? vid : fileName;

            videos.add(VideoItem(
              id: stableId,
              title: displayTitle,
              filePath: entity.path,
              fileSizeBytes: exactSize,
              durationSeconds: durationSeconds,
              uploader: uploader,
              uploadDate: uploadDate,
              downloadedAt: stat.modified,
              thumbnailPath: thumbPath,
              subtitlePath: subtitlePath,
              sourceUrl: sourceUrl,
              playlistUrl: playlistUrl,
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
    } catch (e, s) {
      debugPrint('ERROR in loadTrashIndex: $e\n$s');
      return [];
    }
  }

  Future<void> _saveTrashIndex(List<TrashedVideoItem> items) async {
    try {
      final file = _trashIndexFile;
      final jsonList = items.map((i) => i.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e, s) {
      debugPrint('ERROR in _saveTrashIndex: $e\n$s');
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

      // FIX(atomicity): Önce tüm yan dosyaları (meta, thumbnail) taşımaya
      // çalış; ana video dosyasını en son taşı. Bir adım başarısız olursa
      // zaten taşınanları geri alarak tutarlılığı koru — önceden video
      // taşındıktan sonra meta taşıma hatası, dosyanın çöp listesinde hiç
      // görünmemesine yol açıyordu.
      var movedMeta = false;
      try {
        // Taşı: .meta.json
        final srcMeta = File('${item.filePath.substring(0, item.filePath.lastIndexOf('.'))}.meta.json');
        if (await srcMeta.exists()) {
          final destMeta = File('${destFilePath.substring(0, destFilePath.lastIndexOf('.'))}.meta.json');
          await srcMeta.rename(destMeta.path);
          movedMeta = true;
        }
      } catch (_) {
        // meta taşıma başarısız -> işlem başarısız say, video yerinde kalsın
        return false;
      }

      String? destThumbPath;
      try {
        if (item.thumbnailPath != null) {
          final srcThumb = File(item.thumbnailPath!);
          if (await srcThumb.exists()) {
            final thumbName =
                item.thumbnailPath!.split(Platform.pathSeparator).last;
            destThumbPath = '$trashPath/$thumbName';
            await srcThumb.rename(destThumbPath);
          }
        }
      } catch (_) {
        // thumbnail taşıma başarısız -> meta'yı geri al ve başarısız say
        if (movedMeta) {
          try {
            final srcMeta = File('${item.filePath.substring(0, item.filePath.lastIndexOf('.'))}.meta.json');
            if (!await srcMeta.exists()) {
              final destMeta = File('${destFilePath.substring(0, destFilePath.lastIndexOf('.'))}.meta.json');
              await destMeta.rename(srcMeta.path);
            }
          } catch (_) {}
        }
        return false;
      }

      await srcFile.rename(destFilePath);

      // playlistUrl ve uploadDate dahil TÜM üstveri korunur; kalıcı silme anında
      // YouTube oynatma listesinden kaldırma bu alanlara bağlı (bkz. copyForTrash).
      final trashedVideo = item.copyForTrash(
        filePath: destFilePath,
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
    } catch (e, s) {
      // FIX(atomicity): Kritik adımlar yukarıda ayrı try bloklarıyla
      // korunduğundan buraya yalnızca istisnai durumlarda düşülür.
      debugPrint('ERROR in moveToTrash: $e\n$s');
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
  Future<TrashPurgeResult> purgeExpiredTrash() async {
    try {
      final currentTrash = await loadTrashIndex();
      final List<TrashedVideoItem> activeTrash = [];
      final List<TrashedVideoItem> purged = [];

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
            PlaybackManager.instance.clearPosition(item.video.id);
          } catch (_) {}
          purged.add(item);
        } else {
          // Dosya gerçekten mevcutsa aktif çöp listesinde tut
          if (File(item.video.filePath).existsSync()) {
            activeTrash.add(item);
          }
        }
      }

      await _saveTrashIndex(activeTrash);
      return TrashPurgeResult(purged: purged, remaining: activeTrash);
    } catch (e, s) {
      debugPrint('ERROR in purgeExpiredTrash: $e\n$s');
      return const TrashPurgeResult(purged: [], remaining: []);
    }
  }

  /// Süresi dolmuş çöp kayıtlarını ayırır.
  ///
  /// Ayrı ve saf bir metot olmasının nedeni: "hangi videolar kullanıcının YouTube
  /// oynatma listesinden kaldırılacak" kararı buradan çıkar ve test edilebilir olmak
  /// zorundadır. Süresi dolmamış bir kaydın bu listeye sızması, kullanıcının hâlâ
  /// geri alabileceği bir videoyu YouTube hesabından geri alınamaz biçimde siler.
  static List<TrashedVideoItem> expiredOnly(List<TrashedVideoItem> items) =>
      items.where((t) => t.isExpired).toList();

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
      PlaybackManager.instance.clearPosition(trashed.video.id);

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
          PlaybackManager.instance.clearPosition(item.video.id);
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
