import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/ui/screens/player_screen.dart';

/// Oynatıcı ekranının saf karar mantığını koruyan testler.
///
/// Bu kurallar önce doğrudan `_PlayerScreenState.build` ve `_onPlayerTick`
/// içinde yaşıyordu; video_player widget'ı testte platform kanalı istediği için
/// hiçbiri doğrulanamıyordu. Denetimde çıkan dört davranış hatası da tam olarak
/// bu doğrulanamayan satırlardaydı, bu yüzden kararlar `PlayerLogic` altına
/// alındı ve buraya kilitlendi.
void main() {
  group('Slider sürükleme taslağı', () {
    /// NEDEN: Eski kod Slider değerini doğrudan controller'dan okuyordu.
    /// Kullanıcı 2 saatlik videoda tutamağı sürüklerken parmak sağa kayıyor
    /// ama tutamak yerinde duruyor, arada bir decoder'ın yetiştiği konuma
    /// zıplayıp parmağın gerisine düşüyordu.
    test('sürükleme sırasında taslak değer kazanır, controller pozisyonu değil',
        () {
      final value = PlayerLogic.sliderValueMs(
        dragValueMs: 4200000,
        positionMs: 1000,
        durationMs: 7200000,
      );
      expect(value, 4200000.0);
    });

    test('sürükleme yokken controller pozisyonu gösterilir', () {
      final value = PlayerLogic.sliderValueMs(
        dragValueMs: null,
        positionMs: 65000,
        durationMs: 7200000,
      );
      expect(value, 65000.0);
    });

    /// NEDEN: Slider, value'nun [min, max] aralığında olmasını şart koşuyor.
    /// Süre bilinmezken (henüz initialize olmamış ya da hata sonrası
    /// sıfırlanmış değer) kırpma olmazsa ekran assert ile çöker.
    test('taslak değer süreyi aşarsa süreye kırpılır', () {
      final value = PlayerLogic.sliderValueMs(
        dragValueMs: 9999999,
        positionMs: 0,
        durationMs: 7200000,
      );
      expect(value, 7200000.0);
    });

    test('süre bilinmiyorken değer sıfıra kırpılır', () {
      final value = PlayerLogic.sliderValueMs(
        dragValueMs: 4200000,
        positionMs: 65000,
        durationMs: 0,
      );
      expect(value, 0.0);
    });
  });

  group('Tick sırasında pozisyon kaydı', () {
    /// NEDEN (kritik veri kaybı): Oynatıcı hata verince value sıfırlanıyor
    /// (position 0, duration 0). Eski kod bu tick'te savePosition(id, 0)
    /// çağırıyordu; PlaybackManager 1000 ms altını "kaydı sil" olarak
    /// yorumladığı için 45. dakikada codec hatası alan kullanıcının kaldığı
    /// yer bilgisi siliniyordu.
    test('süre sıfırlanmışsa kayıt yapılmaz, kaldığı yer silinmez', () {
      final persist = PlayerLogic.positionToPersistOnTick(
        positionMs: 0,
        durationMs: 0,
        lastSavedPosMs: 2700000,
      );
      expect(persist, isNull);
    });

    test('eşik altındaki küçük ilerlemede kayıt yapılmaz', () {
      final persist = PlayerLogic.positionToPersistOnTick(
        positionMs: 61500,
        durationMs: 7200000,
        lastSavedPosMs: 60000,
      );
      expect(persist, isNull);
    });

    test('normal ilerlemede güncel pozisyon kaydedilir', () {
      final persist = PlayerLogic.positionToPersistOnTick(
        positionMs: 63000,
        durationMs: 7200000,
        lastSavedPosMs: 60000,
      );
      expect(persist, 63000);
    });

    /// NEDEN: Video bitmek üzereyken kaydedilen pozisyon, kullanıcı videoyu
    /// yeniden açtığında onu doğrudan jeneriğe düşürür; son 3 saniyede kayıt
    /// sıfırlanır ki video baştan başlasın.
    test('son 3 saniyede sıfır kaydedilir, video baştan başlar', () {
      final persist = PlayerLogic.positionToPersistOnTick(
        positionMs: 7198000,
        durationMs: 7200000,
        lastSavedPosMs: 7100000,
      );
      expect(persist, 0);
    });
  });

  group('Tick sırasında yeniden çizim kararı', () {
    /// NEDEN: Kontroller gizli ve altyazı kapalıyken ekranda pozisyona bağlı
    /// tek bir piksel bile yok, buna rağmen saniyede 3 ila 4 setState tüm
    /// Scaffold'u yeniden kuruyordu. Bu, termal politikası olan bir uygulamada
    /// bedava ısınma demek.
    test('kontroller gizli ve altyazı kapalıyken yeniden çizim yok', () {
      final shouldRebuild = PlayerLogic.shouldRebuildForTick(
        controlsVisible: false,
        subtitlesVisible: false,
        positionMs: 60000,
        lastRenderedPosMs: 0,
      );
      expect(shouldRebuild, isFalse);
    });

    /// NEDEN: Altyazı açıkken kontroller gizli olsa bile cue'lar çiziliyor;
    /// optimizasyon altyazıyı dondurmamalı.
    test('kontroller gizli ama altyazı açıkken yeniden çizim sürer', () {
      final shouldRebuild = PlayerLogic.shouldRebuildForTick(
        controlsVisible: false,
        subtitlesVisible: true,
        positionMs: 60000,
        lastRenderedPosMs: 59000,
      );
      expect(shouldRebuild, isTrue);
    });

    test('kontroller açıkken 250 ms eşiği aşılınca yeniden çizilir', () {
      final shouldRebuild = PlayerLogic.shouldRebuildForTick(
        controlsVisible: true,
        subtitlesVisible: false,
        positionMs: 60300,
        lastRenderedPosMs: 60000,
      );
      expect(shouldRebuild, isTrue);
    });

    test('kontroller açık ama pozisyon 250 ms içinde kaldıysa çizilmez', () {
      final shouldRebuild = PlayerLogic.shouldRebuildForTick(
        controlsVisible: true,
        subtitlesVisible: false,
        positionMs: 60100,
        lastRenderedPosMs: 60000,
      );
      expect(shouldRebuild, isFalse);
    });
  });

  group('Oynatma hatası mesajı', () {
    /// NEDEN: errorDescription null olabiliyor. Doğrudan basılsaydı ekranda
    /// "null" yazacak ya da hata kutusu boş kalacaktı; kullanıcı donmuş
    /// ekranın nedenini yine göremeyecekti.
    test('açıklama yokken bile kullanıcıya anlamlı bir mesaj gösterilir', () {
      final message = PlayerLogic.playbackErrorMessage(null);
      expect(message.trim(), isNotEmpty);
      expect(message.toLowerCase().contains('null'), isFalse);
      expect(message.contains('Video oynatılamadı'), isTrue);
    });

    test('açıklama yalnız boşluktan ibaretse jenerik mesaja düşer', () {
      final message = PlayerLogic.playbackErrorMessage('   ');
      expect(message.contains('Video oynatılamadı'), isTrue);
    });

    test('platform açıklaması varsa mesaja eklenir', () {
      final message = PlayerLogic.playbackErrorMessage(
        'MediaCodecVideoRenderer error',
      );
      expect(message.contains('MediaCodecVideoRenderer error'), isTrue);
    });
  });
}
