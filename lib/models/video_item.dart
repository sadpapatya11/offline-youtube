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

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        durationSeconds: json['durationSeconds'] as int?,
        uploader: json['uploader'] as String?,
        downloadedAt: DateTime.parse(json['downloadedAt'] as String),
        thumbnailPath: json['thumbnailPath'] as String?,
        subtitlePath: json['subtitlePath'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        playlistUrl: json['playlistUrl'] as String?,
        uploadDate: json['uploadDate'] as String?,
      );
}
