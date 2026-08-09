import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/playlist_entry.dart';
import 'package:offlineyoutube/providers/download_provider.dart';

/// Oynatma listesi seçim akışının sözleşmesini koruyan testler.
void main() {
  group('PlaylistEntry — süre "bilinmiyor" ile "sıfır" karışmaz', () {
    test('süre gelmezse hasDuration false olur', () {
      const entry = PlaylistEntry(url: 'u', title: 't');
      expect(entry.durationSeconds, 0);
      expect(entry.hasDuration, isFalse);
      expect(entry.formattedDuration, '--:--');
    });

    test('süre geldiyse biçimlendirilir', () {
      const entry = PlaylistEntry(url: 'u', title: 't', durationSeconds: 125);
      expect(entry.hasDuration, isTrue);
      expect(entry.formattedDuration, '2:05');
    });

    test('saat eşiği doğru biçimlenir', () {
      expect(PlaylistEntry.formatDuration(3661), '1:01:01');
      expect(PlaylistEntry.formatDuration(59), '0:59');
    });
  });

  group('PlaylistFetchResult — sessiz kırpma yasağı', () {
    test('üst sınır aşıldığında kırpma miktarı raporlanabilir', () {
      final result = PlaylistFetchResult(
        entries: List.generate(
          100,
          (i) => PlaylistEntry(url: 'u$i', title: 't$i'),
        ),
        totalCount: 250,
        sourceUrl: 'https://www.youtube.com/@kanal',
      );
      expect(result.isTruncated, isTrue);
      expect(result.truncatedCount, 150);
    });

    test('kırpma yoksa bildirim de yok', () {
      const result = PlaylistFetchResult(
        entries: [PlaylistEntry(url: 'u', title: 't')],
        totalCount: 1,
        sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
      );
      expect(result.isTruncated, isFalse);
      expect(result.truncatedCount, 0);
    });

    test('tek seferlik üst sınır tanımlı ve pozitif', () {
      expect(DownloadProvider.maxPlaylistEntries, greaterThan(0));
    });
  });

  group('PlaylistFetchResult — zaten var olanlar atılmaz, işaretlenir', () {
    test('mevcut videolar sayılır ama listede kalır', () {
      const result = PlaylistFetchResult(
        entries: [
          PlaylistEntry(url: 'a', title: 'a', alreadyPresent: true),
          PlaylistEntry(url: 'b', title: 'b'),
          PlaylistEntry(url: 'c', title: 'c', alreadyPresent: true),
        ],
        totalCount: 3,
        sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
      );
      // Listeden atılmıyor: kullanıcı durumu görebilsin.
      expect(result.entries.length, 3);
      expect(result.alreadyPresentCount, 2);
      // Varsayılan seçim yalnız yeni olanları içerir.
      expect(result.selectableEntries.length, 1);
      expect(result.selectableEntries.single.url, 'b');
    });
  });

  group('Kota: süresi bilinmeyen video muaf değildir', () {
    test('varsayılan süre tahmini tanımlı ve pozitif', () {
      expect(DownloadProvider.defaultVideoDurationSeconds, greaterThan(0),
          reason: 'süresi bilinmeyen videolar kotadan muaf tutulursa kota '
              'sessizce aşılır');
    });
  });

  group('Playlist/kanal bağlantısı tespiti', () {
    test('oynatma listesi ve kanal biçimleri tanınır', () {
      const urls = [
        'https://www.youtube.com/playlist?list=PL123',
        'https://www.youtube.com/watch?v=abc&list=PL123',
        'https://www.youtube.com/@kanaladi',
        'https://www.youtube.com/channel/UC123',
        'https://www.youtube.com/c/KanalAdi',
      ];
      for (final url in urls) {
        expect(DownloadProvider.isPlaylistUrl(url), isTrue, reason: url);
      }
    });

    test('tek video bağlantısı playlist sayılmaz', () {
      expect(
          DownloadProvider.isPlaylistUrl(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          isFalse);
      expect(DownloadProvider.isPlaylistUrl('https://youtu.be/abc'), isFalse);
    });
  });
}
