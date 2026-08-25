import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:offlineyoutube/models/app_settings.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/services/youtube_api_service.dart';

/// Servis ve model katmanı düzeltmelerinin regresyon testleri.
///
/// Buradaki her test, geri gelmesi kullanıcıya somut zarar veren bir davranışı
/// kilitler: uydurulan dosya boyutu, kilitlenen kuyruk, kaybolan çöp kaydı,
/// yanlış oynatma listesinden silme ve sessizce düşen silme isteği.
void main() {
  group('DownloadTask.formattedSizeInfo — boyut uydurulmaz', () {
    /// Süreden dosya boyutu tahmin etmek (~1.8 MB/dakika) 30 dakikalık 1080p bir
    /// videoya "~54.0 MB" yazıyordu; dosya gerçekte ~1 GB geliyor. Kullanıcı
    /// depolama kotasını bu uydurma sayıya göre planlayınca kota beklenmedik anda
    /// doluyor ve kuyruk hataya düşüyordu. Bilinmeyen boyut BOŞ döner.
    test('yalnız süre biliniyorsa boş döner, tahmin üretmez', () {
      final task = DownloadTask(
        id: '1',
        url: 'https://youtu.be/aaaaaaaaaaa',
        title: 'Otuz dakikalık video',
        durationSeconds: 1800,
      );

      expect(task.formattedSizeInfo, '');
      expect(task.formattedSizeInfo.contains('~'), isFalse);
    });

    /// Ölçülmüş değerler hâlâ gösterilmeli: düzeltme "hiçbir zaman boyut gösterme"
    /// demek değil, "ölçmediğini gösterme" demek.
    test('metadata baytı biliniyorsa gerçek boyut gösterilir', () {
      final task = DownloadTask(
        id: '2',
        url: 'https://youtu.be/bbbbbbbbbbb',
        title: 'Ölçülmüş video',
        durationSeconds: 1800,
        estimatedSizeBytes: 1073741824,
      );

      expect(task.formattedSizeInfo, '1.00 GB');
    });

    /// yt-dlp'den gelen toplam boyut metni her zaman tahminden önce gelir.
    test('yt-dlp toplam boyutu geldiyse o kullanılır', () {
      final task = DownloadTask(
        id: '3',
        url: 'https://youtu.be/ccccccccccc',
        title: 'İndirilen video',
        durationSeconds: 1800,
        totalSize: '980.4MiB',
      );

      expect(task.formattedSizeInfo, '980.4MiB');
    });
  });

  group('DownloadTask.copyWith — kaynak liste kopyada düşmez', () {
    /// sourcePlaylistUrl kopyada kaybolursa görev "elle eklenmiş tek video" gibi
    /// görünür; syncSavedPlaylists artık o görevi listeye ait saymaz ve listeden
    /// çıkarılmış bir video kuyrukta sonsuza kadar asılı kalır.
    test('kopya kaynak oynatma listesi bağlantısını korur', () {
      final task = DownloadTask(
        id: '4',
        url: 'https://youtu.be/ddddddddddd',
        title: 'Listeden gelen video',
        sourcePlaylistUrl: 'https://www.youtube.com/playlist?list=PL123',
      );

      final copy = task.copyWith(status: DownloadStatus.downloading);

      expect(copy.sourcePlaylistUrl, 'https://www.youtube.com/playlist?list=PL123');
      expect(copy.status, DownloadStatus.downloading);
    });
  });

  group('AppSettings.fromJson — alt sınır kuyruğu kilitlemesin', () {
    /// Kayıtta duran 0 (veya negatif) sınır kuyruğu KALICI kilitliyordu:
    /// processNextQueue "usedBytes >= maxBytes" ve
    /// "totalDurationSec >= maxDurationSec" kapılarında her görevi "kota doldu"
    /// diye hataya düşürüyor, kullanıcı ayarı elle düzeltene kadar tek bir
    /// indirme bile başlamıyordu.
    test('sıfır ve negatif değerler en küçük geçerli değere çekilir', () {
      final zero = AppSettings.fromJson({
        'maxStorageLimitGB': 0,
        'maxVideoDurationHours': 0,
      });
      expect(zero.maxStorageLimitGB, 1);
      expect(zero.maxVideoDurationHours, 1);

      final negative = AppSettings.fromJson({
        'maxStorageLimitGB': -5,
        'maxVideoDurationHours': -1,
      });
      expect(negative.maxStorageLimitGB, 1);
      expect(negative.maxVideoDurationHours, 1);
    });

    /// Geçerli değer aynen korunur, alan yoksa varsayılan kullanılır. Geçersiz
    /// değeri varsayılana YÜKSELTMEK kullanıcının hiç vermediği bir sınırı
    /// uydurmak olurdu; bu yüzden 0 -> 1, eksik -> 20.
    test('geçerli değer korunur, eksik değer varsayılana düşer', () {
      final valid = AppSettings.fromJson({
        'maxStorageLimitGB': 50,
        'maxVideoDurationHours': 12,
      });
      expect(valid.maxStorageLimitGB, 50);
      expect(valid.maxVideoDurationHours, 12);

      final missing = AppSettings.fromJson({});
      expect(missing.maxStorageLimitGB, 20);
      expect(missing.maxVideoDurationHours, 6);
    });
  });

  group('AppSettings eşitliği — gereksiz disk fırtınası engellenir', () {
    /// main.dart'taki ProxyProvider update'i her SettingsProvider VEYA
    /// LibraryProvider bildiriminde koşuyor. Değer eşitliği olmadan "ayar
    /// değişmedi" denemiyor, her indirme bitişinde onSettingsChanged ve onun
    /// üzerinden iki tam disk taraması (getUsedStorageBytes +
    /// scanDownloadedVideos) tetikleniyordu.
    test('aynı değerlere sahip iki nesne eşittir', () {
      const a = AppSettings(maxStorageLimitGB: 30, savedPlaylists: ['a', 'b']);
      final b = AppSettings(maxStorageLimitGB: 30, savedPlaylists: ['a', 'b']);

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    /// Liste ayrı bir örnek olsa bile İÇERİĞİ aynıysa eşit sayılmalı; aksi hâlde
    /// SettingsProvider her kopyada yeni liste ürettiği için kapı hiç tutmaz.
    test('farklı liste örneği ama aynı içerik eşit sayılır', () {
      final a = AppSettings(savedPlaylists: List<String>.from(['x']));
      final b = AppSettings(savedPlaylists: List<String>.from(['x']));

      expect(a == b, isTrue);
    });

    /// Gerçek değişiklik kaçırılmamalı: aksi hâlde kullanıcı Wi-Fi kısıtını
    /// açtığında kuyruk eski ayarla çalışmaya devam ederdi.
    test('gerçek değişiklik farkı korunur', () {
      const base = AppSettings();

      expect(base == base.copyWith(maxStorageLimitGB: 1), isFalse);
      expect(base == base.copyWith(networkMode: NetworkRestrictionMode.allNetworks), isFalse);
      expect(base == base.copyWith(savedPlaylists: const ['yeni']), isFalse);
    });
  });

  group('VideoItem.fromJson — bozuk tek kayıt tüm indeksi düşürmesin', () {
    /// StorageManager.loadTrashIndex listeyi tek "map" ile çözüyor ve herhangi bir
    /// istisna yakalanınca BOŞ liste dönüyor. Kayıtta double duran bir bayt değeri
    /// "as int?" cast'inde TypeError fırlatıyor, yani tek bozuk kayıt kullanıcının
    /// çöpteki 50 videosunu birden görünmez yapıyordu.
    test('sayısal alanlar double kaydedilmişse de okunur', () {
      final item = VideoItem.fromJson({
        'id': 'v1',
        'title': 'Video',
        'filePath': '/tmp/v1.mp4',
        'fileSizeBytes': 12345.0,
        'durationSeconds': 600.0,
        'downloadedAt': '2026-01-02T03:04:05.000',
      });

      expect(item.fileSizeBytes, 12345);
      expect(item.durationSeconds, 600);
      expect(item.downloadedAt.year, 2026);
    });

    /// Çözülemeyen tarih kaydı düşürmez ama UYDURULMAZ da: epoch döner, kayıt en
    /// eski gibi sıralanır. DateTime.now() dönmek kaydı taze göstererek sıralamayı
    /// ve tarih rozetini yalanlardı.
    test('bozuk tarih kaydı düşürmez, epoch olarak işaretlenir', () {
      final item = VideoItem.fromJson({
        'id': 'v2',
        'title': 'Video',
        'filePath': '/tmp/v2.mp4',
        'fileSizeBytes': 1,
        'downloadedAt': 'bozuk-tarih',
      });

      expect(item.downloadedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('YoutubeApiService.extractPlaylistId — yanlış listeden silme yok', () {
    /// Yanlış çıkarılan kimlik, kullanıcının BAŞKA bir oynatma listesinden video
    /// silinmesi demektir ve geri alınamaz. Kimlik yoksa null dönmeli ki silme
    /// hiç denenmesin.
    test('list parametresi olan bağlantılardan kimlik çıkarılır', () {
      expect(
        YoutubeApiService.extractPlaylistId(
            'https://www.youtube.com/playlist?list=PLabc123'),
        'PLabc123',
      );
      expect(
        YoutubeApiService.extractPlaylistId(
            'https://www.youtube.com/watch?v=aaaaaaaaaaa&list=PLxyz'),
        'PLxyz',
      );
    });

    test('liste içermeyen veya boş bağlantı null döner', () {
      expect(YoutubeApiService.extractPlaylistId(null), isNull);
      expect(YoutubeApiService.extractPlaylistId(''), isNull);
      expect(YoutubeApiService.extractPlaylistId('https://youtu.be/aaaaaaaaaaa'),
          isNull);
      expect(
        YoutubeApiService.extractPlaylistId('https://www.youtube.com/@kanal'),
        isNull,
      );
    });
  });

  group('YoutubeApiService.classifyDeletionFailure — sessiz kayıp yok', () {
    /// Eskiden her hata debugPrint ile yutuluyor ve istek kuyruktan zaten çıkmış
    /// olduğu için BİR DAHA denenmiyordu: şebekesini kaybeden kullanıcının 20
    /// videosu YouTube listesinden hiç silinmiyor, uygulama ise silmiş gibi
    /// davranıyordu.
    test('ağ hatası geçici sayılır ve tekrar denenir', () {
      expect(
        YoutubeApiService.classifyDeletionFailure(
            const SocketException('ağ yok')),
        DeletionFailureKind.transient,
      );
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(401, 'token süresi doldu')),
        DeletionFailureKind.transient,
      );
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(403, 'quotaExceeded')),
        DeletionFailureKind.transient,
      );
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(429, 'rate limit')),
        DeletionFailureKind.transient,
      );
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(500, 'sunucu hatası')),
        DeletionFailureKind.transient,
      );
    });

    /// 404 ve 400 tekrar denemekle düzelmez; kuyrukta tutmak boşuna kota yakar
    /// (her liste sorgusu ayrı birim harcar).
    test('kalıcı hatalar tekrar denenmez', () {
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(404, 'not found')),
        DeletionFailureKind.permanent,
      );
      expect(
        YoutubeApiService.classifyDeletionFailure(
            yt.DetailedApiRequestError(400, 'bad request')),
        DeletionFailureKind.permanent,
      );
    });

    /// Deneme tavanı olmadan geçici sayılan kalıcı bir 403 (liste artık bu hesabın
    /// değil) kuyruğu sonsuz döndürürdü.
    test('deneme tavanı sonludur', () {
      expect(YoutubeApiService.maxDeletionAttempts, greaterThan(1));
      expect(YoutubeApiService.maxDeletionAttempts, lessThanOrEqualTo(5));
    });
  });
}
