import os

file_path = "lib/providers/download_provider.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add imports
if "import '../models/playlist_entry.dart';" not in content:
    content = content.replace("import '../models/video_item.dart';", "import '../models/video_item.dart';\nimport '../models/playlist_entry.dart';")

# Add constants
if "static const int maxPlaylistEntries =" not in content:
    content = content.replace("class DownloadProvider extends ChangeNotifier with WidgetsBindingObserver {", 
                              "class DownloadProvider extends ChangeNotifier with WidgetsBindingObserver {\n  static const int maxPlaylistEntries = 250;\n  static const int defaultVideoDurationSeconds = 180;\n")

# Replace addDownload playlist branch
content = content.replace(
    "    if (isPlaylist) {\n      return await _addPlaylistDownload(url: url, settings: settings);\n    } else {",
    "    if (isPlaylist) {\n      return 'PLAYLIST_URL';\n    } else {"
)

# Extract exactly lines 1089 to 1227 (0-indexed 1088 to 1227)
lines = content.split('\n')
if "  Future<String?> _addPlaylistDownload({" in lines[1088]:
    # Replace lines 1088 to 1227 with the new content
    new_methods = """  Future<PlaylistFetchResult> resolvePlaylist({
    required String url,
    required AppSettings settings,
  }) async {
    final rawEntries = await NativeBridge.instance.fetchPlaylistEntries(url);
    if (rawEntries.isEmpty) {
      return PlaylistFetchResult(
          entries: const [], totalCount: 0, sourceUrl: url);
    }

    final ordered = settings.playlistReverseOrder
        ? rawEntries
        : rawEntries.reversed.toList();

    final totalCount = ordered.length;
    final limited = totalCount > maxPlaylistEntries
        ? ordered.sublist(0, maxPlaylistEntries)
        : ordered;

    final downloadedVideos =
        await StorageManager.instance.scanDownloadedVideos();

    final entries = <PlaylistEntry>[];
    for (var i = 0; i < limited.length; i++) {
      final entry = _normalizePlaylistEntry(limited[i], i, downloadedVideos);
      if (entry != null) entries.add(entry);
    }

    return PlaylistFetchResult(
      entries: entries,
      totalCount: totalCount,
      sourceUrl: url,
    );
  }

  PlaylistEntry? _normalizePlaylistEntry(
    Map<String, dynamic> raw,
    int index,
    List<VideoItem> downloadedVideos,
  ) {
    final videoUrl = (raw['url'] as String? ?? '').trim();
    if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') return null;

    var title = (raw['title'] as String? ?? '').trim();
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('[deleted') ||
        lowerTitle.contains('[private') ||
        lowerTitle.contains('[unavailable')) {
      return null;
    }

    final vid = VideoItem.extractVideoId(videoUrl);
    if (title.isEmpty || lowerTitle == 'null' || lowerTitle == 'null null') {
      title = vid != null ? 'Video ($vid)' : 'Video ${index + 1}';
    }

    var thumbnail = (raw['thumbnail'] as String? ?? '').trim();
    if (thumbnail.isEmpty || thumbnail.toLowerCase() == 'null') {
      thumbnail = vid != null ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '';
    }

    var uploader = (raw['uploader'] as String? ?? '').trim();
    if (uploader.toLowerCase() == 'null') uploader = '';

    final inQueue = _tasks.any((t) {
      final tVid = VideoItem.extractVideoId(t.url);
      return t.url == videoUrl || (vid != null && tVid == vid);
    });
    final inLibrary = downloadedVideos.any(
      (v) => v.sourceUrl == videoUrl || (vid != null && v.youtubeId == vid),
    );

    return PlaylistEntry(
      url: videoUrl,
      title: title,
      durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
      thumbnail: thumbnail.isNotEmpty ? thumbnail : null,
      uploader: uploader.isNotEmpty ? uploader : null,
      alreadyPresent: inQueue || inLibrary,
    );
  }

  Future<String?> addSelectedEntries({
    required List<PlaylistEntry> entries,
    required AppSettings settings,
    required String sourcePlaylistUrl,
    int truncatedCount = 0,
    int totalCount = 0,
  }) async {
    if (entries.isEmpty) return 'Seçili video yok.';

    final downloadedVideos =
        await StorageManager.instance.scanDownloadedVideos();
    int runningTotalSec = downloadedVideos.fold<int>(
        0, (sum, v) => sum + (v.durationSeconds ?? 0));
    final maxDurationSec = settings.maxVideoDurationHours * 3600;

    int addedCount = 0;
    int skippedCount = 0;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final effectiveDuration = entry.hasDuration
          ? entry.durationSeconds
          : defaultVideoDurationSeconds;

      if ((runningTotalSec + effectiveDuration) > maxDurationSec) {
        skippedCount++;
        continue;
      }

      runningTotalSec += effectiveDuration;
      _tasks.add(DownloadTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        url: entry.url,
        title: 'Bilgiler alınıyor...',
        status: DownloadStatus.queued,
        sourcePlaylistUrl: sourcePlaylistUrl,
      ));
      addedCount++;
    }

    if (addedCount > 0) {
      _saveTasksToStorage();
      notifyListeners();
      if (!_isQueuePaused) {
        await processNextQueue(settings: settings);
      }
    }

    if (addedCount == 0 && skippedCount > 0) {
      return 'Kütüphane süre sınırına ulaşıldı (${settings.maxVideoDurationHours} saat). Seçilen videolar eklenemedi.';
    }

    if (skippedCount > 0) {
      return 'Kütüphane süre sınırı nedeniyle ${entries.length} videodan sadece $addedCount tanesi eklendi ($skippedCount atlandı).';
    }

    return null;
  }"""
    
    # We replace lines 1088 to 1227 inclusive
    lines = lines[:1088] + new_methods.split('\n') + lines[1227:]
    
    content = '\n'.join(lines)
    print("Replaced _addPlaylistDownload via line numbers.")

# Fix pauseTask
idx_pause = content.find("Future<void> pauseTask(String taskId) async {")
if idx_pause != -1:
    end_pause = content.find("  }", idx_pause) + 3
    pause_body = content[idx_pause:end_pause]
    if "_triggerNextQueue()" not in pause_body:
        new_pause_body = pause_body.replace("    }\n  }", "    }\n    _triggerNextQueue();\n  }")
        content = content[:idx_pause] + new_pause_body + content[end_pause:]

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done patching download_provider.dart")
