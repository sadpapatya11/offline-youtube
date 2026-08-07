import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/download_task.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';
import '../widgets/amoled_fast_scroller.dart';
import '../widgets/download_tile.dart';

enum QueueFilter {
  all,
  downloading,
  queued,
  error,
  completed,
  cancelled,
}

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => QueueScreenState();
}

class QueueScreenState extends State<QueueScreen> {
  final ScrollController _scrollController = ScrollController();
  QueueFilter _selectedFilter = QueueFilter.all;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final allTasks = downloadProvider.tasks;

    final hasErrors = allTasks.any((t) => t.status == DownloadStatus.error);
    final hasCompleted = allTasks.any((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled);

    final isWifiWaiting = downloadProvider.isWifiWaiting;
    final isQueuePaused = downloadProvider.isQueuePaused;
    final isDownloading = downloadProvider.isDownloadingActive;

    // Filter counts
    final runningCount = allTasks
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.fetchingMetadata)
        .length;
    final queuedCount = allTasks
        .where((t) =>
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.paused)
        .length;
    final errorCount =
        allTasks.where((t) => t.status == DownloadStatus.error).length;
    final completedCount =
        allTasks.where((t) => t.status == DownloadStatus.completed).length;
    final cancelledCount =
        allTasks.where((t) => t.status == DownloadStatus.cancelled).length;

