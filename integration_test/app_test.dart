import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offlineyoutube/services/native_bridge.dart'; // package name should match pubspec
import 'package:offlineyoutube/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Runtime Tests', () {
    testWidgets('Verify YT-DLP Network / BotGuard connectivity', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      const testUrl = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
      bool success = false;
      String? errorMessage;
      
      try {
        final meta = await NativeBridge.instance.fetchMetadata(testUrl);
        expect(meta, isNotNull);
        expect(meta['title'], isNotNull);
        success = true;
      } catch (e) {
        errorMessage = e.toString();
      }
      
      expect(success, isTrue, reason: 'YT-DLP Failed to fetch metadata (Possible 403 BotGuard or player_client issue). Error: $errorMessage');
    });
  });
}
