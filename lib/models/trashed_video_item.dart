import 'video_item.dart';

class TrashedVideoItem {
  final VideoItem video;
  final DateTime deletedAt;

  TrashedVideoItem({
    required this.video,
    required this.deletedAt,
  });

  Duration get remainingTime {
    final expiry = deletedAt.add(const Duration(hours: 24));
    final diff = expiry.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired => remainingTime == Duration.zero;

  String get formattedRemainingTime {
    final diff = remainingTime;
    if (diff == Duration.zero) return 'Kalıcı olarak silinecek';
    if (diff.inHours > 0) {
      return '${diff.inHours} sa ${diff.inMinutes % 60} dk kaldı';
    }
    return '${diff.inMinutes} dk kaldı';
  }

  Map<String, dynamic> toJson() => {
        'video': video.toJson(),
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory TrashedVideoItem.fromJson(Map<String, dynamic> json) =>
      TrashedVideoItem(
        video: VideoItem.fromJson(json['video'] as Map<String, dynamic>),
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );
}
