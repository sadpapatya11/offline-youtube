import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_settings.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/native_bridge.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToQueue;

  const HomeScreen({super.key, required this.onNavigateToQueue});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteAndAutoDownload() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && (text.startsWith('http://') || text.startsWith('https://') || text.contains('youtube') || text.contains('youtu.be'))) {
      _urlController.text = text;
      _triggerDownload(text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panoda geçerli bir YouTube bağlantısı bulunamadı.')),
      );
    }
  }

  Future<void> _triggerDownload(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    final downloadProvider = context.read<DownloadProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final libraryProvider = context.read<LibraryProvider>();

    final error = await downloadProvider.addDownload(
      url: cleanUrl,
      settings: settingsProvider.settings,
      currentStorageUsedBytes: libraryProvider.totalUsedBytes,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: const Color(0xFF330000),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _urlController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚡ İndirme otomatik olarak başlatıldı!'),
            backgroundColor: const Color(0xFF003311),
            action: SnackBarAction(
              label: 'Kuyruğu Gör',
              textColor: AmoledTheme.pureWhite,
              onPressed: widget.onNavigateToQueue,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final downloadProvider = context.watch<DownloadProvider>();
    final settings = settingsProvider.settings;

    final usedGB = (libraryProvider.totalUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    final maxGB = settings.maxStorageLimitGB;
    final activeDownloads = downloadProvider.tasks.where((t) =>
        t.status.name == 'downloading' ||
        t.status.name == 'fetchingMetadata' ||
        t.status.name == 'queued').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('OFFLINE YOUTUBE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: AmoledTheme.pureWhite),
            tooltip: 'yt-dlp Motorunu Güncelle',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('yt-dlp motoru güncelleniyor...')),
              );
              final success = await NativeBridge.instance.updateYtDlp();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'yt-dlp motoru güncellendi.'
                        : 'yt-dlp güncellemesi başarısız.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Storage Quick Status Banner
            AmoledCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.storage_rounded, color: AmoledTheme.pureWhite, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Depolama Kotası',
                          style: TextStyle(color: AmoledTheme.subText, fontSize: 11),
                        ),
                        Text(
                          '$usedGB GB / $maxGB GB',
                          style: const TextStyle(
                            color: AmoledTheme.pureWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: settings.networkMode == NetworkRestrictionMode.allNetworks
                          ? const Color(0xFF113311)
                          : const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: settings.networkMode == NetworkRestrictionMode.allNetworks
                            ? const Color(0xFF00FF66)
                            : AmoledTheme.accentGray,
                      ),
                    ),
                    child: Text(
                      settings.networkMode == NetworkRestrictionMode.allNetworks
                          ? 'Mobil + Wi-Fi'
                          : 'Sadece Wi-Fi',
                      style: TextStyle(
                        color: settings.networkMode == NetworkRestrictionMode.allNetworks
                            ? const Color(0xFF00FF66)
                            : AmoledTheme.subText,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Otomatik İndirme Kartı
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFFFFCC00), size: 22),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Otomatik İndirme & Senkronizasyon',
                          style: TextStyle(
                            color: AmoledTheme.pureWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF003311),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'OTOMATİK',
                          style: TextStyle(
                            color: Color(0xFF00FF66),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bağlantıyı yapıştırdığınız an otomatik olarak en son eklenen / en yeni videolar en önce ve en yüksek kalitede indirilmeye başlar.',
                    style: TextStyle(color: AmoledTheme.subText, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: AmoledTheme.pureWhite),
                    decoration: InputDecoration(
                      hintText: 'YouTube video veya oynatma listesi URL...',
                      prefixIcon: const Icon(Icons.link_rounded, color: AmoledTheme.subText),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_urlController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, color: AmoledTheme.subText),
                              onPressed: () {
                                _urlController.clear();
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    onSubmitted: (val) => _triggerDownload(val),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.content_paste_go_rounded, size: 20),
                          label: Text(_isProcessing ? 'Başlatılıyor...' : 'Yapıştır ve Hemen İndir'),
                          onPressed: _isProcessing ? null : _pasteAndAutoDownload,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Canlı İndirme Durumu Kartı
            if (activeDownloads.isNotEmpty) ...[
              AmoledCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Devam Eden İndirme (${activeDownloads.length})',
                              style: const TextStyle(
                                color: AmoledTheme.pureWhite,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: widget.onNavigateToQueue,
                          child: const Text('Tümünü Gör', style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...activeDownloads.take(2).map((task) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AmoledTheme.pureWhite, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: task.progress > 0 ? task.progress / 100.0 : null,
                                backgroundColor: AmoledTheme.accentGray,
                                valueColor: const AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    task.speed.isNotEmpty ? task.speed : 'İndiriliyor...',
                                    style: const TextStyle(color: AmoledTheme.subText, fontSize: 11),
                                  ),
                                  Text(
                                    '%${task.progress.toStringAsFixed(1)} | Kalan: ${task.formattedEta}',
                                    style: const TextStyle(color: AmoledTheme.subText, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Kaydedilen Oynatma Listeleri ve Kanallar
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.playlist_play_rounded, color: AmoledTheme.pureWhite, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Takip Edilen Listeler',
                            style: TextStyle(
                              color: AmoledTheme.pureWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_link_rounded, color: AmoledTheme.pureWhite),
                        tooltip: 'Oynatma Listesi Ekle',
                        onPressed: () => _showAddPlaylistDialog(context, settingsProvider),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (settings.savedPlaylists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Henüz kaydedilmiş liste yok. Sık takip ettiğiniz oynatma listelerini buraya ekleyerek tek dokunuşla en yeni videoları indirebilirsiniz.',
                        style: TextStyle(color: AmoledTheme.subText, fontSize: 12),
                      ),
                    )
                  else
                    ...settings.savedPlaylists.map((url) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.video_library_rounded, color: AmoledTheme.pureWhite, size: 20),
                          title: Text(
                            url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AmoledTheme.pureWhite, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.download_rounded, color: AmoledTheme.pureWhite),
                                tooltip: 'En Yenileri İndir',
                                onPressed: () => _triggerDownload(url),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AmoledTheme.subText),
                                tooltip: 'Listeden Kaldır',
                                onPressed: () => settingsProvider.removeSavedPlaylist(url),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPlaylistDialog(BuildContext context, SettingsProvider settingsProvider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AmoledTheme.cardDark,
        title: const Text('Oynatma Listesi Kaydet', style: TextStyle(color: AmoledTheme.pureWhite)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AmoledTheme.pureWhite),
          decoration: const InputDecoration(hintText: 'https://youtube.com/playlist?list=...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: AmoledTheme.subText)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                settingsProvider.addSavedPlaylist(text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
