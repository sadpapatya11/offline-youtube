import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/main.dart';
import 'package:offlineyoutube/models/app_settings.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/trashed_video_item.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/providers/download_provider.dart';
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

    test('TrashedVideoItem 24-hour expiration calculation', () {
      final video = VideoItem(
        id: 'v999',
        title: 'Sample Trashed Video',
        filePath: '/storage/emulated/0/Download/.offlineyoutube/.trash/v999.mp4',
        fileSizeBytes: 1048576 * 100,
        downloadedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      // Active trash item (deleted 2 hours ago)
      final recentTrash = TrashedVideoItem(
        video: video,
        deletedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(recentTrash.isExpired, isFalse);
      expect(recentTrash.formattedRemainingTime, contains('sa'));

      // Expired trash item (deleted 25 hours ago)
      final expiredTrash = TrashedVideoItem(
        video: video,
        deletedAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      expect(expiredTrash.isExpired, isTrue);
      expect(expiredTrash.formattedRemainingTime, 'Kalıcı olarak silinecek');
    });

    test('DownloadTask progress, ETA and size formatting', () {
      final task = DownloadTask(
        id: '1001',
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        status: DownloadStatus.downloading,
        progress: 45.5,
        speed: '12.4 MB/s',
        etaSeconds: 125, // 2m 5s
        totalSize: '85.4 MB',
        downloadedSize: '38.8 MB',
        hadPreviousError: true,
      );

      expect(task.formattedEta, '02:05');
      expect(task.status, DownloadStatus.downloading);
      expect(task.formattedSizeInfo, '38.8 MB / 85.4 MB');
      expect(task.hadPreviousError, isTrue);

      final json = task.toJson();
      final fromJson = DownloadTask.fromJson(json);
      expect(fromJson.totalSize, '85.4 MB');
      expect(fromJson.downloadedSize, '38.8 MB');
      expect(fromJson.hadPreviousError, isTrue);
    });

    test('Network error detection and Turkish translation', () {
      const err1 =
          'ERROR: [youtube] 8hd7TV3YaUI: Unable to download API page: [Errno 7] No address associated with hostname';
      expect(DownloadProvider.isNetworkRelatedError(err1), isTrue);
      expect(DownloadProvider.cleanErrorMessage(err1),
          contains('İnternet / DNS bağlantısı kurulamadı'));

      const err2 = 'Sign in to confirm you’re not a bot';
      expect(DownloadProvider.cleanErrorMessage(err2),
          contains('YouTube bot doğrulaması istedi'));
    });
  });

  group('AMOLED Theme & UI Structure Tests', () {
    test('AmoledTheme tokens validation', () {
      final theme = AmoledTheme.themeData;
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('Full App Navigation and Tab switching',
        (WidgetTester tester) async {
      await tester.pumpWidget(const OfflineYoutubeApp());
      await tester.pump(const Duration(milliseconds: 200));

      // Check initial screen
      expect(find.text('Ana Sayfa'), findsOneWidget);
      expect(find.text('YouTube İndirici'), findsOneWidget);

      // Tap Downloads tab
      await tester.tap(find.byIcon(Icons.video_library_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRİLENLER'), findsOneWidget);
      expect(find.byIcon(Icons.restore_from_trash_rounded), findsOneWidget);

      // Tap Queue tab
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRME KUYRUĞU'), findsOneWidget);

      // Tap Settings tab
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('AYARLAR'), findsOneWidget);
      expect(find.text('Depolama Kotası Yöneticisi'), findsOneWidget);
      expect(find.text('Toplam Video Süresi Kotası'), findsOneWidget);
      expect(find.text('Ağ Kuralları'), findsOneWidget);
    });
  });
}
