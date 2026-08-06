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
  });

  bool get exists => File(filePath).existsSync();

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
      );
}
