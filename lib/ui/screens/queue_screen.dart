import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/download_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final tasks = downloadProvider.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İNDİRME KUYRUĞU'),
        actions: [
          if (tasks.isNotEmpty)
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
                  const Icon(
                    Icons.cloud_download_outlined,
                    size: 64,
                    color: Color(0xFF444444),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Kuyrukta aktif indirme yok',
                    style: TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ana sayfadan bir video URL\'si ekleyin',
                    style: TextStyle(
                      color: AmoledTheme.subText.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return DownloadTile(
                  task: task,
                  onPause: () => downloadProvider.pauseTask(task.id),
                  onResume: () => downloadProvider.resumeTask(
                      task.id, settingsProvider.settings),
                  onCancel: () => downloadProvider.cancelTask(task.id),
                  onDelete: () => downloadProvider.removeTask(task.id),
                );
              },
            ),
    );
  }
}
