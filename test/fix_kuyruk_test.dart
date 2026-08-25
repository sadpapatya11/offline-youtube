import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İndirme kuyruğu motorunun 2026-08-25 denetiminde bulunan davranış hatalarını
/// kilitler. Her grup, düzeltilen satır bozulduğunda KIRMIZI olacak biçimde
/// yazıldı; yalnız "çalışıyor" demek yerine korunan senaryoyu ölçer.
class _SahteOlayKanali extends MockStreamHandler {
  MockStreamHandlerEventSink? _sink;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    _sink = events;
  }

  @override
  void onCancel(Object? arguments) {
    _sink = null;
  }

  void olayGonder(Map<String, dynamic> olay) => _sink?.success(jsonEncode(olay));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kalıcı ve geçici hata ayrımı', () {
    /// Eski filtre ham metinde `contains('unavailable')` arıyordu. yt-dlp geçici
    /// sunucu hatasını "HTTP Error 503: Service Unavailable" diye yazar; bu metin
    /// filtreye takılıyor, görev hiç tekrar denenmeden kalıcı hataya düşüyordu.
    test('503 Service Unavailable KALICI sayılmaz, tekrar denenir', () {
      expect(
        DownloadQueueManager.isPermanentError('ERROR: unable to download video data: HTTP Error 503: Service Unavailable'),
        isFalse,
        reason: "'unavailable' kelimesi geçiyor diye geçici sunucu hatası kalıcı sayılırsa video bir daha hiç denenmez",
      );
    });

    test('429 istek sınırı KALICI sayılmaz', () {
      expect(
        DownloadQueueManager.isPermanentError('ERROR: HTTP Error 429: Too Many Requests'),
        isFalse,
        reason: 'istek sınırı zamanla kalkar, kalıcı sayılırsa kullanıcı elle yeniden denemek zorunda kalır',
      );
    });

    test('gerçekten yayından kalkmış video KALICI sayılır', () {
      expect(
        DownloadQueueManager.isPermanentError('ERROR: [youtube] abc123: Video unavailable'),
        isTrue,
        reason: 'kalıcı hatada tekrar denemek kuyruğu boşuna meşgul eder',
      );
      expect(
        DownloadQueueManager.isPermanentError("ERROR: [youtube] abc123: Private video. Sign in if you've been granted access to this video"),
        isTrue,
      );
    });

    /// Disk dolu hatası geçici sanılıyordu: aynı dolu diske üç kez daha yazmaya
    /// çalışılıyor, üçü de aynı hatayla yanıyor ve kullanıcıya hiçbir şey
    /// anlatmayan bir tekrar döngüsü yaşanıyordu.
    test('disk dolu (ENOSPC) KALICI sayılır, boşuna tekrarlanmaz', () {
      expect(
        DownloadQueueManager.isPermanentError('ERROR: unable to write data: [Errno 28] No space left on device'),
        isTrue,
        reason: 'yer açılmadan aynı indirme asla başarılı olamaz',
      );
    });

    test('ağ kesintisi KALICI sayılmaz', () {
      expect(
        DownloadQueueManager.isPermanentError('ERROR: unable to download API page: Read timed out'),
        isFalse,
      );
    });
  });

  group('Tekrar denemede üstel geri çekilme', () {
    /// Sabit 3 saniyelik gecikme, istek sınırına takılmış bir hesapta durumu
    /// kötüleştiriyordu: art arda giden istekler sınırı uzatıyordu.
    test('her tekrar bir öncekinin iki katı bekler', () {
      final ilk = DownloadQueueManager.retryDelayMs(1, 'ERROR: unknown failure');
      final ikinci = DownloadQueueManager.retryDelayMs(2, 'ERROR: unknown failure');
      expect(ikinci, ilk * 2,
          reason: 'gecikme sabit kalırsa aynı hata art arda aynı hızda tekrarlanır');
    });

    test('429 istek sınırında taban bekleme çok daha uzundur', () {
      final normal = DownloadQueueManager.retryDelayMs(1, 'ERROR: unknown failure');
      final sinirli = DownloadQueueManager.retryDelayMs(1, 'ERROR: HTTP Error 429: Too Many Requests');
      expect(sinirli, greaterThan(normal * 5),
          reason: 'istek sınırında saniyeler içinde tekrar denemek sınırı uzatır');
    });

    test('bekleme süresi üst sınırla kapanır (sonsuza büyümez)', () {
      expect(DownloadQueueManager.retryDelayMs(20, 'ERROR: HTTP Error 429: Too Many Requests'),
          lessThanOrEqualTo(600000));
    });
  });

  group('Bağlantı olayının yönü', () {
    /// Dinleyici gelen değere hiç bakmıyordu: bağlantının KOPTUĞU olayda da
    /// kuyruk yeniden başlatılıyordu. "Tüm ağlar" modunda ağ katmanı gerçek
    /// bağlantıyı sormadan izin verdiği için indirme kopuk hatta başlıyordu.
    test('bağlantı yokken kuyruk uyandırılmaz', () {
      expect(DownloadQueueManager.isOnline([ConnectivityResult.none]), isFalse);
      expect(DownloadQueueManager.isOnline([]), isFalse,
          reason: 'boş liste "bilinmiyor" demektir, izin olarak yorumlanamaz');
    });

    test('gerçek bağlantı gelince kuyruk uyandırılır', () {
      expect(DownloadQueueManager.isOnline([ConnectivityResult.wifi]), isTrue);
      expect(DownloadQueueManager.isOnline([ConnectivityResult.mobile]), isTrue);
    });
  });

  group('Asılı kalan indirmenin tespiti', () {
    /// yt-dlp bir DNS veya soket takılmasında %0.0'da saatlerce bekleyebiliyor.
    /// Watchdog ölçütü (lastProgressTime) vardı ama kimse bakmıyordu; görev
    /// `downloading` kaldığı için activeTaskId dolu kalıyor ve kuyruk hiç
    /// ilerlemiyordu.
    test('eşiği aşan sessizlik takılma sayılır', () {
      final simdi = DateTime(2026, 8, 25, 12, 0);
      expect(
        DownloadQueueManager.isStalled(simdi.subtract(const Duration(minutes: 11)), simdi),
        isTrue,
      );
    });

    test('normal indirme takılma sayılmaz', () {
      final simdi = DateTime(2026, 8, 25, 12, 0);
      expect(
        DownloadQueueManager.isStalled(simdi.subtract(const Duration(seconds: 20)), simdi),
        isFalse,
        reason: 'yanlış tespit, sağlam bir indirmeyi ffmpeg birleştirmesinin ortasında öldürür',
      );
    });

    test('ölçüm yoksa takılma iddia edilmez', () {
      expect(DownloadQueueManager.isStalled(null, DateTime(2026, 8, 25)), isFalse);
    });

    test('eşik uzun birleştirmeleri öldürmeyecek kadar geniştir', () {
      expect(DownloadQueueManager.stallTimeout.inMinutes, greaterThanOrEqualTo(5),
          reason: 'yt-dlp ffmpeg birleştirmesi sırasında stdout\'a satır basmaz');
    });
  });

  group('Meta dosyası eşleştirmesi', () {
    /// Eşleştirme yt-dlp çıktı şablonuyla (`%(title).50s [%(id)s].%(ext)s`)
    /// hizalıdır. Gevşetilirse YANLIŞ videonun meta kaydı ezilir ve kütüphanede
    /// başka bir videonun başlığı/süresi görünür.
    test('doğru video kimliğini taşıyan dosya eşleşir', () {
      expect(
        DownloadQueueManager.isDownloadedFileForVideo('/sd/Şarkı Klibi [dQw4w9WgXcQ].mp4', 'dQw4w9WgXcQ'),
        isTrue,
      );
    });

    test('başka videonun dosyası eşleşmez', () {
      expect(
        DownloadQueueManager.isDownloadedFileForVideo('/sd/Başka Video [abcdefghijk].mp4', 'dQw4w9WgXcQ'),
        isFalse,
        reason: 'yanlış eşleşme başka videonun meta kaydını ezer',
      );
    });

    test('meta dosyasının kendisi hedef seçilmez', () {
      expect(
        DownloadQueueManager.isDownloadedFileForVideo('/sd/Şarkı Klibi [dQw4w9WgXcQ].meta.json', 'dQw4w9WgXcQ'),
        isFalse,
      );
    });

    test('kimlik çıkarılamadıysa hiçbir dosya eşleşmez', () {
      expect(DownloadQueueManager.isDownloadedFileForVideo('/sd/Video [x].mp4', ''), isFalse,
          reason: 'boş kimlikle eşleşme, rastgele bir dosyanın metasını ezmek demektir');
    });
  });

  group('Bozuk kayıt tüm kuyruğu silmez', () {
    Map<String, dynamic> gecerliKayit(String id, DownloadStatus durum) => DownloadTask(
          id: id,
          url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          title: 'Görev $id',
          status: durum,
        ).toJson();

    /// Eski kod tüm listeyi tek try/catch ile çözüyordu: sürüm yükseltmesinden
    /// kalan TEK bir bozuk kayıt istisna fırlattığında catch bloğu tasks.clear()
    /// çağırıyor ve kullanıcının kuyruğunun tamamı sessizce siliniyordu.
    test('bozuk kayıt atlanır, sağlam kayıtlar korunur ve kayıp sayılır', () {
      final sonuc = DownloadQueueManager.parseStoredTasks([
        gecerliKayit('a', DownloadStatus.queued),
        {'id': 42, 'url': 'https://x', 'status': 'queued'}, // id tipi bozuk
        gecerliKayit('b', DownloadStatus.queued),
      ]);

      expect(sonuc.tasks.map((t) => t.id).toList(), ['a', 'b'],
          reason: 'tek bozuk kayıt yüzünden 40 görevlik kuyruk silinmemeli');
      expect(sonuc.droppedCount, 1,
          reason: 'kayıp sayılmazsa kullanıcı uyarılamaz, kuyruğun eksildiğini fark etmez');
    });

    test('kayıt hiç nesne değilse de tüm liste düşmez', () {
      final sonuc = DownloadQueueManager.parseStoredTasks([
        'tamamen alakasız metin',
        gecerliKayit('c', DownloadStatus.queued),
      ]);

      expect(sonuc.tasks.single.id, 'c');
      expect(sonuc.droppedCount, 1);
    });

    /// downloading ve fetchingMetadata YARIM KALMIŞ geçiş durumlarıdır: süreç
    /// öldüğü için ikisini de sürdürecek taraf kalmamıştır.
    test('yarım kalan indirme kuyruğa geri alınır', () {
      final sonuc = DownloadQueueManager.parseStoredTasks([
        gecerliKayit('d', DownloadStatus.downloading),
      ]);
      expect(sonuc.tasks.single.status, DownloadStatus.queued);
    });

    /// Eski kod fetchingMetadata durumunu hiç kurtarmıyordu: görev "Bilgiler
    /// alınıyor..." başlığıyla sonsuza kadar kuyrukta kalıyor, üstelik aynı video
    /// tekrar eklenemiyordu ("zaten indirme listesinde mevcut").
    test('yarım kalan metadata çekimi zombi bırakmaz', () {
      final sonuc = DownloadQueueManager.parseStoredTasks([
        gecerliKayit('e', DownloadStatus.fetchingMetadata),
      ]);

      expect(sonuc.tasks.single.status, DownloadStatus.error,
          reason: 'fetchingMetadata olarak geri yüklenen görevi hiçbir kod yolu ilerletmez',
      );
      expect(sonuc.tasks.single.errorMessage, isNotNull);
      expect(sonuc.tasks.single.hadPreviousError, isTrue,
          reason: 'kullanıcı "hataları yeniden dene" ile kurtarabilmeli');
    });
  });

  group('Gecikmiş iptal onayı yeniden denenecek görevi öldürmez', () {
    test('kuyruğa yeniden alınmış göreve gelen cancelled olayı YOK SAYILIR', () {
      expect(DownloadQueueManager.shouldApplyCancelEvent(DownloadStatus.queued), isFalse,
          reason: 'watchdog takılan görevi iptal edip kuyruğa alır; native onayı bunu öldürürse video bir daha indirilmez');
    });

    test('watchdog vazgeçtiği için hataya düşen görev sessizce iptale çevrilmez', () {
      expect(DownloadQueueManager.shouldApplyCancelEvent(DownloadStatus.error), isFalse,
          reason: 'iptale çevrilen görev "hataları yeniden dene" kapsamından çıkar ve kullanıcı bir daha kurtaramaz');
    });

    test('kullanıcının gerçek iptali uygulanır', () {
      expect(DownloadQueueManager.shouldApplyCancelEvent(DownloadStatus.cancelled), isTrue);
      expect(DownloadQueueManager.shouldApplyCancelEvent(DownloadStatus.downloading), isTrue);
    });

    test('kapı her durumu açıkça sınıflandırır (yeni durum eklenirse burası kırmızı olur)', () {
      final yoksayilan = DownloadStatus.values
          .where((d) => !DownloadQueueManager.shouldApplyCancelEvent(d))
          .toSet();
      expect(yoksayilan, {DownloadStatus.queued, DownloadStatus.error});
    });
  });

  group('Hata olayının GERÇEK akış üzerinden davranışı', () {
    const olayKanali = EventChannel('com.offlineyoutube/download_events');
    const yontemKanali = MethodChannel('com.offlineyoutube/downloader');
    final sahteKanal = _SahteOlayKanali();
    late DownloadQueueManager manager;

    DownloadTask gorevEkle(String id, DownloadStatus durum, {int retryCount = 0}) {
      final t = DownloadTask(
        id: id,
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Test Videosu',
        status: durum,
        retryCount: retryCount,
      );
      manager.tasks.add(t);
      return t;
    }

    Future<void> olayIsle() async {
      await Future.delayed(const Duration(milliseconds: 60));
    }

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(olayKanali, sahteKanal);
      messenger.setMockMethodCallHandler(yontemKanali, (call) async => true);

      manager = DownloadQueueManager.instance;
      // Kuyruk motorunun kendi kendine iş başlatmasını engelle: bu grup yalnız
      // olay işleyicisinin kararlarını ölçüyor.
      manager.isQueuePaused = true;
      await manager.init();
    });

    setUp(() {
      manager.tasks.clear();
      manager.activeTaskId = null;
    });

    tearDownAll(() {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(olayKanali, null);
      messenger.setMockMethodCallHandler(yontemKanali, null);
      manager.tasks.clear();
      manager.activeTaskId = null;
    });

    test('KURULUM DOĞRULAMASI: sahte kanal olayları gerçekten teslim ediliyor', () async {
      final gorev = gorevEkle('kurulum-kontrol', DownloadStatus.downloading);
      sahteKanal.olayGonder({'type': 'progress', 'taskId': 'kurulum-kontrol', 'progress': 7.0});
      await olayIsle();
      expect(gorev.progress, 7.0,
          reason: 'bu kırmızıysa gruptaki diğer testler olay almadan geçiyor demektir, hepsi yanlış yeşildir');
    });

    test('geçici hatada görev kuyruğa döner ve sayaç artar', () async {
      final gorev = gorevEkle('gecici', DownloadStatus.downloading);

      sahteKanal.olayGonder({
        'type': 'error',
        'taskId': 'gecici',
        'error': 'ERROR: unable to download video data: HTTP Error 503: Service Unavailable',
      });
      await olayIsle();

      expect(gorev.status, DownloadStatus.queued,
          reason: "'Service Unavailable' kalıcı sayılırsa geçici sunucu hatası videoyu kalıcı olarak yakar");
      expect(gorev.retryCount, 1);
    });

    /// Poison pill koruması: sınır kalkarsa (örneğin 99 olursa) sürekli hata veren
    /// tek bir video kuyruğu döndürerek arkasındaki her şeyi bloke eder.
    test('tekrar sınırı dolunca görev kalıcı hataya düşer', () async {
      final gorev = gorevEkle('sinir', DownloadStatus.downloading,
          retryCount: DownloadQueueManager.maxRetries);

      sahteKanal.olayGonder({
        'type': 'error',
        'taskId': 'sinir',
        'error': 'ERROR: unable to download video data: HTTP Error 503: Service Unavailable',
      });
      await olayIsle();

      expect(gorev.status, DownloadStatus.error,
          reason: 'sınır uygulanmazsa aynı görev kuyruğu sonsuza kadar döndürür');
      expect(gorev.retryCount, DownloadQueueManager.maxRetries,
          reason: 'sınır aşıldıktan sonra sayaç artmaya devam etmemeli');
    });

    test('kalıcı hatada hiç tekrar denenmez', () async {
      final gorev = gorevEkle('kalici', DownloadStatus.downloading);

      sahteKanal.olayGonder({
        'type': 'error',
        'taskId': 'kalici',
        'error': 'ERROR: [youtube] abc123: Video unavailable',
      });
      await olayIsle();

      expect(gorev.status, DownloadStatus.error);
      expect(gorev.retryCount, 0,
          reason: 'yayından kalkmış videoyu tekrar denemek kuyruğu boşuna meşgul eder');
    });

    test('yeniden denenmek üzere kuyrukta bekleyen göreve gelen cancelled olayı yok sayılır', () async {
      final gorev = gorevEkle('gecikmis-iptal', DownloadStatus.queued);

      sahteKanal.olayGonder({'type': 'cancelled', 'taskId': 'gecikmis-iptal'});
      await olayIsle();

      expect(gorev.status, DownloadStatus.queued,
          reason: 'watchdog takılan indirmeyi iptal edip kuyruğa alır; gecikmiş onay görevi öldürürse video bir daha indirilmez');
    });

    test('normal iptal akışı bozulmadı', () async {
      final gorev = gorevEkle('gercek-iptal', DownloadStatus.downloading);

      sahteKanal.olayGonder({'type': 'cancelled', 'taskId': 'gercek-iptal'});
      await olayIsle();

      expect(gorev.status, DownloadStatus.cancelled);
    });
  });
}
