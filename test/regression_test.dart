import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/playlist_entry.dart';
import 'package:offlineyoutube/providers/download_provider.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';

/// v1.4.3'te yazılıp v2.2.1 tabanına hiç taşınamayan regresyon paketinin
/// v2.2.1 API'sine uyarlanmış hâli.
///
/// Buradaki her test, paketin geri kalanında KORUNMAYAN bir davranışa çapalıdır:
/// aynı iddiayı zaten kilitleyen bir test varsa (örn. kalıcı hata imzaları
/// `fix_kuyruk_test.dart`'ta, kota kapıları `fix_saglayici_test.dart`'ta) burada
/// tekrarlanmadı. Sabitin yalnız varlığını ölçen kontrol de yazılmadı; her
/// iddia sabitin ETKİSİNİ ölçer, çünkü `expect(sabit, greaterThan(0))` sabiti
/// bozan hiçbir mutasyonu yakalamaz.
void main() {
  group('Oynatma listesi tespiti: tek kaynak ve harf duyarsız', () {
    /// Karar tek yerde ([DownloadProvider.isPlaylistUrl]) verilir ve
    /// `home_screen` de bu fonksiyonu çağırır. Fonksiyon bağlantıyı önce
    /// küçük harfe çevirir; bu adım düşerse YouTube'un paylaş menüsünden veya
    /// elle büyük harfle yapıştırılan bir liste bağlantısı "tek video" sayılır,
    /// seçim ekranı hiç açılmaz ve yt-dlp'ye tek video olarak gönderilen liste
    /// bağlantısı anlaşılmaz bir hatayla düşer.
    test('büyük/küçük harf farkı kararı değiştirmez', () {
      expect(DownloadProvider.isPlaylistUrl('https://YouTube.com/PlayList?LIST=PL123'), isTrue);
      expect(DownloadProvider.isPlaylistUrl('https://www.YouTube.com/Watch?v=dQw4w9WgXcQ&List=PL123'), isTrue);
      expect(DownloadProvider.isPlaylistUrl('https://www.YouTube.com/CHANNEL/UCabcdefghijklmnop'), isTrue);
    });

    /// `/user/` biçimi paketin başka hiçbir testinde geçmiyor. Dal silinirse
    /// eski kanal bağlantısı tek video sayılır ve kanalın tamamı yerine hiçbir
    /// şey indirilmez.
    test('eski /user/ kanal biçimi de liste sayılır', () {
      expect(DownloadProvider.isPlaylistUrl('https://www.youtube.com/user/eskikullanici'), isTrue);
    });

    /// Kritik sıralama: `addDownload` önce [DownloadProvider.isValidYouTubeUrl]
    /// kapısından geçirir, liste dalına ANCAK ondan sonra girer. Doğrulama
    /// kanal biçimlerinden birini reddederse o bağlantı liste dalına hiç
    /// ulaşamaz; kullanıcı "Geçersiz YouTube bağlantısı" mesajı alır ve kanalı
    /// hiçbir zaman indiremez. İki fonksiyon ayrı dosyalarda değişebildiği için
    /// bağ burada açıkça ölçülür.
    test('liste sayılan her bağlantı URL doğrulamasından da geçer', () {
      const listeBaglantilari = [
        'https://www.youtube.com/playlist?list=PL123',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123',
        'https://www.youtube.com/@kanaladi',
        'https://www.youtube.com/channel/UCabcdefghijklmnop',
        'https://www.youtube.com/c/KanalAdi',
        'https://www.youtube.com/user/eskikullanici',
        'https://m.youtube.com/playlist?list=PL123',
        'https://music.youtube.com/playlist?list=PL123',
      ];
      for (final url in listeBaglantilari) {
        expect(DownloadProvider.isPlaylistUrl(url), isTrue, reason: '$url liste sayılmalıydı');
        expect(DownloadProvider.isValidYouTubeUrl(url), isTrue,
            reason: '$url doğrulamadan geçemezse liste dalına hiç ulaşamaz');
      }
    });

    /// Tespit kalıbı gevşetilirse (örn. `/c/` yerine `c` aranırsa) tek video
    /// bağlantıları liste sanılır: kullanıcı tek bir videoyu indirmek isterken
    /// karşısına boş bir seçim ekranı çıkar. Shorts ve zaman damgalı youtu.be
    /// biçimleri paketin başka testinde geçmiyor.
    test('tek video bağlantıları liste SAYILMAZ', () {
      const tekVideolar = [
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ?t=30',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      ];
      for (final url in tekVideolar) {
        expect(DownloadProvider.isPlaylistUrl(url), isFalse, reason: '$url tek video olmalıydı');
      }
    });
  });

  group('Kalıcı ve geçici hata sınıflandırması çakışmaz', () {
    /// [DownloadQueueManager.isPermanentError] ile
    /// [DownloadProvider.isNetworkRelatedError] iki AYRI dosyada, iki ayrı imza
    /// listesiyle çalışır. Bir ağ hatası kalıcı sayılırsa görev hiç tekrar
    /// denenmez: kullanıcı metroya girdiği için kopan tek bir indirme, ağ geri
    /// geldiğinde de ölü kalır ve elle tekrar başlatılmadıkça asla inmez.
    test('ağ hatalarının hiçbiri kalıcı sayılmaz', () {
      const agHatalari = [
        'ERROR: [youtube] dQw4w9WgXcQ: Unable to download API page: [Errno 7] No address associated with hostname',
        'ERROR: unable to download video data: <urlopen error [Errno 111] Connection refused>',
        'ERROR: Unable to download webpage: The read operation timed out',
        'SocketException: Failed host lookup: "www.youtube.com"',
        'ERROR: [youtube] dQw4w9WgXcQ: Temporary failure in name resolution',
        'ERROR: Unable to download webpage: <urlopen error [Errno 104] Connection reset by peer>',
      ];
      for (final hata in agHatalari) {
        expect(DownloadProvider.isNetworkRelatedError(hata), isTrue,
            reason: '"$hata" ağ hatası olarak tanınmalıydı');
        expect(DownloadQueueManager.isPermanentError(hata), isFalse,
            reason: '"$hata" kalıcı sayılırsa geçici bir kesinti görevi kalıcı olarak öldürür');
      }
    });

    /// Ters yön: kalıcı bir hata ağ hatası sayılırsa kuyruk motoru onu sonsuza
    /// dek tekrar dener (poison pill) ve arkasındaki bütün kuyruk ilerlemez.
    /// Disk dolu (ENOSPC) imzası özellikle önemli: `Errno 28` ile `Errno 7`
    /// birbirine karışırsa dolu diske yazma denemesi durmadan tekrarlanır.
    test('kalıcı hataların hiçbiri ağ hatası sayılmaz', () {
      const kaliciHatalar = [
        'ERROR: Video unavailable',
        'ERROR: Private video. Sign in if you have been granted access to this video',
        'ERROR: unable to write data: [Errno 28] No space left on device',
      ];
      for (final hata in kaliciHatalar) {
        expect(DownloadQueueManager.isPermanentError(hata), isTrue,
            reason: '"$hata" kalıcı sayılmalıydı, yoksa sonsuza dek tekrarlanır');
        expect(DownloadProvider.isNetworkRelatedError(hata), isFalse,
            reason: '"$hata" ağ hatası sayılırsa kullanıcıya yanlış "internet yok" mesajı gösterilir');
      }
    });
  });

  group('Hata mesajı kök nedeni maskelemez', () {
    /// [DownloadProvider.cleanErrorMessage] ağ kontrolünü EN BAŞTA yapar ve
    /// eşleşirse geri kalan hiçbir dala bakmadan "internet yok" der. Ağ imzası
    /// listesi genişletilirken kalıcı hata metinlerinden birine değerse
    /// kullanıcı, videonun yayından kalktığını asla öğrenemez: çalışan bir
    /// bağlantıyla oturup ağını düzeltmeye çalışır.
    test('yayından kalkmış video ağ mesajıyla maskelenmez', () {
      expect(DownloadProvider.cleanErrorMessage('ERROR: Video unavailable'),
          'Video yayından kaldırılmış veya gizli.');
    });

    /// Bot doğrulama dalı `sign in to confirm` arar. Kalıp `sign in` kadar
    /// gevşetilirse yt-dlp'nin gizli video mesajı ("Private video. Sign in if
    /// you have been granted access") bot hatası sanılır ve kullanıcı, aslında
    /// erişim izni olmayan bir video için boşuna yt-dlp motorunu günceller.
    test('gizli video mesajı bot doğrulaması sanılmaz', () {
      expect(
          DownloadProvider.cleanErrorMessage(
              'ERROR: Private video. Sign in if you have been granted access to this video'),
          'Bu video gizli olarak ayarlanmış.');
    });

    /// İstek sınırı geçici bir durumdur ve kullanıcıya "uygulama kendisi tekrar
    /// deneyecek" denmelidir. Ağ dalına düşerse kullanıcı ağını kurcalamaya
    /// başlar, kalıcı dala düşerse videoyu elle silip yeniden ekler.
    test('istek sınırı kendi mesajını korur', () {
      expect(DownloadProvider.cleanErrorMessage('ERROR: HTTP Error 429: Too Many Requests'),
          'YouTube istek sınırı aşıldı. Uygulama otomatik yeniden deneyecek.');
    });
  });

  group('Tekrar alanları disk turunu sağlam geçer', () {
    /// Görevler diske JSON olarak yazılır, uygulama açılışında geri okunur.
    /// `retryCount` bu turda düşerse sayaç her açılışta sıfırlanır: tekrar
    /// hakkını çoktan tüketmiş bir görev sonsuza dek yeniden denenir ve
    /// arkasındaki kuyruk hiç ilerlemez. Tur, diskteki gerçek yol gibi
    /// jsonEncode/jsonDecode üzerinden yapılır; düz Map aktarımı tip
    /// kayıplarını gizlerdi.
    test('tekrar sayacı yeniden başlatmada sıfırlanmaz', () {
      final gorev = DownloadTask(
        id: '7',
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'video',
        status: DownloadStatus.error,
        retryCount: DownloadQueueManager.maxRetries,
        errorMessage: 'ERROR: Unable to download webpage: The read operation timed out',
      );

      final geriYuklenen = _diskTuru(gorev);

      expect(geriYuklenen.retryCount, DownloadQueueManager.maxRetries);
      expect(geriYuklenen.retryCount < DownloadQueueManager.maxRetries, isFalse,
          reason: 'kuyruk motorunun tekrar kapısı tam bu karşılaştırmayı kullanır; '
              'sayaç sıfırlanırsa geçici görünen kalıcı bir hata kuyruğu kilitler');
    });

    /// Alanı hiç içermeyen ESKİ kayıtlar (sürüm yükseltmesi sonrası diskte
    /// kalanlar) okunabilir olmalı. Okuma istisna fırlatırsa kayıt bozuk sayılıp
    /// atılır ve kullanıcı kuyruğunun silindiğini görür; varsayılan yanlış
    /// tarafa düşerse görev hiç denenmeden hataya yazılır.
    test('alanı olmayan eski kayıt tekrar hakkını korur', () {
      final eski = DownloadTask.fromJson(const {
        'id': '1',
        'url': 'https://youtu.be/dQw4w9WgXcQ',
        'title': 't',
        'status': 'queued',
      });

      expect(eski.retryCount, 0);
      expect(eski.retryCount < DownloadQueueManager.maxRetries, isTrue,
          reason: 'eski kayıt tekrar hakkı tükenmiş sayılırsa ilk hatada kalıcı olarak ölür');
    });

    /// `sourcePlaylistUrl` kopyalamada korunuyor (bkz. `fix_servis_model_test`)
    /// ama disk turunda korunduğu hiçbir yerde ölçülmüyordu. Yeniden başlatmada
    /// düşerse görev "elle eklenmiş tek video" gibi görünür:
    /// `shouldRemoveFromSync` null kaynak için her zaman false döndüğünden
    /// listeden çıkarılmış video kuyrukta sonsuza dek asılı kalır.
    test('kaynak oynatma listesi bağlantısı disk turunda düşmez', () {
      final listeGorevi = DownloadTask(
        id: '8',
        url: 'https://youtu.be/dQw4w9WgXcQ',
        title: 'liste videosu',
        sourcePlaylistUrl: 'https://www.youtube.com/playlist?list=PL123',
      );
      expect(_diskTuru(listeGorevi).sourcePlaylistUrl,
          'https://www.youtube.com/playlist?list=PL123');

      final tekVideo = DownloadTask(
        id: '9',
        url: 'https://youtu.be/dQw4w9WgXcQ',
        title: 'elle eklenen',
      );
      expect(_diskTuru(tekVideo).sourcePlaylistUrl, isNull,
          reason: 'elle eklenen video bir listeye bağlanırsa eşitleme onu silmeye aday sayar');
    });
  });

  group('hadPreviousError: yazılmış değer türetmeyle ezilmez', () {
    /// Diskte açıkça `false` yazan bir kayıt, durumu `error` olsa bile `false`
    /// kalmalıdır. Okuma tamamen türetmeye çevrilirse (yalnız `status` ve
    /// `errorMessage`'a bakılırsa) diske yazılan değer anlamsızlaşır: alan
    /// kalıcı bir kayıt olmaktan çıkıp her açılışta yeniden hesaplanan bir
    /// tahmine dönüşür ve hata geçmişi geri alınamaz biçimde kaybolur.
    test('açıkça yazılmış false, error durumunda bile korunur', () {
      final gorev = DownloadTask.fromJson(const {
        'id': '1',
        'url': 'https://youtu.be/dQw4w9WgXcQ',
        'title': 't',
        'status': 'error',
        'errorMessage': 'bir hata',
        'hadPreviousError': false,
      });

      expect(gorev.hadPreviousError, isFalse,
          reason: 'diskteki değer türetmeyle ezilirse alanın kalıcı olmasının anlamı kalmaz');
    });

    test('açıkça yazılmış true korunur', () {
      final gorev = DownloadTask.fromJson(const {
        'id': '1',
        'url': 'https://youtu.be/dQw4w9WgXcQ',
        'title': 't',
        'status': 'queued',
        'hadPreviousError': true,
      });

      expect(gorev.hadPreviousError, isTrue);
    });
  });

  group('URL doğrulama: YouTube dışı kaynak kabul edilmez', () {
    /// Host kontrolü `validHosts` listesi VEYA `.youtube.com` son eki ile
    /// yapılır. Son ek kontrolü `contains('youtube.com')` gibi gevşetilirse
    /// `youtube.com.saldirgan.example` gibi bir alan adı geçerli sayılır ve
    /// kullanıcının yapıştırdığı sahte bağlantı doğrudan yt-dlp'ye giderek
    /// tanımadığımız bir sunucudan indirme yapılır.
    test('youtube.com ile BAŞLAYAN yabancı alan adı reddedilir', () {
      expect(
          DownloadProvider.isValidYouTubeUrl(
              'https://youtube.com.saldirgan.example/watch?v=dQw4w9WgXcQ'),
          isFalse);
      expect(DownloadProvider.isValidYouTubeUrl('https://notyoutube.com/watch?v=dQw4w9WgXcQ'), isFalse);
      expect(DownloadProvider.isValidYouTubeUrl('https://vimeo.com/123456'), isFalse);
    });

    test('gerçek alt alan adı kabul edilir', () {
      expect(DownloadProvider.isValidYouTubeUrl('https://gaming.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    /// Uygulamanın ana giriş yolu Android paylaşım metnidir (`home_screen`
    /// paylaşılan metni doğrudan bu fonksiyona verir) ve YouTube paylaşımı
    /// bağlantıyı her zaman ek metinle sarar. Çıkarma bozulursa paylaş menüsünden
    /// gelen her video "geçersiz bağlantı" olarak reddedilir.
    test('paylaşılan metnin içinden bağlantı çıkarılır', () {
      expect(
          DownloadProvider.extractYouTubeUrl('Şunu izle https://youtu.be/dQw4w9WgXcQ via YouTube'),
          'https://youtu.be/dQw4w9WgXcQ');
    });

    /// Çıplak video kimliği youtu.be bağlantısına çevrilir. Bu dal düşerse
    /// kullanıcının kopyaladığı kimlik reddedilir; dal fazla gevşerse rastgele
    /// metin bağlantıya dönüşüp yt-dlp'ye çöp gider.
    test('çıplak video kimliği bağlantıya çevrilir, düz metin çevrilmez', () {
      expect(DownloadProvider.extractYouTubeUrl('dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ');
      expect(DownloadProvider.extractYouTubeUrl('bu bir metin'), isNull);
    });
  });

  group('Sessiz kırpma yasağı: üst sınır raporlanan sayıya bağlıdır', () {
    /// `resolvePlaylist` listeyi [DownloadProvider.maxPlaylistEntries] kadar
    /// kırpar ama `totalCount` olarak KIRPILMAMIŞ sayıyı taşır; kullanıcıya
    /// gösterilen "N video burada görünmüyor" metni bu farktan üretilir.
    /// Fark yanlış hesaplanırsa (örn. `totalCount` da kırpılmış sayıya
    /// eşitlenirse) 250 videoluk bir kanaldan sessizce eksik indirme yapılır ve
    /// kullanıcı eksiği hiç fark etmez. Sabitin yalnız pozitif olduğunu ölçmek
    /// bu mutasyonların hiçbirini yakalamaz, o yüzden fark doğrudan ölçülür.
    test('kırpılan miktar üst sınır üzerinden raporlanır', () {
      const gorunmeyen = 37;
      final sonuc = PlaylistFetchResult(
        entries: List.generate(
          DownloadProvider.maxPlaylistEntries,
          (i) => PlaylistEntry(url: 'https://youtu.be/video$i', title: 'video $i'),
        ),
        totalCount: DownloadProvider.maxPlaylistEntries + gorunmeyen,
        sourceUrl: 'https://www.youtube.com/@kanaladi',
      );

      expect(sonuc.isTruncated, isTrue);
      expect(sonuc.truncatedCount, gorunmeyen,
          reason: 'kullanıcıya gösterilen "görünmüyor" sayısı budur; yanlışsa kırpma sessizleşir');
    });
  });

  group('Süre biçimlendirme: saat eşiği sınırı', () {
    /// Eşik `h > 0` ile belirlenir. Karşılaştırma kayarsa (örn. `h >= 1` yerine
    /// `totalSeconds > 3600`) tam bir saatlik video "0:00" olarak görünür.
    /// Sınırın iki yanı paketin başka testinde ölçülmüyor.
    test('tam bir saat saat biçimine geçer, bir saniye eksiği geçmez', () {
      expect(PlaylistEntry.formatDuration(3599), '59:59');
      expect(PlaylistEntry.formatDuration(3600), '1:00:00');
    });
  });
}

/// Görevi diskteki gerçek yolun aynısından geçirir: toJson, JSON metni, fromJson.
///
/// Düz Map aktarımı tip kayıplarını gizler; kuyruk kaydı gerçekte
/// `jsonEncode` ile yazılıp `jsonDecode` ile okunduğu için tur aynen kurulur.
DownloadTask _diskTuru(DownloadTask gorev) =>
    DownloadTask.fromJson(jsonDecode(jsonEncode(gorev.toJson())) as Map<String, dynamic>);
