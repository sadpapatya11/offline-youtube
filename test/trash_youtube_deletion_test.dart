import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/trashed_video_item.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/services/storage_manager.dart';

/// Bu dosya, çöp kutusu ile YouTube oynatma listesi silme yolunun sözleşmesini korur.
///
/// Kök sorun (2026-08-25 denetimi, kritik bulgu):
/// Çöpe atma anında kullanıcının GERÇEK YouTube oynatma listesinden video siliniyordu.
/// Geri alma yolu yoktu (repoda playlistItems.insert hiç yok), onay dialogu da yoktu.
/// Aynı anda kalıcı silme yolu ise hiç çalışmıyordu, çünkü moveToTrash playlistUrl
/// alanını kopyalamadığı için enqueueDeletion her zaman erken dönüyordu.
///
/// Doğru sözleşme: YouTube silmesi YALNIZ kalıcı silme anında tetiklenir,
/// ve bunun çalışabilmesi için playlistUrl çöp kaydında korunmak ZORUNDADIR.
void main() {
  VideoItem ornekVideo({
    String? playlistUrl = 'https://www.youtube.com/playlist?list=PL123456789',
    String? sourceUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    String? uploadDate = '20260101',
  }) {
    return VideoItem(
      id: 'video-1',
      title: 'Örnek Video',
      filePath: '/indirilenler/ornek.mp4',
      fileSizeBytes: 1024,
      durationSeconds: 300,
      uploader: 'Kanal',
      downloadedAt: DateTime(2026, 8, 1),
      thumbnailPath: '/indirilenler/ornek.jpg',
      subtitlePath: '/indirilenler/ornek.vtt',
      sourceUrl: sourceUrl,
      playlistUrl: playlistUrl,
      uploadDate: uploadDate,
    );
  }

  group('Çöp kaydı YouTube silmesi için gereken alanları korur', () {
    test('copyForTrash playlistUrl alanını KORUR (kalıcı silme buna bağlı)', () {
      final v = ornekVideo();
      final t = v.copyForTrash(
        filePath: '/.trash/ornek.mp4',
        thumbnailPath: '/.trash/ornek.jpg',
      );

      expect(t.playlistUrl, 'https://www.youtube.com/playlist?list=PL123456789',
          reason: 'playlistUrl düşerse kalıcı silmede YouTube listesinden kaldırma sessizce çalışmaz');
      expect(t.uploadDate, '20260101');
      expect(t.youtubeId, 'dQw4w9WgXcQ',
          reason: 'youtubeId sourceUrl üzerinden türer, sourceUrl taşınmak zorunda');
    });

    test('copyForTrash yeni dosya yollarını uygular, kimliği ve üstverisini bozmaz', () {
      final v = ornekVideo();
      final t = v.copyForTrash(
        filePath: '/.trash/yeni.mp4',
        thumbnailPath: '/.trash/yeni.jpg',
      );

      expect(t.filePath, '/.trash/yeni.mp4');
      expect(t.thumbnailPath, '/.trash/yeni.jpg');
      expect(t.id, v.id);
      expect(t.title, v.title);
      expect(t.fileSizeBytes, v.fileSizeBytes);
      expect(t.durationSeconds, v.durationSeconds);
      expect(t.uploader, v.uploader);
      expect(t.downloadedAt, v.downloadedAt);
      expect(t.subtitlePath, v.subtitlePath);
      expect(t.sourceUrl, v.sourceUrl);
    });

    test('kaynağında playlistUrl yoksa çöp kaydında da null kalır, uydurulmaz', () {
      final t = ornekVideo(playlistUrl: null).copyForTrash(filePath: '/.trash/a.mp4');
      expect(t.playlistUrl, isNull);
      expect(t.thumbnailPath, isNull, reason: 'verilmeyen thumbnail yolu null kalmalı');
    });
  });

  group('Kalıcı silme ayrımı: yalnız süresi dolanlar YouTube kuyruğuna girer', () {
    TrashedVideoItem cop({required String id, required Duration yas}) {
      return TrashedVideoItem(
        video: VideoItem(
          id: id,
          title: id,
          filePath: '/.trash/$id.mp4',
          fileSizeBytes: 10,
          downloadedAt: DateTime(2026, 8, 1),
          sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          playlistUrl: 'https://www.youtube.com/playlist?list=PL1',
        ),
        deletedAt: DateTime.now().subtract(yas),
      );
    }

    test('expiredOnly yalnız 24 saati dolmuş kayıtları döndürür', () {
      final liste = [
        cop(id: 'taze', yas: const Duration(minutes: 5)),
        cop(id: 'dolmus', yas: const Duration(hours: 25)),
        cop(id: 'sinirda-taze', yas: const Duration(hours: 23, minutes: 59)),
        cop(id: 'yeni-dolmus', yas: const Duration(hours: 48)),
      ];

      final dolanlar = StorageManager.expiredOnly(liste).map((t) => t.video.id).toList();

      expect(dolanlar, ['dolmus', 'yeni-dolmus']);
      expect(dolanlar, isNot(contains('taze')),
          reason: 'süresi dolmamış çöp YouTube silme kuyruğuna ASLA girmemeli, kullanıcı geri alabilir');
      expect(dolanlar, isNot(contains('sinirda-taze')));
    });

    test('hiçbiri dolmamışsa boş liste döner (kuyruğa hiçbir şey gitmez)', () {
      final liste = [
        cop(id: 'a', yas: const Duration(hours: 1)),
        cop(id: 'b', yas: const Duration(hours: 12)),
      ];
      expect(StorageManager.expiredOnly(liste), isEmpty);
    });

    test('boş çöp listesi boş sonuç verir', () {
      expect(StorageManager.expiredOnly(const []), isEmpty);
    });
  });
}
