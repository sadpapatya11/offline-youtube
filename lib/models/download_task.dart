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
  String? thumbnail;
  int? durationSeconds;
  String? uploader;
  int? estimatedSizeBytes;
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
    this.uploader,
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
    String? thumbnail,
    int? durationSeconds,
    String? uploader,
    int? estimatedSizeBytes,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title ?? this.title,
      thumbnail: thumbnail ?? this.thumbnail,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      uploader: uploader ?? this.uploader,
      estimatedSizeBytes: estimatedSizeBytes ?? this.estimatedSizeBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'thumbnail': thumbnail,
      'durationSeconds': durationSeconds,
      'uploader': uploader,
      'estimatedSizeBytes': estimatedSizeBytes,
      'status': status.name,
      'progress': progress,
      'speed': speed,
      'etaSeconds': etaSeconds,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    DownloadStatus parsedStatus = DownloadStatus.queued;
    try {
      parsedStatus = DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.queued,
      );
    } catch (_) {
      parsedStatus = DownloadStatus.queued;
    }

    return DownloadTask(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      thumbnail: json['thumbnail'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      uploader: json['uploader'] as String?,
      estimatedSizeBytes: json['estimatedSizeBytes'] as int?,
      status: parsedStatus,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speed: json['speed'] as String? ?? '',
      etaSeconds: (json['etaSeconds'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
