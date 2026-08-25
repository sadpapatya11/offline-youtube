import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/providers/download_provider.dart';

/// Sağlayıcı katmanında düzeltilen davranış hatalarını koruyan testler.
///
/// Her testin varlık sebebi, koruduğu satır bozulduğunda KIRMIZI olmasıdır:
/// burada yalnız saf (bağımlılıksız) kurallar sınanır, çünkü kanal ve dosya
/// sistemi gerektiren yollar test ortamında yalancı yeşil üretir.
void main() {
  group('cleanErrorMessage — "bot" alt dizesi alakasız hataları maskelemez', () {
    test('başlığında "Bottom" geçen kaldırılmış video, bot hatası sanılmaz', () {
      // Çıplak contains('bot') kontrolü listenin BAŞINDA olduğu için, içinde
      // "Bottom" geçen her hata bot doğrulaması diye etiketleniyordu; kullanıcı
      // videonun yayından kaldırıldığını hiç öğrenemiyor, bunun yerine boşuna
      // yt-dlp motorunu güncellemeye yönlendiriliyordu.
      const raw = 'ERROR: [youtube] a1b2: Bottom 10 Klip: Video unavailable';
      expect(
        DownloadProvider.cleanErrorMessage(raw),
        'Video yayından kaldırılmış veya gizli.',
      );
    });

    test('yolunda "Robot" geçen depolama hatası, bot hatası sanılmaz', () {
      // Aynı maskeleme depolama hatalarını da yutuyordu: kullanıcı klasör /
      // yazma izni sorununu görmediği için düzeltemiyordu.
      const raw =
          'ERROR: unable to open for writing: [Errno 2] No such file or directory: '
          '/storage/emulated/0/Robot/klip.mp4';
      expect(
        DownloadProvider.cleanErrorMessage(raw),
        contains('Depolama erişim hatası'),
      );
    });

    test('gerçek bot doğrulama imzaları hâlâ tanınır', () {
      const signatures = [
        'ERROR: [youtube] a1b2: Sign in to confirm you are not a bot',
        'ERROR: [youtube] a1b2: botguard challenge failed',
      ];
      for (final raw in signatures) {
        expect(
          DownloadProvider.cleanErrorMessage(raw),
          contains('YouTube bot doğrulaması istedi'),
          reason: raw,
        );
      }
    });
  });

  group('Toplam süre kotası kapısı', () {
    // Kural üç ayrı ekleme yolunda satır içi yazılıyken hiçbir test onu
    // koruyamıyordu: kapıyı komple açan bir mutasyon tüm paketi yeşil bırakıyordu.

    test('kota tam dolduğunda yeni ekleme kapısı kapanır', () {
      expect(
        DownloadProvider.isDurationQuotaFull(
          currentTotalSeconds: 36000,
          maxDurationSeconds: 36000,
        ),
        isTrue,
        reason: 'eşitlik "dolu" sayılmazsa kota her zaman bir video aşılır',
      );
      expect(
        DownloadProvider.isDurationQuotaFull(
          currentTotalSeconds: 35999,
          maxDurationSeconds: 36000,
        ),
        isFalse,
      );
    });

    test('kotayı tam dolduran video kabul, bir saniye taşıran reddedilir', () {
      expect(
        DownloadProvider.fitsInDurationQuota(
          currentTotalSeconds: 35000,
          videoSeconds: 1000,
          maxDurationSeconds: 36000,
        ),
        isTrue,
      );
      expect(
        DownloadProvider.fitsInDurationQuota(
          currentTotalSeconds: 35000,
          videoSeconds: 1001,
          maxDurationSeconds: 36000,
        ),
        isFalse,
      );
    });

    test('süresi bilinmeyen video tek başına kapıyı kapatmaz', () {
      // Tek video ekleme yolunda süre okunamadığında ekleme tamamen tıkanmamalı.
      expect(
        DownloadProvider.fitsInDurationQuota(
          currentTotalSeconds: 35999,
          videoSeconds: 0,
          maxDurationSeconds: 36000,
        ),
        isTrue,
      );
    });

    test('ham süre toplu yolda kotayı tamamen etkisiz kılar', () {
      // Bu testin amacı effectiveDurationSeconds'ın NEDEN var olduğunu sabitlemek:
      // --flat-playlist süreyi çoğu girdide vermez, ham 0 ile kapı hiç kapanmaz.
      var total = 0;
      var added = 0;
      for (var i = 0; i < 500; i++) {
        if (!DownloadProvider.fitsInDurationQuota(
          currentTotalSeconds: total,
          videoSeconds: 0,
          maxDurationSeconds: 36000,
        )) {
          continue;
        }
        added++;
      }
      expect(added, 500,
          reason: 'ham süre kullanılırsa 500 video 10 saatlik kotaya "sığar"');
    });

    test('süresi bilinmeyen videolar tahmini süreyle kotayı aşamaz', () {
      // Oynatma listesi ve eşitleme yolları effectiveDurationSeconds geçmek
      // ZORUNDADIR; aksi hâlde 10 saatlik sınır konmuş olsa bile yüzlerce video
      // "toplam 0 saniye" sayılıp kuyruğa dökülür.
      const maxDurationSec = 36000; // 10 saat
      var total = 0;
      var added = 0;
      for (var i = 0; i < 500; i++) {
        final effective = DownloadProvider.effectiveDurationSeconds(0);
        if (!DownloadProvider.fitsInDurationQuota(
          currentTotalSeconds: total,
          videoSeconds: effective,
          maxDurationSeconds: maxDurationSec,
        )) {
          continue;
        }
        total += effective;
        added++;
      }
      expect(added, maxDurationSec ~/ DownloadProvider.defaultVideoDurationSeconds);
      expect(total, lessThanOrEqualTo(maxDurationSec));
    });

    test('bilinen süre tahminle değiştirilmez', () {
      expect(DownloadProvider.effectiveDurationSeconds(742), 742);
      expect(DownloadProvider.effectiveDurationSeconds(0),
          DownloadProvider.defaultVideoDurationSeconds);
      expect(DownloadProvider.effectiveDurationSeconds(-5),
          DownloadProvider.defaultVideoDurationSeconds);
    });
  });

  group('Eşitleme: çekilemeyen liste sessizce yutulmaz', () {
    test('hata yoksa kullanıcıya ek mesaj gösterilmez', () {
      expect(
        DownloadProvider.buildSyncFailureNotice(
            attemptedCount: 3, failedCount: 0),
        isNull,
        reason: 'başarılı turda mesaj kirliliği olmamalı',
      );
    });

    test('listelerin bir kısmı çekilemediyse sayı ile bildirilir', () {
      final notice = DownloadProvider.buildSyncFailureNotice(
          attemptedCount: 3, failedCount: 1);
      expect(notice, isNotNull);
      expect(notice, contains('3 listeden 1'));
      expect(notice, contains('silinmedi'),
          reason: 'kullanıcı eksik videoların silinmediğini bilmeli');
    });

    test('hiçbir liste çekilemediyse ayrı ve net uyarı verilir', () {
      final notice = DownloadProvider.buildSyncFailureNotice(
          attemptedCount: 2, failedCount: 2);
      expect(notice, contains('Hiçbir oynatma listesi çekilemedi'));
    });
  });
}
