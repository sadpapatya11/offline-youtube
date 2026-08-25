import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Duraklatma yarışının GERÇEK akış üzerinden davranış testi.
///
/// progress_event_guard_test.dart saf karar fonksiyonunu doğrular, ama kapının olay
/// işleyicisine bağlı olduğunu kanıtlamaz: kapı satırı akıştan silinse bile o testler
/// yeşil kalır. Bu dosya tam olarak o boşluğu kapatır ve native olay akışını taklit
/// ederek görevin diriltilmediğini doğrudan ölçer.
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

  const olayKanali = EventChannel('com.offlineyoutube/download_events');
  const yontemKanali = MethodChannel('com.offlineyoutube/downloader');
  // DownloadQueueManager bir singleton ve olay aboneliği init() içinde BİR KEZ kurulur.
  // Mock kanalı her testte yeniden kurmak, aboneliğin eski handler'da kalmasına ve
  // olayların hiç teslim edilmemesine yol açıyordu; bu da "değişmemeli" diyen testleri
  // yanlış yeşil yapardı. Bu yüzden kanal ve init tek sefer kurulur.
  final sahteKanal = _SahteOlayKanali();
  late DownloadQueueManager manager;

  DownloadTask gorevEkle(String id, DownloadStatus durum) {
    final t = DownloadTask(
      id: id,
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      title: 'Test Videosu',
      status: durum,
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
    // Olay işleyicisi bilinmeyen görev için cancelDownload çağırabiliyor; sessizce yutulsun.
    messenger.setMockMethodCallHandler(yontemKanali, (call) async => true);

    manager = DownloadQueueManager.instance;
    manager.isQueuePaused = true; // kuyruk motorunun kendi kendine iş başlatmasını engelle
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
        reason: 'bu kırmızıysa diğer testler olay almadan geçiyor demektir, hepsi yanlış yeşildir');
  });

  test('duraklatılmış göreve gelen gecikmiş progress olayı görevi DİRİLTMEZ', () async {
    final gorev = gorevEkle('gorev-1', DownloadStatus.paused);

    sahteKanal.olayGonder({
      'type': 'progress',
      'taskId': 'gorev-1',
      'progress': 42.0,
      'speed': '3.1MiB/s',
    });
    await olayIsle();

    expect(gorev.status, DownloadStatus.paused,
        reason: 'duraklatılan görev sahte downloading durumuna dönerse kuyruk kalıcı kilitlenir');
    expect(manager.activeTaskId, isNull,
        reason: 'activeTaskId yeniden dolarsa processNextQueue her çağrıda erken döner');
  });

  test('iptal edilmiş göreve gelen artık olay durumu bozmaz', () async {
    final gorev = gorevEkle('gorev-2', DownloadStatus.cancelled);

    sahteKanal.olayGonder({'type': 'progress', 'taskId': 'gorev-2', 'progress': 90.0});
    await olayIsle();

    expect(gorev.status, DownloadStatus.cancelled);
    expect(manager.activeTaskId, isNull);
  });

  test('normal akış bozulmadı: indirilen göreve gelen progress uygulanır', () async {
    final gorev = gorevEkle('gorev-3', DownloadStatus.downloading);

    sahteKanal.olayGonder({
      'type': 'progress',
      'taskId': 'gorev-3',
      'progress': 55.0,
      'speed': '2.0MiB/s',
    });
    await olayIsle();

    expect(gorev.status, DownloadStatus.downloading);
    expect(gorev.progress, 55.0);
    expect(manager.activeTaskId, 'gorev-3');
  });

  test("kuyruktaki göreve gelen 'started' olayı normal biçimde uygulanır", () async {
    final gorev = gorevEkle('gorev-4', DownloadStatus.queued);

    sahteKanal.olayGonder({'type': 'started', 'taskId': 'gorev-4', 'progress': 0.0});
    await olayIsle();

    expect(gorev.status, DownloadStatus.downloading);
    expect(manager.activeTaskId, 'gorev-4');
  });
}
