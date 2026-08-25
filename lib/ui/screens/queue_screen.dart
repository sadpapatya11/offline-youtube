import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/download_task.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../theme/amoled_theme.dart';
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

class QueueScreenState extends State<QueueScreen> with SingleTickerProviderStateMixin {
  // Uyarı bandı renkleri. AmoledTheme'de karşılığı yok; sihirli literal
  // gömmemek için sınıf düzeyinde adlandırıldı.
  static const Color _noticeBackground = Color(0xFF2A1F00);
  static const Color _noticeBorder = Color(0xFFFFB300);
  static const Color _noticeText = Color(0xFFFFD54F);

  final ScrollController _scrollController = ScrollController();
  QueueFilter _selectedFilter = QueueFilter.all;

  bool _showPopup = false;
  String _popupText = '';
  late AnimationController _animController;
  late Animation<double> _iconMoveAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 400),
    );
    _iconMoveAnim = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _animController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleQueueState(DownloadProvider provider, SettingsProvider settings) {
    final isPaused = provider.isQueuePaused;
    if (isPaused) {
      provider.resumeQueue(settings: settings.settings);
      _showTempPopup('Devam ediyor');
    } else {
      provider.pauseQueue();
      _showTempPopup('Duraklatıldı');
    }
  }

  void _showTempPopup(String text) {
    setState(() {
      _popupText = text;
      _showPopup = true;
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showPopup = false;
        });
      }
    });
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

  /// Kuyruğun SESSİZCE durduğu ve açılışta kayıt düştüğü durumları gösterir.
  ///
  /// Bu bandın olmaması gerçek bir kayıptı: geçici engelde (ağ izni yok, kota
  /// ölçülemedi, ön plan servisi reddetti) kuyruk motoru artık görevi hataya
  /// düşürmüyor, `queued` bırakıp nedeni yayınlıyor. Neden hiçbir yerde
  /// gösterilmeyince kullanıcı yalnız "hiçbir şey inmiyor" görüyor, kırmızı
  /// bir hata satırı bile çıkmıyordu. Sinyalin tüketicisi burasıdır.
  Widget _buildQueueNoticeBanner(DownloadProvider provider) {
    final List<Widget> notices = [];

    // Engel nedeni yalnız BEKLEYEN iş varken gösterilir: kuyruk boşken soğuk
    // açılışta "Ayarlar henüz yüklenmedi" gibi geçici bir neden yazılıyor ve
    // kullanıcıya olmayan bir sorun bildiriliyordu.
    final hasPendingWork =
        provider.tasks.any((t) => t.status == DownloadStatus.queued);
    final blockReason = provider.blockReason;
    if (hasPendingWork && blockReason != null && blockReason.isNotEmpty) {
      notices.add(_buildNoticeRow(
        icon: Icons.pause_circle_filled_rounded,
        text: blockReason,
      ));
    }

    if (provider.queueRecordUnreadable) {
      if (notices.isNotEmpty) notices.add(const SizedBox(height: 8));
      notices.add(_buildNoticeRow(
        icon: Icons.error_outline_rounded,
        text: 'Kayıtlı kuyruk okunamadı ve sıfırdan başlatıldı. '
            'İndirmelerinizi yeniden eklemeniz gerekiyor.',
        onDismiss: provider.acknowledgeQueueLoadNotice,
      ));
    } else if (provider.droppedTaskCount > 0) {
      if (notices.isNotEmpty) notices.add(const SizedBox(height: 8));
      notices.add(_buildNoticeRow(
        icon: Icons.warning_amber_rounded,
        text: '${provider.droppedTaskCount} görev kaydı okunamadığı için '
            'kuyruktan düştü. Bu videoları yeniden eklemeniz gerekebilir.',
        onDismiss: provider.acknowledgeQueueLoadNotice,
      ));
    }

    if (notices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _noticeBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _noticeBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: notices,
        ),
      ),
    );
  }

  Widget _buildNoticeRow({
    required IconData icon,
    required String text,
    VoidCallback? onDismiss,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _noticeBorder, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _noticeText,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close_rounded, color: _noticeText, size: 16),
            ),
          ),
      ],
    );
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

    final isQueuePaused = downloadProvider.isQueuePaused;

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
          IconButton(
            icon: downloadProvider.isSyncingPlaylists 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            tooltip: 'Oynatma Listelerini Şimdi Eşitle',
            onPressed: downloadProvider.isSyncingPlaylists 
                ? null 
                : () async {
                    final settings = context.read<SettingsProvider>().settings;
                    final libraryProvider = context.read<LibraryProvider>();
                    await downloadProvider.syncSavedPlaylists(
                      settings: settings,
                      libraryProvider: libraryProvider,
                    );
                  },
          ),
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
      floatingActionButton: allTasks.isEmpty ? null : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: _showPopup ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isQueuePaused ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (isQueuePaused ? Colors.red : Colors.green).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Text(
                _popupText,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          FloatingActionButton(
            backgroundColor: isQueuePaused ? Colors.red : Colors.green,
            onPressed: () => _toggleQueueState(downloadProvider, settingsProvider),
            child: isQueuePaused
                ? const Icon(Icons.pause_rounded, color: Colors.white, size: 28)
                : AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_iconMoveAnim.value, 0),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      );
                    },
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQueueNoticeBanner(downloadProvider),
          Expanded(
            child: allTasks.isEmpty
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
                                        onPrioritize: () =>
                                            downloadProvider.prioritizeTask(task.id),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
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

}
