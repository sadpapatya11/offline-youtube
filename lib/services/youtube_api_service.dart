import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'dart:math';
import 'package:http/http.dart' as http;

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class YoutubeApiService {
  static final YoutubeApiService _instance = YoutubeApiService._internal();
  factory YoutubeApiService() => _instance;
  YoutubeApiService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [yt.YouTubeApi.youtubeScope],
  );

  GoogleSignInAccount? _currentUser;
  final Queue<Map<String, String>> _deletionQueue = Queue();
  bool _isProcessingQueue = false;

  GoogleSignInAccount? get currentUser => _currentUser;

  /// Listen for sign-in state changes
  void init() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      _currentUser = account;
      if (account != null) {
        debugPrint('YouTube API (Google Sign-In) successful: ${account.email}');
      }
    });
    _googleSignIn.signInSilently();
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (e) {
      debugPrint('Google SignIn Error: $e');
      return null;
    }
  }

  Future<Map<String, DateTime>?> fetchPlaylistVideos(String playlistId) async {
    final account = _currentUser;
    if (account == null) return null;

    final headers = await account.authHeaders;
    final client = _GoogleAuthClient(headers);
    final api = yt.YouTubeApi(client);

    try {
      String? nextPageToken;
      final List<String> videoIds = [];
      do {
        final resp = await api.playlistItems.list(
            ['contentDetails'],
            playlistId: playlistId,
            maxResults: 50,
            pageToken: nextPageToken
        );
        for (var item in resp.items ?? []) {
          if (item.contentDetails?.videoId != null) {
            videoIds.add(item.contentDetails!.videoId!);
          }
        }
        nextPageToken = resp.nextPageToken;
      } while (nextPageToken != null);

      final Map<String, DateTime> publishedByVideoId = {};
      for (int i = 0; i < videoIds.length; i += 50) {
        final chunk = videoIds.sublist(i, min(i + 50, videoIds.length));
        final vidResp = await api.videos.list(['snippet'], id: chunk, maxResults: 50);
        for (final v in vidResp.items ?? []) {
          final ts = v.snippet?.publishedAt;
          if (v.id != null && ts != null) publishedByVideoId[v.id!] = ts;
        }
      }

      return publishedByVideoId;
    } catch (e) {
      debugPrint('fetchPlaylistVideos error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  /// Extracts the playlist ID from a YouTube playlist URL (e.g. ?list=PLxxxx)
  String? _extractPlaylistId(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.queryParameters.containsKey('list')) {
      return uri.queryParameters['list'];
    }
    return null;
  }

  /// Adds a deletion request to the queue to prevent API spam (Anti-Ban feature)
  void enqueueDeletion(String? playlistUrl, String? videoId) {
    if (playlistUrl == null || videoId == null) return;
    
    final playlistId = _extractPlaylistId(playlistUrl);
    if (playlistId == null) return;

    _deletionQueue.add({
      'playlistId': playlistId,
      'videoId': videoId,
    });
    
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _deletionQueue.isEmpty) return;
    _isProcessingQueue = true;

    while (_deletionQueue.isNotEmpty) {
      final item = _deletionQueue.removeFirst();
      final playlistId = item['playlistId']!;
      final videoId = item['videoId']!;

      try {
        // Doğal kullanıcı davranışı taklidi ve API sınırlarına takılmamak için
        // her işlem öncesi 1 ile 10 saniye arası (yapay) rastgele gecikme ekliyoruz.
        final randomDelay = Random().nextInt(10) + 1; // 1 to 10 seconds
        debugPrint('YouTube API delay: $randomDelay seconds before next delete...');
        await Future.delayed(Duration(seconds: randomDelay));
        await _executeDelete(playlistId, videoId);
      } catch (e) {
        debugPrint('YouTube Playlist API Error: $e');
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> _executeDelete(String playlistId, String videoId) async {
    final account = _currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) {
      debugPrint('Cannot delete from playlist: User not signed in.');
      return;
    }

    final headers = await account.authHeaders;
    final authClient = _GoogleAuthClient(headers);
    final youtube = yt.YouTubeApi(authClient);

    // 1. Find the playlistItemId inside the specific playlist that matches the videoId
    final yt.PlaylistItemListResponse response = await youtube.playlistItems.list(
      ['id', 'snippet'],
      playlistId: playlistId,
      videoId: videoId,
    );

    if (response.items == null || response.items!.isEmpty) {
      debugPrint('Video $videoId not found in playlist $playlistId.');
      authClient.close();
      return;
    }

    // 2. Delete the item using its specific playlistItemId
    for (final item in response.items!) {
      final playlistItemId = item.id;
      if (playlistItemId != null) {
        debugPrint('Deleting playlist item $playlistItemId (Video: $videoId) from $playlistId...');
        await youtube.playlistItems.delete(playlistItemId);
        debugPrint('Successfully deleted from YouTube playlist.');
      }
    }

    authClient.close();
  }
}
