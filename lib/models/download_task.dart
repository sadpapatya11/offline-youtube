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
  bool hadPreviousError;
  String? totalSize;
  String? downloadedSize;
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
    this.hadPreviousError = false,
    this.totalSize,
    this.downloadedSize,
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

  String get formattedSizeInfo {
    // 1. İndirme esnasında hem indirilen hem toplam boyut varsa (örn: "45.2 MB / 120.5 MB")
    if (status == DownloadStatus.downloading &&
        downloadedSize != null &&
        downloadedSize!.isNotEmpty &&
        totalSize != null &&
        totalSize!.isNotEmpty) {
      return '$downloadedSize / $totalSize';
    }

    // 2. Sadece toplam boyut varsa (örn: "120.5 MB")
    if (totalSize != null && totalSize!.isNotEmpty) {
      return totalSize!;
    }

    // 3. Metadata'dan gelen tahmini/gerçek bayt boyutu varsa
    if (estimatedSizeBytes != null && estimatedSizeBytes! > 0) {
      final bytes = estimatedSizeBytes!;
      if (bytes >= 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    // 4. Süreye göre yaklaşık dosya boyutu tahmini (~1.8 MB/dakika)
    if (durationSeconds != null && durationSeconds! > 0) {
      final estimatedMB = (durationSeconds! / 60) * 1.8;
      if (estimatedMB >= 1024) {
        return '~${(estimatedMB / 1024).toStringAsFixed(2)} GB';
      }
      return '~${estimatedMB.toStringAsFixed(1)} MB';
    }

    return '';
  }

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? speed,
    int? etaSeconds,
    String? errorMessage,
    bool? hadPreviousError,
    String? totalSize,
    String? downloadedSize,
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
      hadPreviousError: hadPreviousError ?? this.hadPreviousError,
      totalSize: totalSize ?? this.totalSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
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
      'hadPreviousError': hadPreviousError,
      'totalSize': totalSize,
      'downloadedSize': downloadedSize,
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
      hadPreviousError: json['hadPreviousError'] as bool? ??
          (parsedStatus == DownloadStatus.error ||
              json['errorMessage'] != null),
      totalSize: json['totalSize'] as String?,
      downloadedSize: json['downloadedSize'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
