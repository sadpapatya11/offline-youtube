import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/providers/download_provider.dart';

/// Kayıtlı oynatma listesi eşitlemesinin (syncSavedPlaylists) iki yıkıcı hatasını korur.
///
/// Kök sorunlar (2026-08-25 denetimi, iki kritik bulgu):
///
/// 1. Görev kimliği çakışması: yeni görevlerin id'si `epochMs_jit_0` kalıbıyla
///    üretiliyordu ve son ek SABİT 0 idi. Döngü senkron olduğu için aynı turda eklenen
///    tüm görevler aynı id'yi alıyordu. Sonuç: kuyruktan tek bir videoyu silmek aynı
///    turda eklenen hepsini siliyor, ilerleme olayları yanlış göreve yazılıyordu.
///
/// 2. Korumasız temizlik: bir oynatma listesi çekilemediğinde (ağ hatası, 429, botguard)
///    o listenin videoları "artık listede yok" sayılıp kütüphaneden çöpe atılıyor ve
///    kuyruktan siliniyordu. Kuyruk temizleme döngüsü anyPlaylistSucceeded kapısının
///    DIŞINDA olduğu için, hiçbir liste çekilemese bile bekleyen tüm görevler siliniyordu.
void main() {
  group('Eşitleme görev kimliği benzersizdir', () {
    test('aynı milisaniyede üretilen kimlikler ÇAKIŞMAZ', () {
      const epoch = 1756100000000;
      final ids = List.generate(12, (i) => DownloadProvider.buildSyncTaskId(epoch, i));

      expect(ids.toSet().length, 12,
          reason: 'aynı turda eklenen görevler aynı id alırsa tek silme hepsini siler');
    });

    test('kimlik epoch ve indeksi birlikte taşır', () {
      expect(DownloadProvider.buildSyncTaskId(1756100000000, 0), '1756100000000_jit_0');
      expect(DownloadProvider.buildSyncTaskId(1756100000000, 7), '1756100000000_jit_7');
    });

    test('farklı turlar da çakışmaz', () {
      final tur1 = List.generate(5, (i) => DownloadProvider.buildSyncTaskId(1000, i));
      final tur2 = List.generate(5, (i) => DownloadProvider.buildSyncTaskId(2000, i));
      expect({...tur1, ...tur2}.length, 10);
    });
  });

  group('Eşitleme yalnız BAŞARIYLA çekilen listeler için silme kararı verir', () {
    const basarili = {'https://youtube.com/playlist?list=PL_A'};

    test('listesi çekilemeyen video ASLA silinmez (ağ hatası veri kaybına dönüşmez)', () {
      final karar = DownloadProvider.shouldRemoveFromSync(
        sourcePlaylistUrl: 'https://youtube.com/playlist?list=PL_B',
        successfulPlaylists: basarili,
        stillOnline: false,
      );

      expect(karar, isFalse,
          reason: 'PL_B çekilemedi, çevrimiçi listesi bilinmiyor; yokluğu silme gerekçesi olamaz');
    });

    test('hiçbir liste çekilemediyse hiçbir şey silinmez', () {
      final karar = DownloadProvider.shouldRemoveFromSync(
        sourcePlaylistUrl: 'https://youtube.com/playlist?list=PL_A',
        successfulPlaylists: const {},
        stillOnline: false,
      );
      expect(karar, isFalse);
    });

    test('listesi çekilen ve gerçekten listeden kalkan video silinir', () {
      final karar = DownloadProvider.shouldRemoveFromSync(
        sourcePlaylistUrl: 'https://youtube.com/playlist?list=PL_A',
        successfulPlaylists: basarili,
        stillOnline: false,
      );
      expect(karar, isTrue);
    });

    test('listede hâlâ duran video silinmez', () {
      final karar = DownloadProvider.shouldRemoveFromSync(
        sourcePlaylistUrl: 'https://youtube.com/playlist?list=PL_A',
        successfulPlaylists: basarili,
        stillOnline: true,
      );
      expect(karar, isFalse);
    });

    test('kaynak listesi olmayan video eşitlemenin konusu değildir', () {
      expect(
        DownloadProvider.shouldRemoveFromSync(
          sourcePlaylistUrl: null,
          successfulPlaylists: basarili,
          stillOnline: false,
        ),
        isFalse,
      );
      expect(
        DownloadProvider.shouldRemoveFromSync(
          sourcePlaylistUrl: '',
          successfulPlaylists: basarili,
          stillOnline: false,
        ),
        isFalse,
      );
    });
  });
}
