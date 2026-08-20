import re

with open('lib/providers/download_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add youtube_api_service.dart import
if "import '../services/youtube_api_service.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../services/youtube_api_service.dart';")

# 2. Extract logic for syncSavedPlaylists
sync_match = re.search(r'Future<PlaylistSyncResult> syncSavedPlaylists.*?finally \{\s*_isSyncingPlaylists = false;\s*notifyListeners\(\);\s*\}\s*\}', content, flags=re.DOTALL)
if not sync_match:
    print("Could not find syncSavedPlaylists")
    exit(1)

old_sync = sync_match.group(0)

new_sync = """Future<PlaylistSyncResult> syncSavedPlaylists({
    required AppSettings settings,
    required LibraryProvider libraryProvider,
  }) async {
    if (_isSyncingPlaylists) return const PlaylistSyncResult(success: false, message: 'Senkronizasyon zaten devam ediyor');
    if (settings.savedPlaylists.isEmpty) return const PlaylistSyncResult(success: false, message: 'Kayitli oynatma listesi bulunamadi');

    _isSyncingPlaylists = true;
    notifyListeners();

    int trashedCount = 0;
    int queueDeletedCount = 0;
    int addedCount = 0;
    bool anyPlaylistSucceeded = false;

    try {
      final downloadedVideos = await StorageManager.instance.scanDownloadedVideos();
      final currentQueueTasks = List<DownloadTask>.from(_manager.tasks);
      final Set<String> allOnlineVideoIds = {};
      final Set<String> allOnlineUrls = {};
      final List<Map<String, dynamic>> orderedNewEntries = [];

      for (final playlistUrl in settings.savedPlaylists) {
        if (playlistUrl.trim().isEmpty) continue;
        try {
          final pid = VideoItem.extractPlaylistId(playlistUrl);
          Map<String, DateTime>? apiDates;
          if (pid != null) {
            apiDates = await YoutubeApiService().fetchPlaylistVideos(pid);
          }

          final entries = await NativeBridge.instance.fetchPlaylistEntries(playlistUrl);
          if (entries.isNotEmpty) anyPlaylistSucceeded = true;
          for (final entry in entries) {
            final u = (entry['url'] as String? ?? '').trim();
            final vid = VideoItem.extractVideoId(u) ?? (entry['id'] as String? ?? '').trim();
            if (vid.isNotEmpty) allOnlineVideoIds.add(vid);
            if (u.isNotEmpty) allOnlineUrls.add(u);

            final t = (entry['title'] as String? ?? '').trim();
            if (t.toLowerCase().contains('[deleted') || t.toLowerCase().contains('[private') || t.toLowerCase().contains('[unavailable')) continue;

            final isAlreadyDownloaded = downloadedVideos.any((v) => (v.youtubeId != null && v.youtubeId == vid) || (v.sourceUrl != null && v.sourceUrl == u));
            final isAlreadyInQueue = currentQueueTasks.any((t) => (VideoItem.extractVideoId(t.url) != null && VideoItem.extractVideoId(t.url) == vid) || t.url == u);
            final isAlreadyInBatch = orderedNewEntries.any((e) {
              final eUrl = (e['url'] as String? ?? '').trim();
              final eVid = VideoItem.extractVideoId(eUrl) ?? (e['id'] as String? ?? '').trim();
              return (vid.isNotEmpty && eVid == vid) || (u.isNotEmpty && eUrl == u);
            });

            if (!isAlreadyDownloaded && !isAlreadyInQueue && !isAlreadyInBatch) {
              final newEntry = {...entry, '_sourcePlaylistUrl': playlistUrl};
              if (apiDates != null && vid.isNotEmpty && apiDates.containsKey(vid)) {
                newEntry['uploadDate'] = apiDates[vid]!.toIso8601String();
              }
              orderedNewEntries.add(newEntry);
            }
          }
        } catch (_) {}
      }

      if (anyPlaylistSucceeded) {
        for (final video in downloadedVideos) {
          if (video.playlistUrl == null || video.playlistUrl!.isEmpty || !settings.savedPlaylists.contains(video.playlistUrl)) continue;
          final vid = video.youtubeId;
          final stillInPlaylist = (vid != null && allOnlineVideoIds.contains(vid)) || allOnlineUrls.contains(video.sourceUrl);
          if (!stillInPlaylist) {
            final moved = await StorageManager.instance.moveToTrash(video);
            if (moved) trashedCount++;
          }
        }
        if (trashedCount > 0) _manager.onLibraryNeedsRefresh?.call();
      }

      for (final t in List.of(_manager.tasks)) {
        final belongsToSavedPlaylist = t.sourcePlaylistUrl != null && settings.savedPlaylists.contains(t.sourcePlaylistUrl);
        if (!belongsToSavedPlaylist) continue;
        if (t.status == DownloadStatus.queued || t.status == DownloadStatus.paused) {
          final tVid = VideoItem.extractVideoId(t.url);
          final stillOnline = (tVid != null && allOnlineVideoIds.contains(tVid)) || allOnlineUrls.contains(t.url);
          if (!stillOnline) {
            _manager.tasks.remove(t);
            queueDeletedCount++;
          }
        }
      }

      // Metadata Fallback for missing uploadDate
      for (var i = 0; i < orderedNewEntries.length; i++) {
         final d = orderedNewEntries[i]['uploadDate']?.toString() ?? '';
         if (d.isEmpty) {
             final u = (orderedNewEntries[i]['url'] as String? ?? '').trim();
             if (u.isNotEmpty) {
                 try {
                     final meta = await NativeBridge.instance.fetchMetadata(u);
                     orderedNewEntries[i]['uploadDate'] = meta['uploadDate'];
                 } catch(_) {}
             }
         }
      }

      orderedNewEntries.sort((a, b) {
          final da = (a['uploadDate']?.toString() ?? '').replaceAll('-', '');
          final db = (b['uploadDate']?.toString() ?? '').replaceAll('-', '');
          if (da.isNotEmpty && db.isNotEmpty) return db.compareTo(da);
          return 0;
      });

      final maxDurationSec = settings.maxVideoDurationHours * 3600;
      final refreshedDownloads = await StorageManager.instance.scanDownloadedVideos();
      int runningTotalSec = refreshedDownloads.fold<int>(0, (sum, v) => sum + (v.durationSeconds ?? 0));

      for (final entry in orderedNewEntries) {
        final videoUrl = (entry['url'] as String? ?? '').trim();
        var title = (entry['title'] as String? ?? '').trim();
        final duration = (entry['duration'] as num?)?.toInt() ?? 0;
        var thumbnail = (entry['thumbnail'] as String? ?? '').trim();
        var uploader = (entry['uploader'] as String? ?? '').trim();

        if (videoUrl.isEmpty || videoUrl.toLowerCase() == 'null') continue;
        if (duration > 0 && (runningTotalSec + duration) > maxDurationSec) continue;

        if (title.isEmpty || title.toLowerCase() == 'null') {
          final vid = VideoItem.extractVideoId(videoUrl);
          title = vid != null ? 'Video ($vid)' : 'YouTube Videosu';
        }

        runningTotalSec += duration;
        final taskId = '${DateTime.now().millisecondsSinceEpoch}_jit_0';
        final entrySourcePlaylist = (entry['_sourcePlaylistUrl'] as String? ?? '').trim();
        final newTask = DownloadTask(
          id: taskId,
          url: videoUrl,
          title: title,
          thumbnail: thumbnail.isNotEmpty && thumbnail.toLowerCase() != 'null' ? thumbnail : null,
          durationSeconds: duration,
          uploader: uploader.isNotEmpty && uploader.toLowerCase() != 'null' ? uploader : null,
          uploadDate: entry['uploadDate']?.toString(),
          status: DownloadStatus.queued,
          sourcePlaylistUrl: entrySourcePlaylist.isNotEmpty ? entrySourcePlaylist : null,
        );

        _manager.tasks.insert(0, newTask);
        addedCount++;
        break; // YALNIZCA TEK YENI VIDEO EKLENIR
      }

      await _manager.saveTasksToStorage();
      _manager.notifyListeners();
      if (!_manager.isQueuePaused && addedCount > 0) {
        await _manager.processNextQueue(settings: settings);
      }

      return PlaylistSyncResult(
        success: anyPlaylistSucceeded,
        newVideosAdded: addedCount,
        deletedVideosRemoved: trashedCount + queueDeletedCount,
      );
    } catch (e) {
      return PlaylistSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncingPlaylists = false;
      notifyListeners();
    }
  }"""

content = content.replace(old_sync, new_sync)

with open('lib/providers/download_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated download_provider.dart")