    // Filtered list
    final filteredTasks = allTasks.where((t) {
      switch (_selectedFilter) {
        case QueueFilter.all:
          return true;
        case QueueFilter.downloading:
          return t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.fetchingMetadata;
        case QueueFilter.queued:
          return t.status == DownloadStatus.queued ||
              t.status == DownloadStatus.paused;
        case QueueFilter.error:
          return t.status == DownloadStatus.error;
        case QueueFilter.completed:
          return t.status == DownloadStatus.completed;
        case QueueFilter.cancelled:
          return t.status == DownloadStatus.cancelled;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('İNDİRME KUYRUĞU'),
        actions: [
          if (hasErrors) ...[
            IconButton(
              icon: const Icon(Icons.replay_rounded, color: Color(0xFF00E676)),
              tooltip: 'Hataları Tekrar Dene',
              onPressed: () => downloadProvider.retryAllErrors(
                  settings: settingsProvider.settings),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: Color(0xFFFF5252)),
              tooltip: 'Hataları Temizle',
              onPressed: () => downloadProvider.clearErrors(),
            ),
          ],
          if (hasCompleted || allTasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded,
                  color: AmoledTheme.pureWhite),
              tooltip: 'Tamamlananları Temizle',
              onPressed: () => downloadProvider.clearCompleted(),
            ),
        ],
      ),
      body: allTasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AmoledTheme.cardDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: AmoledTheme.accentGray),
                    ),
                    child: const Icon(
                      Icons.cloud_download_outlined,
                      size: 56,
                      color: AmoledTheme.subText,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Kuyrukta bekleyen indirme yok',
                    style: TextStyle(
                      color: AmoledTheme.pureWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ana sayfadan bir video veya oynatma listesi ekleyin',
                    style: TextStyle(
                      color: AmoledTheme.subText.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 1. MASTER KUYRUK KONTROL KARTI
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: AmoledCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _buildStatusIndicator(
                                  isWifiWaiting: isWifiWaiting,
                                  isPaused: isQueuePaused,
                                  isDownloading: isDownloading,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusTitle(
                                    isWifiWaiting: isWifiWaiting,
                                    isPaused: isQueuePaused,
                                    isDownloading: isDownloading,
                                  ),
                                  style: const TextStyle(
                                    color: AmoledTheme.pureWhite,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AmoledTheme.pureBlack,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AmoledTheme.accentGray),
                              ),
                              child: Text(
                                '${allTasks.length} Görev',
                                style: const TextStyle(
                                  color: AmoledTheme.subText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isQueuePaused
                                      ? const Color(0xFF00E676)
                                      : const Color(0xFFFFCC00),
                                  foregroundColor: Colors.black,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  isQueuePaused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  isQueuePaused
                                      ? 'Kuyruğu Devam Ettir'
                                      : 'Tüm Kuyruğu Duraklat',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                                onPressed: () {
                                  if (isQueuePaused) {
                                    downloadProvider.resumeQueue(
                                        settings: settingsProvider.settings);
                                  } else {
                                    downloadProvider.pauseQueue();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. KUYRUK KATEGORİ SEKMELERİ (FİLTRELER)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        filter: QueueFilter.all,
                        label: 'Tümü',
                        count: allTasks.length,
                        activeColor: AmoledTheme.pureWhite,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        filter: QueueFilter.downloading,
                        label: 'Çalışıyor',
                        count: runningCount,
                        activeColor: const Color(0xFF00E676),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        filter: QueueFilter.queued,
                        label: 'Kuyrukta',
                        count: queuedCount,
                        activeColor: const Color(0xFFFFCC00),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        filter: QueueFilter.error,
                        label: 'Hata Oluştu',
                        count: errorCount,
                        activeColor: const Color(0xFFFF5252),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        filter: QueueFilter.completed,
                        label: 'Tamamlandı',
                        count: completedCount,
                        activeColor: const Color(0xFF00E676),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        filter: QueueFilter.cancelled,
                        label: 'İptal Edildi',
                        count: cancelledCount,
                        activeColor: const Color(0xFF888888),
                      ),
                    ],
                  ),
                ),

                const Divider(color: AmoledTheme.borderDark, height: 1),

                // 3. GÖREV LİSTESİ
                Expanded(
                  child: filteredTasks.isEmpty
                      ? Center(
                          child: Text(
                            'Bu filtrede gösterilecek görev yok',
                            style: TextStyle(
                              color: AmoledTheme.subText.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : AmoledFastScroller(
                          controller: _scrollController,
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredTasks.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final task = filteredTasks[index];
                              return Dismissible(
                                key: Key('queue_task_${task.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5252),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Kuyruktan Çıkar',
                                        style: TextStyle(
                                          color: AmoledTheme.pureWhite,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        color: AmoledTheme.pureWhite,
                                        size: 24,
                                      ),
                                    ],
                                  ),
                                ),
                                onDismissed: (_) {
                                  downloadProvider.removeTask(task.id);
                                },
                                child: DownloadTile(
                                  task: task,
                                  onPause: () =>
                                      downloadProvider.pauseTask(task.id),
                                  onResume: () => downloadProvider.resumeTask(
                                    task.id,
                                    settingsProvider.settings,
                                  ),
                                  onCancel: () =>
                                      downloadProvider.cancelTask(task.id),
                                  onDelete: () =>
                                      downloadProvider.removeTask(task.id),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip({
    required QueueFilter filter,
    required String label,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = _selectedFilter == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : AmoledTheme.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : AmoledTheme.borderDark,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : AmoledTheme.subText,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.black : AmoledTheme.pureWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required bool isWifiWaiting,
    required bool isPaused,
    required bool isDownloading,
  }) {
    if (isWifiWaiting) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFFF9900),
          shape: BoxShape.circle,
        ),
      );
    }
    if (isPaused) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFFFCC00),
          shape: BoxShape.circle,
        ),
      );
    }
    if (isDownloading) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFF00E676),
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: AmoledTheme.accentGray,
        shape: BoxShape.circle,
      ),
    );
  }

  String _getStatusTitle({
    required bool isWifiWaiting,
    required bool isPaused,
    required bool isDownloading,
  }) {
    if (isWifiWaiting) return 'Wi-Fi Bağlantısı Bekleniyor';
    if (isPaused) return 'Kuyruk Duraklatıldı';
    if (isDownloading) return 'İndirme Aktif Çalışıyor';
    return 'Kuyruk Hazır';
  }
}
