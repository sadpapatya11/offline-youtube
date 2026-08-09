import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_settings.dart';
import '../../models/playlist_entry.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';
import 'playlist_selection_screen.dart';

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
    if (!mounted) return;
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && DownloadProvider.isValidYouTubeUrl(text)) {
      _urlController.text = text;
      _triggerDownload(text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Panoda geçerli bir YouTube bağlantısı bulunamadı.'),
          backgroundColor: Color(0xFF330000),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _triggerDownload(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    if (!DownloadProvider.isValidYouTubeUrl(cleanUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir YouTube video veya liste linki girin.'),
          backgroundColor: Color(0xFF330000),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final downloadProvider = context.read<DownloadProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final libraryProvider = context.read<LibraryProvider>();

    // Oynatma listesi / kanal bağlantısı: liste SESSİZCE kuyruğa dökülmez.
    // Önce çözümlenir, kullanıcı seçim ekranında ne indireceğine karar verir.
    if (DownloadProvider.isPlaylistUrl(cleanUrl)) {
      try {
        await _handlePlaylistSelection(
            cleanUrl, downloadProvider, settingsProvider.settings);
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
      return;
    }

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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚡ İndirme otomatik olarak başlatıldı!'),
            backgroundColor: const Color(0xFF003311),
            duration: const Duration(seconds: 2),
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

  /// Oynatma listesi / kanal akışı: çözümle → kullanıcıya seçtir → kuyruğa ekle.
  ///
  /// Bağlantı verilir verilmez listenin tamamını kuyruğa dökmek yerine araya
  /// seçim ekranı girer. İptal edilirse hiçbir şey eklenmez.
  Future<void> _handlePlaylistSelection(
    String url,
    DownloadProvider downloadProvider,
    AppSettings settings,
  ) async {
    final PlaylistFetchResult result;
    try {
      result =
          await downloadProvider.resolvePlaylist(url: url, settings: settings);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Oynatma listesi okunamadı: ${DownloadProvider.cleanErrorMessage(e)}'),
          backgroundColor: const Color(0xFF330000),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!mounted) return;

    if (result.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu bağlantıda indirilebilir video bulunamadı.'),
          backgroundColor: Color(0xFF330000),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final selected = await Navigator.of(context).push<List<PlaylistEntry>>(
      MaterialPageRoute(
        builder: (_) => PlaylistSelectionScreen(result: result),
      ),
    );

    if (!mounted) return;
    // null = iptal, boş = hiçbir şey seçilmedi. İkisinde de kuyruğa dokunulmaz.
    if (selected == null || selected.isEmpty) return;

    final message = await downloadProvider.addSelectedEntries(
      entries: selected,
      settings: settings,
      sourcePlaylistUrl: result.sourceUrl,
      truncatedCount: result.truncatedCount,
      totalCount: result.totalCount,
    );

    if (!mounted) return;

    _urlController.clear();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // "ℹ️" ile başlayan metin bilgi mesajıdır (kısmi ekleme), hata değil.
    final isInfo = message == null || message.startsWith('ℹ️');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ??
            '⚡ ${selected.length} video kuyruğa eklendi, indirme başladı!'),
        backgroundColor:
            isInfo ? const Color(0xFF003311) : const Color(0xFF330000),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Kuyruğu Gör',
          textColor: AmoledTheme.pureWhite,
          onPressed: widget.onNavigateToQueue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Yeni İndirme',
          style: TextStyle(
            color: AmoledTheme.pureWhite,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          'YouTube İndirici',
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
                    'Bağlantıyı yapıştırdığınız an video veya oynatma listesi en yüksek kalitede otomatik olarak indirilmeye başlar.',
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
                                tooltip: 'Listeyi Aç ve İndirilecekleri Seç',
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
