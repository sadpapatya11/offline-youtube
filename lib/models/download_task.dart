enum DownloadStatus {
  queued,
  fetchingMetadata,
  downloading,
  paused,
  completed,
  error,
  cancelled,
}

class DownloadTask {
  final String id;
  final String url;
  String title;
  final String? thumbnail;
  final int? durationSeconds;
  final int? estimatedSizeBytes;
  DownloadStatus status;
  double progress; // 0.0 - 100.0
  String speed;
  int etaSeconds;
  String? errorMessage;
  final DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    this.thumbnail,
    this.durationSeconds,
    this.estimatedSizeBytes,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speed = '',
    this.etaSeconds = 0,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get formattedEta {
    if (etaSeconds <= 0) return '--:--';
    final m = etaSeconds ~/ 60;
    final s = etaSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? speed,
    int? etaSeconds,
    String? errorMessage,
    String? title,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title ?? this.title,
      thumbnail: thumbnail,
      durationSeconds: durationSeconds,
      estimatedSizeBytes: estimatedSizeBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
    );
  }
}
