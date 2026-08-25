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

/// Bir silme isteğinin başarısızlığı tekrar denemeye değer mi.
enum DeletionFailureKind { transient, permanent }

/// Kuyruktaki tek bir silme isteği. Kaç kez denendiğini KENDİSİ taşır: sayaç
/// olmadan geçici hatada geri konan istek sonsuza kadar dönebilir.
class _DeletionRequest {
  final String playlistId;
  final String videoId;
  int attempts;

  _DeletionRequest(this.playlistId, this.videoId) : attempts = 0;
}

class YoutubeApiService {
  static final YoutubeApiService _instance = YoutubeApiService._internal();
  factory YoutubeApiService() => _instance;
  YoutubeApiService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [yt.YouTubeApi.youtubeScope],
  );

  /// Geçici hatada bir isteğin toplam deneme sayısı. Sınırsız deneme, kalıcı bir
  /// 403 (liste artık bu hesabın değil) durumunda kuyruğu sonsuz döndürürdü.
  static const int maxDeletionAttempts = 3;

  GoogleSignInAccount? _currentUser;

  /// Kullanıcı bu oturumda AÇIKÇA çıkış yaptı mı.
  ///
  /// signOut sonrası sessiz giriş cihazda çoğu zaman hâlâ başarılı olur. Bayrak
  /// olmadan, ayarlardan çıkış yapan kullanıcının hesabına bekleyen bir silme
  /// isteği ya da eşitleme turu dokunmaya devam ederdi.
  bool _userSignedOut = false;

  final Queue<_DeletionRequest> _deletionQueue = Queue();
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
      final account = await _googleSignIn.signIn();
      _currentUser = account;
      if (account != null) _userSignedOut = false;
      return account;
    } catch (e) {
      debugPrint('Google SignIn Error: $e');
      return null;
    }
  }

  /// Oturumu çözer; bellekte yoksa sessiz girişi dener.
  ///
  /// Arka plan izolatında [init] HİÇ çağrılmaz, dolayısıyla `_currentUser` her
  /// zaman null olur. Sessiz giriş denenmezse eşitleme YouTube üstverisini hiç
  /// çekemez ve bulunan her yeni video için ayrı bir yt-dlp metadata süreci
  /// başlar: 40 videoluk bir turda 40 ayrı süreç, WorkManager'ın ~10 dakikalık
  /// penceresini yiyip görevi yarıda kestirir.
  Future<GoogleSignInAccount?> _ensureAccount() async {
    final cached = _currentUser;
    if (cached != null) return cached;
    if (_userSignedOut) return null;
    try {
      final account = await _googleSignIn.signInSilently();
      _currentUser ??= account;
      return account;
    } catch (e) {
      debugPrint('signInSilently error: $e');
      return null;
    }
  }

  Future<Map<String, DateTime>?> fetchPlaylistVideos(String playlistId) async {
    final account = await _ensureAccount();
    if (account == null) return null;

    // authHeaders da ağa çıkar ve fırlatabilir; try'ın DIŞINDA kalırsa istisna
    // eşitleme turunun tamamını düşürüyordu. İstemci de bu yüzden nullable.
    _GoogleAuthClient? client;
    try {
      final headers = await account.authHeaders;
      client = _GoogleAuthClient(headers);
      final api = yt.YouTubeApi(client);
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
      client?.close();
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _userSignedOut = true;
  }

  /// Bir YouTube bağlantısından oynatma listesi kimliğini çıkarır (`?list=...`).
  ///
  /// Saf ve doğrudan test edilebilir olması ŞART: yanlış kimlik, kullanıcının
  /// BAŞKA bir oynatma listesinden video silinmesi demektir ve geri alınamaz.
  /// Kimlik çıkarılamıyorsa null döner ve silme hiç denenmez.
  @visibleForTesting
  static String? extractPlaylistId(String? url) {
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
    
    final playlistId = extractPlaylistId(playlistUrl);
    if (playlistId == null) return;

    _deletionQueue.add(_DeletionRequest(playlistId, videoId));
    
    _processQueue();
  }

  /// Silme hatasını sınıflandırır: tekrar denenmeli mi, atılmalı mı.
  ///
  /// Eskiden HER hata `debugPrint` ile yutuluyordu ve istek kuyruktan zaten
  /// çıkmış olduğu için bir daha DENENMİYORDU. Şebekesini kaybeden kullanıcının
  /// 20 videosu YouTube listesinden hiç silinmiyordu; uygulama ise silmiş gibi
  /// davranıyordu. Aynı sessizlik 401 (token süresi doldu) ve 429 (hız sınırı)
  /// için de geçerliydi.
  @visibleForTesting
  static DeletionFailureKind classifyDeletionFailure(Object error) {
    if (error is yt.DetailedApiRequestError) {
      final status = error.status;
      // 400 biçimsel hata, 404 öğe zaten yok: tekrar denemek aynı sonucu verir,
      // istek kuyrukta tutulursa boşuna kota harcar.
      if (status == 400 || status == 404) return DeletionFailureKind.permanent;
      // 401 / 403 / 429 / 5xx: taze token, kota penceresi veya ağın düzelmesiyle
      // sonraki turda başarılı olabilir.
      return DeletionFailureKind.transient;
    }
    // SocketException, TimeoutException, kanal hatası: ağ geri gelince düzelir.
    return DeletionFailureKind.transient;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue || _deletionQueue.isEmpty) return;
    _isProcessingQueue = true;

    while (_deletionQueue.isNotEmpty) {
      final item = _deletionQueue.removeFirst();

      try {
        // Doğal kullanıcı davranışı taklidi ve API sınırlarına takılmamak için
        // her işlem öncesi 1 ile 10 saniye arası (yapay) rastgele gecikme ekliyoruz.
        final randomDelay = Random().nextInt(10) + 1; // 1 to 10 seconds
        debugPrint('YouTube API delay: $randomDelay seconds before next delete...');
        await Future.delayed(Duration(seconds: randomDelay));
        await _executeDelete(item.playlistId, item.videoId);
      } catch (e) {
        item.attempts++;
        final kind = classifyDeletionFailure(e);
        if (kind == DeletionFailureKind.transient &&
            item.attempts < maxDeletionAttempts) {
          // Token süresi dolduysa aynı bayat başlıkla tekrar denemek anlamsız:
          // önbelleği temizle ki sonraki deneme taze token alsın.
          if (e is yt.DetailedApiRequestError && e.status == 401) {
            await _clearAuthCache();
          }
          _deletionQueue.addLast(item);
          debugPrint(
              'YouTube silme hatası (deneme ${item.attempts}/$maxDeletionAttempts), istek kuyruğa geri alındı: $e');
        } else {
          debugPrint(
              'YouTube silme isteği düştü (${item.videoId} -> ${item.playlistId}), deneme ${item.attempts}: $e');
        }
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> _clearAuthCache() async {
    try {
      await _currentUser?.clearAuthCache();
    } catch (e) {
      debugPrint('clearAuthCache error: $e');
    }
  }

  Future<void> _executeDelete(String playlistId, String videoId) async {
    final account = await _ensureAccount();
    if (account == null) {
      debugPrint('Cannot delete from playlist: User not signed in.');
      return;
    }

    final headers = await account.authHeaders;
    final authClient = _GoogleAuthClient(headers);
    final youtube = yt.YouTubeApi(authClient);

    // İstemci HATA yolunda da kapatılmalı: kapatılmayan her _GoogleAuthClient
    // içindeki http.Client açık soketi canlı tutuyor. Çevrimdışı yapılan 50
    // videoluk toplu silmede 50 soket sızıyor, uzun oturumda platform sınırına
    // dayanıyordu. fetchPlaylistVideos'taki kalıbın aynısı.
    try {
      // 1. Find the playlistItemId inside the specific playlist that matches the videoId
      final yt.PlaylistItemListResponse response = await youtube.playlistItems.list(
        ['id', 'snippet'],
        playlistId: playlistId,
        videoId: videoId,
      );

      if (response.items == null || response.items!.isEmpty) {
        debugPrint('Video $videoId not found in playlist $playlistId.');
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
    } finally {
      authClient.close();
    }
  }
}
