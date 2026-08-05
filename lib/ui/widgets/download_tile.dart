import 'package:flutter/material.dart';
import '../../models/download_task.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  const DownloadTile({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AmoledCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AmoledTheme.accentGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getStatusIcon(),
                  color: AmoledTheme.pureWhite,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStatusLabel(),
                      style: TextStyle(
                        color: _getStatusColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildActionButtons(),
            ],
          ),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress / 100.0 : null,
                backgroundColor: AmoledTheme.accentGray,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${task.progress.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (task.speed.isNotEmpty)
                  Text(
                    task.speed,
                    style: const TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 12,
                    ),
                  ),
                if (task.etaSeconds > 0)
                  Text(
                    'Kalan: ${task.formattedEta}',
                    style: const TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
          if (task.status == DownloadStatus.error && task.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              task.errorMessage!,
              style: const TextStyle(
                color: Color(0xFFFF5555),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (task.status == DownloadStatus.downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline, color: AmoledTheme.pureWhite),
            onPressed: onPause,
            tooltip: 'Duraklat',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Color(0xFF888888)),
            onPressed: onCancel,
            tooltip: 'İptal Et',
          ),
        ],
      );
    } else if (task.status == DownloadStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: AmoledTheme.pureWhite),
            onPressed: onResume,
            tooltip: 'Devam Et',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Color(0xFF888888)),
            onPressed: onCancel,
            tooltip: 'İptal Et',
          ),
        ],
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.delete_outline, color: Color(0xFF888888)),
        onPressed: onDelete,
        tooltip: 'Listeden Kaldır',
      );
    }
  }

  IconData _getStatusIcon() {
    switch (task.status) {
      case DownloadStatus.fetchingMetadata:
        return Icons.hourglass_top_rounded;
      case DownloadStatus.queued:
        return Icons.queue_rounded;
      case DownloadStatus.downloading:
        return Icons.download_rounded;
      case DownloadStatus.paused:
        return Icons.pause_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_rounded;
      case DownloadStatus.error:
        return Icons.error_outline_rounded;
      case DownloadStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  String _getStatusLabel() {
    switch (task.status) {
      case DownloadStatus.fetchingMetadata:
        return 'Bilgiler alınıyor...';
      case DownloadStatus.queued:
        return 'Sırada bekliyor';
      case DownloadStatus.downloading:
        return 'İndiriliyor';
      case DownloadStatus.paused:
        return 'Duraklatıldı';
      case DownloadStatus.completed:
        return 'Tamamlandı';
      case DownloadStatus.error:
        return 'Hata oluştu';
      case DownloadStatus.cancelled:
        return 'İptal edildi';
    }
  }

  Color _getStatusColor() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return AmoledTheme.pureWhite;
      case DownloadStatus.paused:
        return const Color(0xFFFFCC00);
      case DownloadStatus.completed:
        return const Color(0xFF00FF66);
      case DownloadStatus.error:
        return const Color(0xFFFF5555);
      default:
        return AmoledTheme.subText;
    }
  }
}
