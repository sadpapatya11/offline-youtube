import 'dart:io';

class VideoItem {
  final String id;
  final String title;
  final String filePath;
  final int fileSizeBytes;
  final int? durationSeconds;
  final String? uploader;
  final DateTime downloadedAt;
  final String? thumbnailPath;
  final String? subtitlePath;
  final String? sourceUrl;
  final String? playlistUrl;
  final String? uploadDate;

  VideoItem({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileSizeBytes,
    this.durationSeconds,
    this.uploader,
    required this.downloadedAt,
    this.thumbnailPath,
    this.subtitlePath,
    this.sourceUrl,
    this.playlistUrl,
    this.uploadDate,
  });

  bool get exists => File(filePath).existsSync();

  /// Video çöp kutusuna taşınırken kullanılan kopya: yalnız dosya yolları değişir,
  /// üstverinin tamamı korunur.
  ///
  /// [playlistUrl] ve [sourceUrl] burada MUTLAKA taşınır: kalıcı silme anında
  /// videoyu kullanıcının YouTube oynatma listesinden kaldırma kararı bu iki alana
  /// bağlıdır ([youtubeId] sourceUrl üzerinden türer). Alanlar düşerse silme isteği
  /// sessizce erken döner ve kullanıcıya verilen söz yerine gelmez.
  VideoItem copyForTrash({required String filePath, String? thumbnailPath}) {
    return VideoItem(
      id: id,
      title: title,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      durationSeconds: durationSeconds,
      uploader: uploader,
      downloadedAt: downloadedAt,
      thumbnailPath: thumbnailPath,
      subtitlePath: subtitlePath,
      sourceUrl: sourceUrl,
      playlistUrl: playlistUrl,
      uploadDate: uploadDate,
    );
  }

  static String? extractVideoId(String? url) {
    if (url == null || url.isEmpty) return null;
    final regExp =
        RegExp(r'(?:v=|\/|youtu\.be\/|embed\/|shorts\/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  String? get youtubeId => extractVideoId(sourceUrl);

  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = fileSizeBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return '--:--';
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    final s = durationSeconds! % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedDisplayDate {
    if (uploadDate != null && uploadDate!.length == 8) {
      final y = uploadDate!.substring(0, 4);
      final m = uploadDate!.substring(4, 6);
      final d = uploadDate!.substring(6, 8);
      return '$d.$m.$y';
    }
    // Fallback to downloadedAt if no uploadDate exists
    return '${downloadedAt.day.toString().padLeft(2, '0')}.${downloadedAt.month.toString().padLeft(2, '0')}.${downloadedAt.year}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'fileSizeBytes': fileSizeBytes,
        'durationSeconds': durationSeconds,
        'uploader': uploader,
        'downloadedAt': downloadedAt.toIso8601String(),
        'thumbnailPath': thumbnailPath,
        'subtitlePath': subtitlePath,
        'sourceUrl': sourceUrl,
        'playlistUrl': playlistUrl,
        'uploadDate': uploadDate,
      };

  /// Sayısal alanı gösterimden bağımsız okur.
  ///
  /// `as int?` cast'i kayıtta double duran bir değerde (`12345.0`, eski sürüm
  /// verisi ya da başka bir yazıcı) TypeError fırlatıyordu. Bu istisna tek bir
  /// kaydı değil, çöp indeksinin TAMAMINI düşürüyor: StorageManager.loadTrashIndex
  /// listeyi tek `map` ile çözüyor ve hata yakalanınca boş liste dönüyor, yani
  /// kullanıcının çöpteki 50 videosu birden görünmez oluyordu.
  static int? _toIntOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Bozuk tarih tüm indeksi düşürmesin diye tolere edilir.
  ///
  /// Uydurma yapılmaz: çözülemeyen tarih "bilinmiyor" anlamında epoch olur,
  /// böylece kayıt en eski gibi sıralanır. `DateTime.now()` dönmek kaydı taze
  /// göstererek sıralamayı ve tarih rozetini yalanlardı.
  static DateTime _toDate(dynamic v) {
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        fileSizeBytes: _toIntOrNull(json['fileSizeBytes']) ?? 0,
        durationSeconds: _toIntOrNull(json['durationSeconds']),
        uploader: json['uploader'] as String?,
        downloadedAt: _toDate(json['downloadedAt']),
        thumbnailPath: json['thumbnailPath'] as String?,
        subtitlePath: json['subtitlePath'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        playlistUrl: json['playlistUrl'] as String?,
        uploadDate: json['uploadDate'] as String?,
      );
}
