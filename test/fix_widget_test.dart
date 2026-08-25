import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/ui/widgets/amoled_fast_scroller.dart';
import 'package:offlineyoutube/ui/widgets/download_tile.dart';
import 'package:offlineyoutube/ui/widgets/video_tile.dart';
import 'package:offlineyoutube/utils/snackbar_helper.dart';

void main() {
  group('AmoledFastScroller sürükleme oranı', () {
    test('yakalama noktası sürükleme boyunca korunur', () {
      // Oran, parmağın mutlak konumundan değil kat edilen mesafeden türer.
      // Eski hesap (localY / trackHeight) thumb'ın konumlandırıldığı tabandan
      // (trackHeight eksi 48) farklı bir taban kullandığı için parmakla
      // gösterge arasında büyüyen bir kayma bırakıyordu.
      expect(
        fastScrollerDragRatio(
          startRatio: 0.25,
          deltaY: 100,
          effectiveTrackHeight: 500,
        ),
        closeTo(0.45, 1e-9),
      );

      // Geri sürüklemek oranı simetrik biçimde küçültür.
      expect(
        fastScrollerDragRatio(
          startRatio: 0.45,
          deltaY: -100,
          effectiveTrackHeight: 500,
        ),
        closeTo(0.25, 1e-9),
      );
    });

    test('oran her zaman 0 ile 1 arasında kalır', () {
      // İz dışına taşan bir sürükleme listeyi maxScrollExtent ötesine
      // götürmemeli; jumpTo aralık dışı bir değerle çağrılırsa kaydırma
      // pozisyonu bozulur.
      expect(
        fastScrollerDragRatio(
          startRatio: 0.9,
          deltaY: 5000,
          effectiveTrackHeight: 500,
        ),
        1.0,
      );
      expect(
        fastScrollerDragRatio(
          startRatio: 0.1,
          deltaY: -5000,
          effectiveTrackHeight: 500,
        ),
        0.0,
      );
    });

    test('iz yüksekliği sıfırken sıfıra bölme yapılmaz', () {
      // Çok kısa bir görünümde (klavye açıkken kalan alan) effectiveTrackHeight
      // sıfır olabilir. Bölme yapılırsa oran NaN olur ve jumpTo çöker.
      final ratio = fastScrollerDragRatio(
        startRatio: 0.3,
        deltaY: 120,
        effectiveTrackHeight: 0,
      );
      expect(ratio, 0.3);
      expect(ratio.isNaN, isFalse);
    });
  });

  testWidgets('kaydırılamayan listede hızlı kaydırıcı göstergesi çizilmez',
      (WidgetTester tester) async {
    // Arama listeyi tek öğeye daralttığında ya da liste zaten ekrana sığdığında
    // gösterge çizilmemeli: eskiden thumb her koşulda ağaçtaydı ve sürüklenince
    // parmağı takip edip hiçbir şeyi kaydırmıyordu, yani sahte bir kontroldü.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmoledFastScroller(
            controller: controller,
            child: ListView.builder(
              controller: controller,
              itemCount: 2,
              itemExtent: 50,
              itemBuilder: (context, index) => Text('Öğe $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.position.maxScrollExtent, 0);
    expect(
      find.descendant(
        of: find.byType(AmoledFastScroller),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
    );
  });

  testWidgets('liste başındayken daralırsa gösterge yine de kaybolur',
      (WidgetTester tester) async {
    // En sinsi hâli: kullanıcı listenin başındayken arama yazıp listeyi
    // kaydırılamaz hale getiriyor. ScrollController yalnızca piksel
    // değiştiğinde haber verdiği için (piksel zaten sıfır) tek bir bildirim
    // gelmiyordu; gösterge ekranda kalıyor, sürüklenince parmağı takip edip
    // hiçbir şeyi kaydırmıyordu. Ölçü değişimi ScrollMetricsNotification ile
    // yakalanmazsa bu bekçi kırmızı yanar.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    var itemCount = 100;
    late StateSetter setOuterState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return AmoledFastScroller(
                controller: controller,
                child: ListView.builder(
                  controller: controller,
                  itemCount: itemCount,
                  itemExtent: 50,
                  itemBuilder: (context, index) => Text('Öğe $index'),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Önce kaydırıp göstergeyi canlandır, sonra tam başa dön: gösterge artık
    // ağaçta ve oranı sıfır, yani bundan sonrası piksel değiştirmez.
    controller.jumpTo(500);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    final thumbFinder = find.descendant(
      of: find.byType(AmoledFastScroller),
      matching: find.byType(AnimatedContainer),
    );
    expect(thumbFinder, findsOneWidget);

    setOuterState(() {
      itemCount = 2;
    });
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 0);
    expect(controller.position.maxScrollExtent, 0);
    expect(thumbFinder, findsNothing);
  });

  testWidgets('sağ kenardan yapılan normal kaydırma listeyi ışınlamaz',
      (WidgetTester tester) async {
    // Telefonu sağ eliyle tutan kullanıcı ekranın sağ kenarından listeyi
    // kaydırmak istiyor. Eskiden sağ kenardaki 32 piksellik şerit boydan boya
    // uzandığı ve dokunulan yere anında ışınladığı için liste bir tutam
    // kaymak yerine ortalara fırlıyordu (aynı nedenle aşağı çekerek yenileme
    // de hiç tetiklenmiyordu). Yakalama alanı artık yalnızca göstergenin
    // çevresi kadar.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmoledFastScroller(
            controller: controller,
            child: ListView.builder(
              controller: controller,
              itemCount: 100,
              itemExtent: 50,
              itemBuilder: (context, index) => Text('Öğe $index'),
            ),
          ),
        ),
      ),
    );

    controller.jumpTo(1000);
    await tester.pumpAndSettle();

    // Gösterge bu noktada iz üzerinde yaklaşık 132 pikselde duruyor; 400
    // pikselden başlayan dokunuş ona uzak, yani listeye ait olmalı.
    final topRight = tester.getTopRight(find.byType(AmoledFastScroller));
    await tester.dragFrom(topRight + const Offset(-10, 400), const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(1000));
    expect(controller.offset, lessThan(1500));
  });

  testWidgets('360 dp genişlikte indirme kartı taşmaz',
      (WidgetTester tester) async {
    // En yaygın Android genişliğinde, indirilmekte olan bir görev süre ve boyut
    // bilgisiyle birlikte gösterildiğinde satır taşıyordu: debug'da sarı siyah
    // taşma bandı, release'de boyut bilgisinin aksiyon butonlarının altına
    // girmesi. Taşma, çizim sırasında FlutterError olarak raporlandığı için
    // takeException ile yakalanır.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final task = DownloadTask(
      id: 't1',
      url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
      title: 'Uzun Başlıklı Bir Test Videosu Bölüm Bir',
      status: DownloadStatus.downloading,
      progress: 45.2,
      speed: '2.45MiB/s',
      etaSeconds: 332,
      durationSeconds: 3932,
      downloadedSize: '45.2 MB',
      totalSize: '120.5 MB',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [DownloadTile(task: task)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('seçim modunda bağlantı satırına dokunmak videoyu seçer',
      (WidgetTester tester) async {
    // Kullanıcı çoklu seçim modunda. Kartın altındaki uzun bağlantı satırına
    // denk gelen dokunuş, eskiden videoyu seçmek yerine uygulamayı arka plana
    // atıp YouTube'u açıyordu; kullanıcı geri döndüğünde o video seçilmemiş
    // oluyordu. Seçim modunda bağlantının kapalı olması, dokunuşun dıştaki
    // karta geçmesini ve seçimin değişmesini sağlar.
    const url = 'https://www.youtube.com/watch?v=abcdefghijk';
    final video = VideoItem(
      id: 'v1',
      title: 'Test Videosu',
      filePath: '/tmp/yok.mp4',
      fileSizeBytes: 1024 * 1024,
      downloadedAt: DateTime(2026, 1, 1),
      sourceUrl: url,
    );

    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: VideoTile(
              video: video,
              isSelectionMode: true,
              isSelected: false,
              onTap: () => tapCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(url));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('KAPAT, gösteren ekran kapandıktan sonra hata atmadan çalışır',
      (WidgetTester tester) async {
    // Snackbar'ı gösteren ekran (alt sayfa veya ikinci rota) kapandıktan sonra
    // snackbar ekranda kalmaya devam eder. KAPAT eylemi gösteren ekranın
    // context'ini yakaladığı için basıldığında ağaçtan kalkmış eleman üzerinden
    // arama yapılıyor ve "deactivated widget's ancestor" hatası atılıyordu.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (rootContext) => Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push<void>(
                    rootContext,
                    MaterialPageRoute<void>(
                      builder: (innerContext) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed: () {
                              SnackbarHelper.show(innerContext, 'mesaj');
                              Navigator.pop(innerContext);
                            },
                            child: const Text('goster'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('git'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('git'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('goster'));
    await tester.pumpAndSettle();

    expect(find.text('mesaj'), findsWidgets);

    await tester.tap(find.text('KAPAT'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('mesaj'), findsNothing);
  });

  testWidgets('seçim modunda kart, seçili durumunu erişilebilirlik ağacına yazar',
      (WidgetTester tester) async {
    // Seçim yalnızca yeşil çerçeve ve onay simgesiyle anlatılıyordu; ekran
    // okuyucu kullanan biri on iki videoyu işaretlerken hangisinin seçili
    // olduğunu hiç duymuyor, yanlış videoyu silme riskiyle ilerliyordu.
    // Semantics(selected: ...) sarmalı kaldırılırsa bayrak hiç yazılmaz
    // (Tristate.none, yani null) ve bu bekçi kırmızı yanar.
    // addTearDown ile atmak GEÇ kalıyor: flutter_test, test gövdesi biter
    // bitmez (tearDown geri çağrılarından ÖNCE) açık SemanticsHandle var mı
    // diye bakıyor ve "A SemanticsHandle was active" diyerek testi
    // patlatıyor. Bu yüzden handle gövdenin sonunda elle atılıyor.
    final handle = tester.ensureSemantics();

    final video = VideoItem(
      id: 'v2',
      title: 'Seçili Test Videosu',
      filePath: '/tmp/yok2.mp4',
      fileSizeBytes: 2 * 1024 * 1024,
      downloadedAt: DateTime(2026, 1, 2),
      sourceUrl: 'https://www.youtube.com/watch?v=ccccccccccc',
    );

    Future<void> pumpTile({required bool isSelected}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: VideoTile(
                video: video,
                isSelectionMode: true,
                isSelected: isSelected,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpTile(isSelected: true);
    expect(
      tester.getSemantics(find.byType(VideoTile)).flagsCollection.isSelected
          .toBoolOrNull(),
      isTrue,
    );

    // Seçili olmayan kart da bayrağı taşımalı: bayrak hiç yazılmazsa okuyucu
    // "seçili değil" diyemez, kullanıcı yine karanlıkta kalır.
    await pumpTile(isSelected: false);
    expect(
      tester.getSemantics(find.byType(VideoTile)).flagsCollection.isSelected
          .toBoolOrNull(),
      isFalse,
    );

    handle.dispose();
  });

  testWidgets('kuyruk kartındaki küçük resim kutu boyutuna göre çözülür',
      (WidgetTester tester) async {
    // YouTube'un verdiği küçük resim 1280x720 olabiliyor ve tam çözünürlükte
    // çözülünce kare tamponu yaklaşık 3.5 MB tutuyor. 64x48'lik bir kutu için
    // bu israf, elli görevlik bir kuyrukta ImageCache'in 100 MB'lık varsayılan
    // sınırını doldurup düşük bellekli cihazda kare atlamalarına yol açıyordu.
    // cacheWidth kaldırılırsa Image.network kaynağı ResizeImage ile sarmalamaz
    // ve bu bekçi kırmızı yanar.
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final task = DownloadTask(
      id: 't2',
      url: 'https://www.youtube.com/watch?v=bbbbbbbbbbb',
      title: 'Küçük resimli görev',
      status: DownloadStatus.queued,
      thumbnail: 'https://i.ytimg.com/vi/bbbbbbbbbbb/maxresdefault.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [DownloadTile(task: task)],
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    // 64 dp'lik kutunun iki katı, cihaz piksel oranıyla çarpılır.
    expect((image.image as ResizeImage).width, 256);

    // Test ortamında ağ isteği 400 ile biter; bu hata errorBuilder'a düşer ve
    // burada konumuz değildir, testi kirletmemesi için tüketiliyor.
    tester.takeException();
  });
}
