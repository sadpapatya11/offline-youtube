import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/video_item.dart';
import 'package:offlineyoutube/providers/download_provider.dart';
import 'package:offlineyoutube/providers/library_provider.dart';
import 'package:offlineyoutube/ui/screens/downloads_screen.dart';
import 'package:offlineyoutube/ui/widgets/video_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoItem ID Extraction & Matching Tests', () {
    test('Extracts YouTube Video ID accurately from various URL formats', () {
      expect(
        VideoItem.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        VideoItem.extractVideoId('https://youtu.be/dQw4w9WgXcQ?t=10'),
        'dQw4w9WgXcQ',
      );
      expect(
        VideoItem.extractVideoId('https://www.youtube.com/shorts/abcdef12345'),
        'abcdef12345',
      );
      expect(
        VideoItem.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        VideoItem.extractVideoId('invalid_url'),
        null,
      );
    });

    test('VideoItem youtubeId getter works correctly with sourceUrl and id', () {
      final video1 = VideoItem(
        id: 'dQw4w9WgXcQ',
        title: 'Video 1',
        filePath: '/test/video1.mp4',
        fileSizeBytes: 1024,
        downloadedAt: DateTime.now(),
        sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(video1.youtubeId, 'dQw4w9WgXcQ');

      final video2 = VideoItem(
        id: 'custom_id_123',
        title: 'Video 2',
        filePath: '/test/video2.mp4',
        fileSizeBytes: 1024,
        downloadedAt: DateTime.now(),
        sourceUrl: 'https://youtu.be/abcdefghijk',
      );
      expect(video2.youtubeId, 'abcdefghijk');
    });
  });

  group('DownloadsScreen Multi-Selection & Bulk Delete UI Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('DownloadsScreen builds properly with MultiProvider',
        (tester) async {
      final libraryProvider = LibraryProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibraryProvider>.value(
                value: libraryProvider,
              ),
            ],
            child: const DownloadsScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Top bar title is İNDİRİLENLER initially
      expect(find.text('İNDİRİLENLER'), findsOneWidget);
    });

    testWidgets('VideoTile displays selection UI correctly', (tester) async {
      final video = VideoItem(
        id: 'test_vid',
        title: 'Test Flutter Video',
        filePath: '/test/vid.mp4',
        fileSizeBytes: 50 * 1024 * 1024,
        downloadedAt: DateTime.now(),
        durationSeconds: 120,
      );

      bool tapped = false;
      bool longPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTile(
              video: video,
              isSelectionMode: true,
              isSelected: true,
              onTap: () => tapped = true,
              onLongPress: () => longPressed = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test Flutter Video'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.byType(VideoTile));
      expect(tapped, true);

      await tester.longPress(find.byType(VideoTile));
      expect(longPressed, true);
    });

    testWidgets('DownloadsScreen renders RefreshIndicator correctly',
        (tester) async {
      final libraryProvider = LibraryProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibraryProvider>.value(
                value: libraryProvider,
              ),
            ],
            child: const DownloadsScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    test('PlaylistSyncResult calculates fields accurately', () {
      const res = PlaylistSyncResult(
        success: true,
        newVideosAdded: 3,
        deletedVideosRemoved: 2,
      );
      expect(res.success, true);
      expect(res.newVideosAdded, 3);
      expect(res.deletedVideosRemoved, 2);
    });
  });
}
