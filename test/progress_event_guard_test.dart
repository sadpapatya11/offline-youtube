import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';

/// Duraklatma yarışını ve kalıcı kuyruk kilidini korur.
///
/// Kök sorun (2026-08-25 denetimi, yüksek bulgu):
/// Native olay işleyicisi 'started' ve 'progress' olaylarını görevin O ANKİ durumunu
/// hiç sormadan uyguluyordu: durumu koşulsuz `downloading` yapıp `activeTaskId`
/// alanını dolduruyordu.
///
/// Kullanıcı indirmeyi duraklattığında pauseTask görevi `paused` yapar ve
/// activeTaskId'yi temizler, ama yt-dlp süreci ölmeden önce bir ilerleme satırı daha
/// teslim edebilir. Gecikmiş o tek olay görevi sahte biçimde `downloading` durumuna
/// geri döndürür ve activeTaskId'yi yeniden doldurur.
///
/// Sonuç kalıcı kilittir: processNextQueue içindeki
///   `if (activeTaskId != null && tasks[i].status == downloading) return;`
/// kapısı artık her çağrıda erken döner. Native süreç zaten öldüğü için yeni bir olay
/// da gelmez, yani durum kendiliğinden ASLA düzelmez ve kuyruk bir daha ilerlemez.
void main() {
  group('İlerleme olayı yalnız aktif olabilecek görevlere uygulanır', () {
    test('duraklatılmış göreve gelen artık ilerleme olayı YOK SAYILIR', () {
      expect(
        DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.paused),
        isFalse,
        reason: 'yoksa kullanıcının duraklattığı görev sahte downloading olur ve kuyruk kalıcı kilitlenir',
      );
    });

    test('iptal edilmiş ve tamamlanmış görevler diriltilmez', () {
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.cancelled), isFalse);
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.completed), isFalse);
    });

    test('hata durumundaki göreve gelen artık olay durumu bozmaz', () {
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.error), isFalse);
    });

    test('normal indirme akışı etkilenmez', () {
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.downloading), isTrue);
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.queued), isTrue,
          reason: "'started' olayı görevi queued durumundan downloading durumuna geçirir");
      expect(DownloadQueueManager.shouldApplyProgressEvent(DownloadStatus.fetchingMetadata), isTrue);
    });

    test('kapı her durumu açıkça sınıflandırır (yeni durum eklenirse burası kırmızı olur)', () {
      final kabul = DownloadStatus.values
          .where(DownloadQueueManager.shouldApplyProgressEvent)
          .toSet();
      expect(kabul, {
        DownloadStatus.queued,
        DownloadStatus.fetchingMetadata,
        DownloadStatus.downloading,
      });
    });
  });
}
