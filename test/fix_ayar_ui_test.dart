import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/playlist_entry.dart';
import 'package:offlineyoutube/ui/screens/playlist_selection_screen.dart';
import 'package:offlineyoutube/ui/theme/amoled_theme.dart';

/// Ayar ve arayüz turunda düzeltilen davranışları koruyan testler.
///
/// Kapsam bilinçli olarak seçim ekranıyla sınırlı: bu ekran tek başına
/// çalışabilen (sağlayıcısız, kanalsız) tek ekran, dolayısıyla kırmızı olması
/// gerektiğinde gerçekten kırmızı olabilecek tek yer.
PlaylistFetchResult _result(int count) => PlaylistFetchResult(
      entries: List.generate(
        count,
        (i) => PlaylistEntry(url: 'https://youtu.be/video$i', title: 'Video $i'),
      ),
      totalCount: count,
      sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
    );

Widget _app(PlaylistFetchResult result, {double bottomInset = 0}) {
  return MaterialApp(
    theme: AmoledTheme.themeData,
    home: Builder(
      builder: (context) => MediaQuery(
        // Sistem gezinme çubuğu insetini taklit eder. MediaQuery MaterialApp'in
        // İÇİNDE olmalı: WidgetsApp kendi MediaQuery'sini dışarıdakinin üstüne
        // kurar ve dışarıda verilen inset ekrana hiç ulaşmaz.
        data: MediaQuery.of(context)
            .copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
        child: PlaylistSelectionScreen(result: result),
      ),
    ),
  );
}

void main() {
  group('Seçim ekranı alt aksiyon çubuğu', () {
    testWidgets('sistem gezinme çubuğunun altında kalmaz', (tester) async {
      // NEDEN: Alt çubuk Scaffold'un bottomNavigationBar'ı değil, Column'un son
      // çocuğu. Sabit 14 px alt boşluk 3 düğmeli gezinme çubuğunu telafi
      // etmiyordu; "indir" düğmesi sistem çubuğunun altında kalıyor ve dokunuş
      // uygulamaya hiç ulaşmıyordu, yani kullanıcı seçimini onaylayamıyordu.
      const inset = 48.0;
      await tester.pumpWidget(_app(_result(3), bottomInset: inset));

      final scaffoldBottom = tester.getRect(find.byType(Scaffold)).bottom;
      final buttonBottom =
          tester.getRect(find.widgetWithText(ElevatedButton, '3 videoyu indir')).bottom;

      expect(
        buttonBottom,
        lessThanOrEqualTo(scaffoldBottom - inset),
        reason: 'İndir düğmesi sistem gezinme çubuğu alanına taşıyor, '
            'dokunulamaz hâle gelir (SafeArea kaldırılmış olabilir)',
      );
    });

    testWidgets('inset yokken de ekranın içinde kalır', (tester) async {
      // NEDEN: SafeArea eklenirken çubuğun inset'siz cihazlarda taşmadığını da
      // sabitliyoruz; aksi hâlde düzeltme başka bir taşma hatası doğurabilir.
      await tester.pumpWidget(_app(_result(3)));

      final scaffoldBottom = tester.getRect(find.byType(Scaffold)).bottom;
      final buttonBottom =
          tester.getRect(find.widgetWithText(ElevatedButton, '3 videoyu indir')).bottom;

      expect(buttonBottom, lessThanOrEqualTo(scaffoldBottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('Hızlı seçim çipi', () {
    testWidgets('etiketi mevcut seçimi sileceğini söyler ve öyle davranır',
        (tester) async {
      // NEDEN: Ekran varsayılan olarak DOLU geliyor (yeni videolar seçili).
      // "İlk 10" etiketi eklemeyi ima ederken aslında seçimi sıfırlayıp yerine
      // ilk 10'u koyuyordu ve geri alma yoktu. Etiket ile davranış tek testte
      // birlikte sabitlenir: biri değişirse test kırmızı olur.
      await tester.pumpWidget(_app(_result(12)));

      expect(find.text('12 videoyu indir'), findsOneWidget);

      await tester.tap(find.text('Yalnız İlk 10'));
      await tester.pump();

      expect(find.text('10 videoyu indir'), findsOneWidget,
          reason: 'çip seçimi değiştirmeli (eklemeli değil), '
              'etiketi de bunu vaat ediyor');
    });
  });

  group('Onay çıktısı', () {
    testWidgets('kuyruğa seçim sırası değil LİSTE sırası döner',
        (tester) async {
      // NEDEN: Seçim ekranı artık ana ekrandan gerçekten açılıyor, dolayısıyla
      // döndürdüğü sıra doğrudan indirme sırası oluyor. Kullanıcı 3. videoyu
      // önce işaretlese bile ders serisi/podcast doğru sırada inmeli.
      const result = PlaylistFetchResult(
        entries: [
          PlaylistEntry(url: 'a', title: 'Video 0', alreadyPresent: true),
          PlaylistEntry(url: 'b', title: 'Video 1', alreadyPresent: true),
          PlaylistEntry(url: 'c', title: 'Video 2', alreadyPresent: true),
        ],
        totalCount: 3,
        sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
      );

      List<PlaylistEntry>? popped;
      await tester.pumpWidget(MaterialApp(
        theme: AmoledTheme.themeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context)
                      .push<List<PlaylistEntry>>(MaterialPageRoute(
                    builder: (_) => const PlaylistSelectionScreen(result: result),
                  ));
                },
                child: const Text('ekranı aç'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('ekranı aç'));
      await tester.pumpAndSettle();

      // Ters sırada işaretle: önce sondaki, sonra baştaki.
      await tester.tap(find.text('Video 2'));
      await tester.pump();
      await tester.tap(find.text('Video 0'));
      await tester.pump();

      await tester.tap(find.text('2 videoyu indir'));
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.map((e) => e.title).toList(), ['Video 0', 'Video 2']);
    });
  });

  group('Varsayılan seçim', () {
    testWidgets('zaten kuyrukta veya kütüphanede olanlar işaretli gelmez',
        (tester) async {
      // NEDEN: Seçim ekranının varlık sebebi listenin sessizce kuyruğa
      // dökülmemesi. Varsayılan seçim yalnız YENİ videoları içermeli, aksi
      // hâlde kullanıcı farkında olmadan mevcut videoları yeniden kuyruğa alır.
      const result = PlaylistFetchResult(
        entries: [
          PlaylistEntry(url: 'a', title: 'Video A', alreadyPresent: true),
          PlaylistEntry(url: 'b', title: 'Video B'),
          PlaylistEntry(url: 'c', title: 'Video C', alreadyPresent: true),
        ],
        totalCount: 3,
        sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
      );

      await tester.pumpWidget(_app(result));

      expect(find.text('1 videoyu indir'), findsOneWidget);
    });
  });
}
