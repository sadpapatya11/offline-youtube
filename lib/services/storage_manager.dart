import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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

/// [StorageManager.measureUsedStorage] sonucu.
///
/// Ayrı bir tip olmasının nedeni: eski `getUsedStorageBytes` her hata yolunda 0
/// döndürüyordu ve 0 bayt, "klasör boş" ile "ölçemedim"i AYIRT ETMİYORDU. Depolama
/// izni geri alındığında veya indirme klasörü native tarafın izin verdiği taban
/// dizinin dışında kaldığında kota kapısı (`usedBytes >= maxBytes`) hiç kapanmıyor,
/// uygulama disk dolana kadar indirmeye devam ediyordu. [measured] false ise [bytes]
/// bir tahmin DEĞİLDİR, karar verirken kullanılmamalıdır.
class UsedStorageMeasurement {
  /// Ölçülen bayt. Yalnız [measured] true iken anlamlıdır.
  final int bytes;

  /// Ölçüm gerçekten yapılabildi mi.
  final bool measured;

  const UsedStorageMeasurement._(this.bytes, this.measured);

  const UsedStorageMeasurement.of(int bytes) : this._(bytes, true);

  const UsedStorageMeasurement.unknown() : this._(0, false);
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

      // FIX(veri kaybı): getExternalStorageDirectory() null dönerse (dış depolama
      // takılı değil, USB aktarım modu, çok kullanıcılı profil) _currentDownloadPath
      // defaultHiddenPath olarak kalıyordu. Döngü aynı klasörü "eski klasör" sayıp
      // her dosyayı kendi üzerine rename ediyor, sonra oldDir.delete(recursive: true)
      // ile TÜM kütüphaneyi (videolar, .meta.json, kapaklar, çöp indeksi) siliyordu.
      for (final oldPath in migratableOldPaths(oldPaths, _currentDownloadPath)) {
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
              // Alt klasör gerçekten boşaldıysa kaldır. Dolu kaldıysa delete()
              // hata verir ve taşınamayan dosyalar yerinde korunur.
              try {
                await entity.delete();
              } catch (_) {}
            }
          } catch (_) {}
        }

        // trash_index.json içindeki eski mutlak yolları güncelle
        try {
          final trashIndex = File('${newDir.path}/.trash/trash_index.json');
          if (await trashIndex.exists()) {
            final content = await trashIndex.readAsString();
            final updatedContent = content.replaceAll(oldPath, _currentDownloadPath);
            if (updatedContent != content) {
              await _writeJsonAtomic(trashIndex, updatedContent);
            }
          }
        } catch (_) {}

        // FIX(veri kaybı): Burada delete(recursive: true) vardı; rename'i patlayan
        // (ör. dosya sistemleri arası taşımada EXDEV) dosyalar da siliniyordu.
        // Artık yalnızca klasör gerçekten boşaldıysa silinir.
        try {
          await oldDir.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Kullanılan alanı ölçer ve ölçümün YAPILIP YAPILMADIĞINI da bildirir.
  ///
  /// FIX(kota): Eski sürüm yalnız `int` döndürüyor, her hata yolunda 0 veriyordu.
  /// Native ölçüm de sessizdir: NativeBridge.getFolderSize her istisnayı yutup 0
  /// döndürür ve MainActivity.getFolderSize izin verilen taban dizinin dışındaki
  /// yolu reddedip 0L verir. Bu yüzden native 0 doğrulanmadan kabul edilemez,
  /// Dart tarafında yeniden sayılır.
  Future<UsedStorageMeasurement> measureUsedStorage() async {
    int nativeBytes = 0;
    try {
      nativeBytes = await NativeBridge.instance.getFolderSize(_currentDownloadPath);
    } catch (_) {
      nativeBytes = 0;
    }
    if (nativeBytes > 0) return UsedStorageMeasurement.of(nativeBytes);

    try {
      final dir = Directory(_currentDownloadPath);
      if (!await dir.exists()) {
        // initDirectory bu klasörü oluşturur; yokluğu depolamanın erişilemez
        // olduğunu gösterir, "0 bayt kullanılıyor" demek DEĞİLDİR.
        return const UsedStorageMeasurement.unknown();
      }
      var total = 0;
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          try {
            total += await file.length();
          } catch (_) {
            // İndirme sürerken yt-dlp .part dosyasını yeniden adlandırabilir;
            // tek dosyanın okunamaması tüm ölçümü geçersiz kılmamalı, aksi hâlde
            // kota kapısı indirme sırasında haksız yere kapanır.
          }
        }
      }
      return UsedStorageMeasurement.of(total);
    } catch (_) {
      return const UsedStorageMeasurement.unknown();
    }
  }

  /// Yalnız GÖRÜNTÜLEME içindir: ölçülemeyen durumu 0 gösterir.
  /// Kota kararı verirken [measureUsedStorage] artı [isWithinStorageQuota] kullanın.
  Future<int> getUsedStorageBytes() async => (await measureUsedStorage()).bytes;

  /// Kota kapısı kararı.
  ///
  /// Ölçüm yapılamadıysa indirmeye İZİN VERİLMEZ: bilinmeyeni 0 sayan eski davranış,
  /// depolama izni geri alındığında veya kart çıkarıldığında kullanıcının kotasını
  /// tamamen devre dışı bırakıyor, disk dolana kadar indirme sürüyordu.
  static bool isWithinStorageQuota(UsedStorageMeasurement used, int maxBytes) =>
      used.measured && used.bytes < maxBytes;

  /// İki yolun aynı klasörü gösterip göstermediğini kanonik biçimde karşılaştırır.
  static bool isSameDirectory(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return p.canonicalize(a) == p.canonicalize(b);
  }

  /// Göç edilecek eski klasörleri süzer: hedefin kendisi listeden DÜŞÜRÜLÜR.
  ///
  /// Ayrı ve saf bir metot olmasının nedeni: kaynak ile hedef aynı klasöre denk
  /// geldiğinde göç döngüsü sonunda klasörü siliyor, yani kullanıcının bütün
  /// kütüphanesini yok ediyordu. Bu karar test edilebilir olmak zorundadır.
  static List<String> migratableOldPaths(
    List<String> candidates,
    String currentPath,
  ) =>
      candidates.where((c) => !isSameDirectory(c, currentPath)).toList();

  /// [filePath] dosya adını [directoryPath] altına taşır (içerik kopyalanmaz).
  ///
  /// Çöp kayıtlarındaki MUTLAK yollar indirme klasörü göç edince geçersizleşir;
  /// kaydı hemen düşürmek yerine dosya yeni klasörde aranır.
  static String rebaseToDirectory(String filePath, String directoryPath) =>
      p.join(directoryPath, p.basename(filePath));

  /// JSON'u geçici dosyaya yazıp hedefin üzerine rename eder.
  ///
  /// FIX(atomiklik): writeAsString hedefi ÖNCE sıfırlar. Android süreci tam bu anda
  /// öldürürse (düşük bellek, pil optimizasyonu, kullanıcı uygulamayı kapatır)
  /// diskte yarım JSON kalıyor ve çözümlenemediği için TÜM indeks veya üstveri
  /// kayboluyordu. Aynı klasördeki rename atomiktir: hedef ya eski ya yeni içeriğe
  /// sahiptir, asla yarım kalmaz.
  static Future<void> _writeJsonAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
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
      // Yarım yazılan .meta.json çözümlenemez; video kütüphanede gerçek başlık,
      // süre, sourceUrl ve playlistUrl olmadan görünür (kimlik dosya adına düşer).
      await _writeJsonAtomic(metaFile, jsonEncode(data));
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

  /// Çöp indeksi ham JSON'unu kayıtlara çevirir; ÇÖZÜMLENEMEYEN TEK kaydı atlar,
  /// kalanları korur. Belgenin tamamı bozuksa istisna fırlatır (çağıran karantinaya alır).
  ///
  /// Saf ve statik olmasının nedeni: eski kod `.map(...).toList()` kullanıyordu ve
  /// tek bir bozuk kayıt (elle düzenlenmiş JSON, model alanı değişikliği) istisna
  /// fırlatıp TÜM indeksi boşaltıyordu. Boşalan indeks ilk yazmada diske geçince
  /// çöpteki bütün videolar kayıtsız yetim dosyaya dönüşüyor: arayüzde görünmüyor,
  /// geri alınamıyor, silinemiyor ama diskte yer kaplamaya devam ediyordu.
  static List<TrashedVideoItem> parseTrashIndex(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return [];
    final decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      throw const FormatException('trash_index.json bir liste değil');
    }
    final items = <TrashedVideoItem>[];
    for (final raw in decoded) {
      try {
        items.add(TrashedVideoItem.fromJson(raw as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Bozuk çöp kaydı atlandı: $e');
      }
    }
    return items;
  }

  /// Bozuk çöp indeksi karantinaya alındıysa yedeğin yolu.
  ///
  /// Arayüz kullanıcıya "çöp kayıtların bozuktu, yedeği şurada" diyebilsin diye
  /// tutulur; sessizce boş indeksle devam etmek kaybı görünmez kılıyordu.
  String? get lastQuarantinedTrashIndexPath => _lastQuarantinedTrashIndexPath;
  String? _lastQuarantinedTrashIndexPath;

  Future<List<TrashedVideoItem>> loadTrashIndex() async {
    final file = _trashIndexFile;
    String content;
    try {
      if (!await file.exists()) return [];
      content = await file.readAsString();
    } catch (e, s) {
      debugPrint('ERROR in loadTrashIndex (okuma): $e\n$s');
      return [];
    }

    try {
      return parseTrashIndex(content);
    } catch (e, s) {
      debugPrint('ERROR in loadTrashIndex (çözümleme): $e\n$s');
      // Karantina: bozuk dosyayı yerinde bırakmak yerine yeniden adlandır. Aksi
      // hâlde bir sonraki _saveTrashIndex tek kopyanın üzerine yazıyor ve
      // kullanıcının çöpteki videolarının kaydı geri dönülmez biçimde yok oluyordu.
      try {
        final backupPath =
            '$trashPath/trash_index.corrupt-${DateTime.now().millisecondsSinceEpoch}.json';
        await file.rename(backupPath);
        _lastQuarantinedTrashIndexPath = backupPath;
      } catch (e2, s2) {
        debugPrint('ERROR in loadTrashIndex (karantina): $e2\n$s2');
      }
      return [];
    }
  }

  /// Çöp indeksini diske yazar ve BAŞARIYI DÖNDÜRÜR.
  ///
  /// bool dönmesinin nedeni: moveToTrash yazma sonucunu hiç sorgulamadan `true`
  /// diyordu. İndeks yazılamadığında video .trash içine taşınmış ama hiçbir kayıt
  /// oluşmamış oluyordu, yani dosya hem kütüphaneden hem çöpten kayboluyordu.
  ///
  /// Sonuç BİLEREK yalnız moveToTrash'te sorgulanır: diğer çağrılarda yıkıcı iş
  /// (silme, geri taşıma) zaten tamamlanmıştır, false dönmek çağıranın YouTube
  /// oynatma listesi temizliğini gerçekleşmiş bir silme için iptal etmesine yol
  /// açardı. Bayat kalan kayıtlar purgeExpiredTrash'te kendiliğinden düşer.
  Future<bool> _saveTrashIndex(List<TrashedVideoItem> items) async {
    try {
      final jsonList = items.map((i) => i.toJson()).toList();
      await _writeJsonAtomic(_trashIndexFile, jsonEncode(jsonList));
      return true;
    } catch (e, s) {
      debugPrint('ERROR in _saveTrashIndex: $e\n$s');
      return false;
    }
  }

  /// [moveToTrash] yarıda kaldığında .trash'e taşınmış yan dosyaları geri alır.
  ///
  /// Neden: video rename'i patladığında (disk dolu, dosya sistemi hatası) meta ve
  /// kapak .trash içinde kalıyordu. Video kütüphanede duruyor ama .meta.json
  /// bulunamadığı için gerçek başlık, süre, sourceUrl ve playlistUrl kalıcı olarak
  /// kayboluyor, video sonraki taramada dosya adıyla ve üstverisiz görünüyordu.
  Future<void> _rollbackSidecars({
    required String originalFilePath,
    required String trashFilePath,
    required bool movedMeta,
    String? originalThumbPath,
    String? trashThumbPath,
  }) async {
    if (movedMeta) {
      try {
        final srcMeta = File(
            '${originalFilePath.substring(0, originalFilePath.lastIndexOf('.'))}.meta.json');
        if (!await srcMeta.exists()) {
          final destMeta = File(
              '${trashFilePath.substring(0, trashFilePath.lastIndexOf('.'))}.meta.json');
          if (await destMeta.exists()) {
            await destMeta.rename(srcMeta.path);
          }
        }
      } catch (e, s) {
        debugPrint('ERROR in _rollbackSidecars (meta): $e\n$s');
      }
    }

    if (originalThumbPath != null && trashThumbPath != null) {
      try {
        final srcThumb = File(originalThumbPath);
        if (!await srcThumb.exists()) {
          final destThumb = File(trashThumbPath);
          if (await destThumb.exists()) {
            await destThumb.rename(srcThumb.path);
          }
        }
      } catch (e, s) {
        debugPrint('ERROR in _rollbackSidecars (kapak): $e\n$s');
      }
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
        await _rollbackSidecars(
          originalFilePath: item.filePath,
          trashFilePath: destFilePath,
          movedMeta: movedMeta,
        );
        return false;
      }

      // FIX(atomiklik): Video rename'i korumasızdı; patladığında meta ve kapak
      // .trash içinde kalıyor, video kütüphanede üstverisiz sürüyordu.
      try {
        await srcFile.rename(destFilePath);
      } catch (e, s) {
        debugPrint('ERROR in moveToTrash (video rename): $e\n$s');
        await _rollbackSidecars(
          originalFilePath: item.filePath,
          trashFilePath: destFilePath,
          movedMeta: movedMeta,
          originalThumbPath: item.thumbnailPath,
          trashThumbPath: destThumbPath,
        );
        return false;
      }

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
      if (!await _saveTrashIndex(currentTrash)) {
        // FIX(veri kaybı): İndeks yazılamazsa kayıt hiç oluşmaz. Dosya .trash
        // içinde bırakılırsa kütüphanede de çöpte de görünmez, kullanıcı için
        // kalıcı kayıptır. Her şeyi eski yerine taşı ve başarısızlığı bildir.
        try {
          final movedVideo = File(destFilePath);
          if (await movedVideo.exists()) {
            await movedVideo.rename(item.filePath);
          }
        } catch (e, s) {
          debugPrint('ERROR in moveToTrash (video geri alma): $e\n$s');
        }
        await _rollbackSidecars(
          originalFilePath: item.filePath,
          trashFilePath: destFilePath,
          movedMeta: movedMeta,
          originalThumbPath: item.thumbnailPath,
          trashThumbPath: destThumbPath,
        );
        return false;
      }

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

      // FIX(veri kaybı): Dosya yoksa geri yükleme YAPILMAMIŞTIR. Eski kod kaydı
      // yine de indeksten düşürüp başarı bildiriyordu; video hem çöpten hem
      // kütüphaneden kayboluyor, kullanıcı hatayı hiç görmüyordu.
      if (!await srcFile.exists()) return false;
      await srcFile.rename(destFilePath);

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

      for (final raw in currentTrash) {
        // Yol tazeleme ÖNCE yapılır: indirme klasörü göç ettiğinde (veya yedek
        // yola düşüldüğünde) indeksteki mutlak yollar bir tur boyunca geçersizdir.
        // Tazelenmezse kayıt sessizce düşürülüyor, dosya .trash içinde kayıtsız
        // kalıyordu: arayüzde görünmez, geri alınamaz, silinemez ama kotaya sayılır.
        final healed = await _healTrashRecord(raw);
        final item = healed ?? raw;
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
        } else if (healed != null) {
          activeTrash.add(healed);
        }
        // healed == null ve süresi dolmamış: dosya diskte hiçbir yerde yok,
        // kaydın geri yüklenecek bir karşılığı kalmadığı için düşürülür.
      }

      await _saveTrashIndex(activeTrash);
      return TrashPurgeResult(purged: purged, remaining: activeTrash);
    } catch (e, s) {
      debugPrint('ERROR in purgeExpiredTrash: $e\n$s');
      return const TrashPurgeResult(purged: [], remaining: []);
    }
  }

  /// Çöp kaydının dosya yolunu doğrular, gerekiyorsa güncel [trashPath] altına taşır.
  ///
  /// null dönmesi "dosya diskte gerçekten yok" demektir; kaydın kaybolan yolu ile
  /// kaybolan dosyası bu şekilde birbirinden ayrılır.
  Future<TrashedVideoItem?> _healTrashRecord(TrashedVideoItem item) async {
    try {
      if (await File(item.video.filePath).exists()) return item;

      final rebased = rebaseToDirectory(item.video.filePath, trashPath);
      if (rebased == item.video.filePath) return null;
      if (!await File(rebased).exists()) return null;

      final oldThumb = item.video.thumbnailPath;
      String? newThumb;
      if (oldThumb != null) {
        final rebasedThumb = rebaseToDirectory(oldThumb, trashPath);
        if (await File(rebasedThumb).exists()) newThumb = rebasedThumb;
      }

      return TrashedVideoItem(
        video: item.video.copyForTrash(filePath: rebased, thumbnailPath: newThumb),
        deletedAt: item.deletedAt,
      );
    } catch (e, s) {
      debugPrint('ERROR in _healTrashRecord: $e\n$s');
      return null;
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
