import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/main.dart';
import 'package:offlineyoutube/models/app_settings.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/providers/download_provider.dart';
import 'package:offlineyoutube/services/network_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E2E Full Lifecycle & Workflow Tests', () {
    test('1. App Settings & 2-Mode Network Restriction Validation', () async {
      // Default settings check
      const defaultSettings = AppSettings();
      expect(defaultSettings.networkMode, NetworkRestrictionMode.anyWifi);
      expect(defaultSettings.maxStorageLimitGB, 20);
      expect(defaultSettings.maxVideoDurationHours, 6);
      expect(defaultSettings.playlistReverseOrder, isTrue);

      // Verify network permission with allNetworks (should always allow)
      final netCheckAll = await NetworkManager.instance
          .checkNetworkPermissionAndStatus(defaultSettings.copyWith(networkMode: NetworkRestrictionMode.allNetworks));
      expect(netCheckAll['allowed'], isTrue);

      // Verify copyWith works properly for WiFi mode
      final wifiOnlySettings = defaultSettings.copyWith(
        networkMode: NetworkRestrictionMode.anyWifi,
        maxStorageLimitGB: 50,
        maxVideoDurationHours: 10,
      );
      expect(wifiOnlySettings.networkMode, NetworkRestrictionMode.anyWifi);
      expect(wifiOnlySettings.maxStorageLimitGB, 50);
      expect(wifiOnlySettings.maxVideoDurationHours, 10);
    });

    test('2. Sequential Queue & Task State Engine & Serialization', () {
      final task1 = DownloadTask(
        id: 'task_001',
        url: 'https://www.youtube.com/watch?v=video1',
        title: 'Video 1 - Flutter Architecture',
        status: DownloadStatus.queued,
      );

      final task2 = DownloadTask(
        id: 'task_002',
        url: 'https://www.youtube.com/watch?v=video2',
        title: 'Video 2 - State Management',
        status: DownloadStatus.queued,
      );

      expect(task1.status, DownloadStatus.queued);
      expect(task2.status, DownloadStatus.queued);

      // Start task 1
      task1.status = DownloadStatus.downloading;
      task1.progress = 50.0;
      task1.speed = '4.2 MB/s';
      task1.etaSeconds = 45;

      expect(task1.status, DownloadStatus.downloading);
      expect(task1.formattedEta, '00:45');

      // Test toJson and fromJson round-trip
      final json1 = task1.toJson();
      final restoredTask1 = DownloadTask.fromJson(json1);
      expect(restoredTask1.id, task1.id);
      expect(restoredTask1.url, task1.url);
      expect(restoredTask1.title, task1.title);
      expect(restoredTask1.status, DownloadStatus.downloading);
      expect(restoredTask1.progress, 50.0);
      expect(restoredTask1.speed, '4.2 MB/s');
      expect(restoredTask1.etaSeconds, 45);

      // Pause task 1 (Supressing error state)
      task1.status = DownloadStatus.paused;
      task1.speed = '';
      expect(task1.status, DownloadStatus.paused);
      expect(task1.speed, '');

      // Resume task 1
      task1.status = DownloadStatus.queued;
      expect(task1.status, DownloadStatus.queued);

      // Complete task 1
      task1.status = DownloadStatus.completed;
      task1.progress = 100.0;
      expect(task1.status, DownloadStatus.completed);

      // Start task 2
      task2.status = DownloadStatus.downloading;
      expect(task2.status, DownloadStatus.downloading);
    });

    test('3. Playlist Publication Date Ordering & Duration Filtering Logic', () {
      final mockRawPlaylist = [
        {'id': 'vid_old', 'title': 'Old Video', 'duration': 1200, 'upload_date': '20230101'},
        {'id': 'vid_new', 'title': 'New Video', 'duration': 1800, 'upload_date': '20260701'},
        {'id': 'vid_mid', 'title': 'Mid Video', 'duration': 900, 'upload_date': '20250515'},
        {'id': 'vid_long', 'title': 'Too Long Video', 'duration': 36000, 'upload_date': '20260801'},
      ];

      // Sort by upload_date descending (newest first)
      final sorted = List<Map<String, dynamic>>.from(mockRawPlaylist)
        ..sort((a, b) {
          final dateA = a['upload_date'] as String? ?? '';
          final dateB = b['upload_date'] as String? ?? '';
          return dateB.compareTo(dateA);
        });

      expect(sorted[0]['id'], 'vid_long');
      expect(sorted[1]['id'], 'vid_new');
      expect(sorted[2]['id'], 'vid_mid');
      expect(sorted[3]['id'], 'vid_old');

      // Filter by max duration (e.g. 6 hours = 21600 seconds)
      const maxDurationSeconds = 6 * 3600;
      final filtered = sorted.where((item) {
        final dur = item['duration'] as int? ?? 0;
        return dur <= maxDurationSeconds;
      }).toList();

      expect(filtered.length, 3);
      expect(filtered.any((e) => e['id'] == 'vid_long'), isFalse);
      expect(filtered[0]['id'], 'vid_new');
    });

    test('4. VideoItem & Storage Calculations', () {
      final videos = [
        VideoItem(
          id: 'v1',
          title: 'Video 1',
          filePath: '/downloads/v1.mp4',
          fileSizeBytes: 1024 * 1024 * 500, // 500 MB
          downloadedAt: DateTime.now(),
        ),
        VideoItem(
          id: 'v2',
          title: 'Video 2',
          filePath: '/downloads/v2.mp4',
          fileSizeBytes: 1024 * 1024 * 1500, // 1.5 GB
          downloadedAt: DateTime.now(),
        ),
      ];

      final totalBytes = videos.fold<int>(0, (sum, v) => sum + v.fileSizeBytes);
      final totalGB = totalBytes / (1024 * 1024 * 1024);
      expect(totalGB, closeTo(1.95, 0.05));
    });

    test('5. YouTube URL Validation & Error Message Cleaning', () {
      // Invalid inputs
      expect(DownloadProvider.isValidYouTubeUrl(''), isFalse);
      expect(DownloadProvider.isValidYouTubeUrl('Bu offline-youtube uygulamasında indirmeyi duraklattığında...'), isFalse);
      expect(DownloadProvider.isValidYouTubeUrl('not a url'), isFalse);
      expect(DownloadProvider.isValidYouTubeUrl('ftp://youtube.com/watch?v=123'), isFalse);

      // Valid inputs
      expect(DownloadProvider.isValidYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(DownloadProvider.isValidYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(DownloadProvider.isValidYouTubeUrl('https://youtube.com/shorts/abcd1234'), isTrue);
      expect(DownloadProvider.isValidYouTubeUrl('https://music.youtube.com/watch?v=xyz'), isTrue);
      expect(DownloadProvider.isValidYouTubeUrl('https://www.youtube.com/playlist?list=PL123456789'), isTrue);

      // Error cleaning
      final rawError = 'PlatformException(METADATA_ERROR, WARNING: Your yt-dlp version is older than 90 days! ERROR: [generic] not a valid URL, null, null)';
      final cleaned = DownloadProvider.cleanErrorMessage(rawError);
      expect(cleaned, contains('[generic] not a valid URL'));
      expect(cleaned.contains('WARNING:'), isFalse);
    });

    testWidgets('6. Full UI E2E Navigation & Component Interaction', (WidgetTester tester) async {
      await tester.pumpWidget(const OfflineYoutubeApp());
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Home screen verification
      expect(find.text('Ana Sayfa'), findsOneWidget);
      expect(find.text('YouTube İndirici'), findsOneWidget);

      // 2. Navigate to Downloads tab
      await tester.tap(find.byIcon(Icons.video_library_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRİLENLER'), findsOneWidget);

      // 3. Navigate to Queue tab
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('İNDİRME KUYRUĞU'), findsOneWidget);

      // 4. Navigate to Settings tab
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('AYARLAR'), findsOneWidget);
      expect(find.text('Ağ Kuralları'), findsOneWidget);
      expect(find.text('Sadece Wi-Fi ile İndir'), findsOneWidget);
      expect(find.text('Depolama Kotası Yöneticisi'), findsOneWidget);
      expect(find.text('Toplam Video Süresi Kotası'), findsOneWidget);
      expect(find.text('yt-dlp Motorunu Güncelle'), findsOneWidget);

      // 5. Test Switch interaction on Settings
      final wifiSwitch = find.byType(Switch).first;
      await tester.scrollUntilVisible(wifiSwitch, 100);
      await tester.tap(wifiSwitch);
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
