import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/providers/download_provider.dart';
import 'package:offlineyoutube/providers/library_provider.dart';
import 'package:offlineyoutube/providers/settings_provider.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';
import 'package:offlineyoutube/ui/screens/queue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kuyruk motorunun yayınladığı "sessiz durma" sinyallerinin gerçekten bir
/// ekrana ULAŞTIĞINI kanıtlar.
///
/// Kök sorun (2026-08-26 entegrasyon turu): denetim turunda _failNextTaskIfAny
/// kaldırılıp yerine _blockQueue geldi. Bu doğru bir düzeltmeydi (geçici ağ ya
/// da kota engeli artık görevi kalıcı hataya yakmıyor), ama nedeni yazdığı
/// `blockReason` alanını hiçbir sağlayıcı ve hiçbir ekran OKUMUYORDU. Sonuç:
/// eskiden kırmızı bir hata satırı gören kullanıcı artık hiçbir şey görmüyor,
/// kuyruk sebepsiz donmuş gibi duruyordu. Aynı sessizlik, açılışta çözülemeyip
/// düşürülen görev kayıtları (`droppedTaskCount`) için de geçerliydi.
///
/// Bu bekçi, geçidi kaldıran bir değişiklikte kırmızı yanar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadQueueManager manager;

  DownloadTask bekleyenGorev(String id) => DownloadTask(
        id: id,
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Görev $id',
        status: DownloadStatus.queued,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = DownloadQueueManager.instance;
    manager.tasks.clear();
    manager.activeTaskId = null;
    manager.blockReason = null;
    manager.droppedTaskCount = 0;
    manager.queueRecordUnreadable = false;
  });

  /// Ekranı kurar, SONRA motor durumunu uygular.
  ///
  /// Sıra önemli: DownloadProvider constructor'ı `_manager.init()` çağırır ve
  /// init içindeki _loadTasksFromStorage `droppedTaskCount` ile
  /// `queueRecordUnreadable` bayraklarını SIFIRLAR. Bayrakları kurulumdan önce
  /// yazmak, testi kendi kurduğu durumu silen bir yarışa sokar.
  Future<void> ekraniKur(
    WidgetTester tester, {
    void Function()? motorDurumu,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => LibraryProvider()),
          ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ],
        child: const MaterialApp(home: QueueScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    if (motorDurumu != null) {
      motorDurumu();
      manager.notifyListeners();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('engel nedeni, bekleyen görev varken kullanıcıya gösterilir',
      (WidgetTester tester) async {
    await ekraniKur(tester, motorDurumu: () {
      manager.tasks.add(bekleyenGorev('a'));
      manager.blockReason = 'Depolama kotası doldu (20 GB).';
    });

    expect(
      find.text('Depolama kotası doldu (20 GB).'),
      findsOneWidget,
      reason: 'blockReason ekrana taşınmazsa kuyruk sebepsiz donmuş görünür',
    );
  });

  testWidgets('kuyrukta bekleyen iş yokken engel nedeni gösterilmez',
      (WidgetTester tester) async {
    // Soğuk açılışta "Ayarlar henüz yüklenmedi" nedeni yazılıyor; ortada
    // bekleyen indirme yokken bunu göstermek olmayan bir sorunu bildirmektir.
    await ekraniKur(tester, motorDurumu: () {
      manager.blockReason = 'Ayarlar henüz yüklenmedi, kuyruk bekletiliyor.';
    });

    expect(
      find.text('Ayarlar henüz yüklenmedi, kuyruk bekletiliyor.'),
      findsNothing,
    );
  });

  testWidgets('düşen görev sayısı bildirilir ve kapatılabilir',
      (WidgetTester tester) async {
    await ekraniKur(tester, motorDurumu: () {
      manager.droppedTaskCount = 3;
    });

    expect(find.textContaining('3 görev kaydı okunamadığı için'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(
      find.textContaining('3 görev kaydı okunamadığı için'),
      findsNothing,
      reason: 'kapatma bayrağı temizlemezse uyarı her açılışta geri gelir',
    );
  });

  testWidgets('kaydın tamamı okunamadıysa ayrı ve daha ağır uyarı çıkar',
      (WidgetTester tester) async {
    await ekraniKur(tester, motorDurumu: () {
      manager.queueRecordUnreadable = true;
      manager.droppedTaskCount = 0;
    });

    expect(find.textContaining('Kayıtlı kuyruk okunamadı'), findsOneWidget);
  });

  testWidgets('uyarı yokken bant hiç çizilmez', (WidgetTester tester) async {
    await ekraniKur(tester, motorDurumu: () {
      manager.tasks.add(bekleyenGorev('a'));
    });

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });
}
