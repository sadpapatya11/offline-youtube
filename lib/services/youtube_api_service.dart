import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
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
    } catch (error) {
      debugPrint('Google Sign-In Error: $error');
      // Common error 10 means DEVELOPER_ERROR (misconfigured SHA-1 or package name in GCP)
      return null;
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
        // her işlem öncesi 3-5 saniye (yapay) gecikme ekliyoruz.
        await Future.delayed(const Duration(seconds: 4));
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
