import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/download_task.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';
import '../widgets/download_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final tasks = downloadProvider.tasks;
    final hasErrors = tasks.any((t) => t.status == DownloadStatus.error);
    final hasCompleted = tasks.any((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled);

    final isWifiWaiting = downloadProvider.isWifiWaiting;
    final isQueuePaused = downloadProvider.isQueuePaused;
    final isDownloading = downloadProvider.isDownloadingActive;

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
          if (hasCompleted || tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded,
                  color: AmoledTheme.pureWhite),
              tooltip: 'Tamamlananları Temizle',
              onPressed: () => downloadProvider.clearCompleted(),
            ),
        ],
      ),
      body: tasks.isEmpty
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: AmoledCard(
                    padding: const EdgeInsets.all(16),
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
                                '${tasks.length} Görev',
                                style: const TextStyle(
                                  color: AmoledTheme.subText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
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
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(
                                  isQueuePaused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  isQueuePaused
                                      ? 'Kuyruğu Başlat'
                                      : 'Kuyruğu Duraklat',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
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

                // 2. Wİ-Fİ BEKLENİYOR UYARI BANNERI
                if (isWifiWaiting)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1E00),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFFFB300), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: Color(0xFFFFB300), size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Mobil Veri Koruması Aktif: Sadece Wi-Fi ile indirme kuralı seçili. Wi-Fi bağlantısı bekleniyor.',
                              style: TextStyle(
                                color: Color(0xFFFFE082),
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 3. GÖREV LİSTESİ (KAYDIRARAK SİLME DESTEKLİ)
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: tasks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Dismissible(
                        key: Key('queue_task_${task.id}'),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.white, size: 26),
                              SizedBox(width: 8),
                              Text(
                                'Kuyruktan Kaldır',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Kuyruktan Kaldır',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.white, size: 26),
                            ],
                          ),
                        ),
                        onDismissed: (direction) {
                          downloadProvider.removeTask(task.id);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('"${task.title}" kuyruktan kaldırıldı.'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: DownloadTile(
                          task: task,
                          onPause: () => downloadProvider.pauseTask(task.id),
                          onResume: () => downloadProvider.resumeTask(
                              task.id, settingsProvider.settings),
                          onCancel: () => downloadProvider.cancelTask(task.id),
                          onDelete: () => downloadProvider.removeTask(task.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusIndicator({
    required bool isWifiWaiting,
    required bool isPaused,
    required bool isDownloading,
  }) {
    Color color;
    IconData icon;

    if (isWifiWaiting) {
      color = const Color(0xFFFFB300);
      icon = Icons.wifi_lock_rounded;
    } else if (isPaused) {
      color = const Color(0xFFFFCC00);
      icon = Icons.pause_circle_filled_rounded;
    } else if (isDownloading) {
      color = const Color(0xFF00E676);
      icon = Icons.downloading_rounded;
    } else {
      color = AmoledTheme.subText;
      icon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  String _getStatusTitle({
    required bool isWifiWaiting,
    required bool isPaused,
    required bool isDownloading,
  }) {
    if (isWifiWaiting) {
      return 'Wi-Fi BAĞLANTISI BEKLENİYOR';
    } else if (isPaused) {
      return 'KUYRUK DURAKLATILDI';
    } else if (isDownloading) {
      return 'İNDİRME DEVAM EDİYOR';
    } else {
      return 'KUYRUK HAZIR';
    }
  }
}
