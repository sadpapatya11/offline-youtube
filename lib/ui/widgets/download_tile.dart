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
  final VoidCallback? onPrioritize;

  const DownloadTile({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onDelete,
    this.onPrioritize,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isError = task.status == DownloadStatus.error;
    final hasThumbnail = task.thumbnail != null && task.thumbnail!.isNotEmpty;

    return AmoledCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail or Icon Container
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getStatusBgColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getStatusColor().withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: hasThumbnail
                      ? Image.network(
                          task.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              _getStatusIcon(),
                              color: _getStatusColor(),
                              size: 24,
                            ),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: Icon(
                                _getStatusIcon(),
                                color: _getStatusColor(),
                                size: 24,
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(
                            _getStatusIcon(),
                            color: _getStatusColor(),
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusLabel(),
                            style: TextStyle(
                              color: _getStatusColor(),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (task.durationSeconds != null &&
                            task.durationSeconds! > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            task.formattedDuration,
                            style: const TextStyle(
                              color: AmoledTheme.subText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (task.formattedSizeInfo.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: AmoledTheme.subText,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AmoledTheme.accentGray,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sd_storage_outlined,
                                  size: 11,
                                  color: AmoledTheme.brandRed,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  task.formattedSizeInfo,
                                  style: const TextStyle(
                                    color: AmoledTheme.pureWhite,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _buildActionButtons(),
            ],
          ),
          if (isDownloading || isPaused) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress / 100.0 : null,
                backgroundColor: AmoledTheme.accentGray,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPaused ? const Color(0xFFFFCC00) : const Color(0xFF00E676),
                ),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${task.progress.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: isPaused
                            ? const Color(0xFFFFCC00)
                            : AmoledTheme.pureWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (task.formattedSizeInfo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${task.formattedSizeInfo})',
                        style: const TextStyle(
                          color: Color(0xFF81D4FA),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (task.speed.isNotEmpty)
                  Text(
                    task.speed,
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (task.etaSeconds > 0)
                  Text(
                    'Kalan: ${task.formattedEta}',
                    style: const TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ],
          if (isError && task.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A0000),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF550000)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFFF5555), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      task.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFF8888),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isPaused &&
              task.errorMessage != null &&
              task.errorMessage!.contains('Mobil veri koruması')) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1E00),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Color(0xFFFFB300), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      task.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFFE082),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
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
            icon: const Icon(Icons.pause_circle_outline,
                color: Color(0xFFFFCC00), size: 26),
            onPressed: onPause,
            tooltip: 'Duraklat',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFF888888), size: 22),
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
            icon: const Icon(Icons.play_circle_outline,
                color: Color(0xFF00E676), size: 26),
            onPressed: onResume,
            tooltip: 'Devam Et',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFF888888), size: 22),
            onPressed: onCancel,
            tooltip: 'İptal Et',
          ),
        ],
      );
    } else if (task.status == DownloadStatus.cancelled || task.status == DownloadStatus.error) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF64B5F6), size: 24),
            onPressed: onResume,
            tooltip: 'Yeniden Başlat',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color(0xFF888888), size: 22),
            onPressed: onDelete,
            tooltip: 'Listeden Kaldır',
          ),
        ],
      );
    } else {
      final isQueued = task.status == DownloadStatus.queued;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isQueued && onPrioritize != null)
            IconButton(
              icon: const Icon(Icons.vertical_align_top_rounded,
                  color: Color(0xFF00E676), size: 24),
              onPressed: onPrioritize,
              tooltip: 'Önceliklendir (En Üste Taşı)',
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color(0xFF888888), size: 22),
            onPressed: onDelete,
            tooltip: 'Listeden Kaldır',
          ),
        ],
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
        return Icons.downloading_rounded;
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
        return 'Hata';
      case DownloadStatus.cancelled:
        return 'İptal edildi';
    }
  }

  Color _getStatusColor() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const Color(0xFF00E676);
      case DownloadStatus.paused:
        return const Color(0xFFFFCC00);
      case DownloadStatus.completed:
        return const Color(0xFF00E676);
      case DownloadStatus.error:
        return const Color(0xFFFF5555);
      case DownloadStatus.queued:
        return const Color(0xFF64B5F6);
      default:
        return AmoledTheme.subText;
    }
  }

  Color _getStatusBgColor() {
    return _getStatusColor().withValues(alpha: 0.1);
  }
}
