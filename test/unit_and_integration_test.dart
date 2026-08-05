import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/main.dart';
import 'package:offlineyoutube/models/app_settings.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/ui/theme/amoled_theme.dart';

void main() {
  group('Models & Logic Tests', () {
    test('AppSettings serialization and defaults', () {
      const settings = AppSettings();
      expect(settings.maxStorageLimitGB, 20);
      expect(settings.maxVideoDurationHours, 6);
      expect(settings.networkMode, NetworkRestrictionMode.allNetworks);

      final json = settings.toJson();
      final fromJson = AppSettings.fromJson(json);
      expect(fromJson.maxStorageLimitGB, 20);
      expect(fromJson.maxVideoDurationHours, 6);
      expect(fromJson.networkMode, NetworkRestrictionMode.allNetworks);

      final modified = settings.copyWith(
        maxStorageLimitGB: 50,
        maxVideoDurationHours: 12,
        networkMode: NetworkRestrictionMode.anyWifi,
      );
      expect(modified.maxStorageLimitGB, 50);
      expect(modified.maxVideoDurationHours, 12);
      expect(modified.networkMode, NetworkRestrictionMode.anyWifi);
    });

    test('VideoItem formatting logic', () {
      final video = VideoItem(
        id: 'v123',
        title: 'Flutter Architecture Deep Dive',
        filePath: '/storage/emulated/0/Download/.offlineyoutube/v123.mp4',
        fileSizeBytes: 1048576 * 250, // 250 MB
        downloadedAt: DateTime(2026, 1, 1),
      );

      expect(video.formattedSize, '250.0 MB');
    });

    test('DownloadTask progress and ETA formatting', () {
      final task = DownloadTask(
        id: '1001',
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        status: DownloadStatus.downloading,
        progress: 45.5,
        speed: '12.4 MB/s',
        etaSeconds: 125, // 2m 5s
      );

      expect(task.formattedEta, '02:05');
      expect(task.status, DownloadStatus.downloading);
    });
  });

  group('AMOLED Theme & UI Structure Tests', () {
    test('AmoledTheme tokens validation', () {
      final theme = AmoledTheme.themeData;
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('Full App Navigation and Tab switching', (WidgetTester tester) async {
      await tester.pumpWidget(const OfflineYoutubeApp());
      await tester.pump(const Duration(milliseconds: 200));

      // Check initial screen
      expect(find.text('OFFLINE YOUTUBE'), findsWidgets);
      expect(find.text('Otomatik İndirme & Senkronizasyon'), findsOneWidget);

      // Tap Downloads tab
      await tester.tap(find.byIcon(Icons.video_library_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRİLENLER'), findsOneWidget);

      // Tap Queue tab
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRME KUYRUĞU'), findsOneWidget);

      // Tap Settings tab
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('AYARLAR VE KISITLAMALAR'), findsOneWidget);
      expect(find.text('Depolama Kotası Yöneticisi'), findsOneWidget);
      expect(find.text('Maksimum Video Uzunluğu'), findsOneWidget);
      expect(find.text('Ağ ve Bağlantı Kuralı'), findsOneWidget);
    });
  });
}
