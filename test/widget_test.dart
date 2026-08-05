import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OfflineYoutubeApp());
    expect(find.text('OFFLINE YOUTUBE'), findsOneWidget);
    expect(find.text('Ana Sayfa'), findsOneWidget);
    expect(find.text('İndirilenler'), findsOneWidget);
    expect(find.text('Kuyruk'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
  });
}
