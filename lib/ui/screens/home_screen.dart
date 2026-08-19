import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/snackbar_helper.dart';
import '../../models/playlist_entry.dart';
import 'playlist_selection_screen.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
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
    String? textToUse;

    // Eğer kutuda bir metin varsa onu kullan
    if (_urlController.text.trim().isNotEmpty) {
      textToUse = _urlController.text.trim();
    } else {
      // Yoksa panodan al
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      textToUse = data?.text?.trim();
    }

    if (textToUse != null && textToUse.isNotEmpty && DownloadProvider.isValidYouTubeUrl(textToUse)) {
      _urlController.text = textToUse;
      _triggerDownload(textToUse);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir YouTube bağlantısı girin veya kopyalayın.'),
          backgroundColor: Color(0xFF330000),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _triggerDownload(String url) async {
    final cleanUrl = DownloadProvider.extractYouTubeUrl(url);
    if (cleanUrl == null) {
      SnackbarHelper.showTop(
        context,
        'Lütfen geçerli bir YouTube video veya liste linki girin.',
        backgroundColor: const Color(0xFF330000),
      );
      return;
    }

    if (_urlController.text != cleanUrl) {
      _urlController.text = cleanUrl;
    }

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

    if (error == 'PLAYLIST_URL') {
      final result = await downloadProvider.resolvePlaylist(
        url: cleanUrl,
        settings: settingsProvider.settings,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (result.entries.isEmpty) {
          SnackbarHelper.showTop(
            context,
            'Oynatma listesinde indirilebilir video bulunamadı veya tümü zaten indirilmiş.',
            backgroundColor: const Color(0xFF330000),
          );
        } else {
          // Kullanıcının isteği: Sadece en güncel olan 1 adet videoyu kuyruğa ekle.
          // result.entries zaten indirilmemiş olan videoları en güncelden eskiye sıralı şekilde getiriyor.
          final selected = result.entries.take(1).toList();

          final addError = await downloadProvider.addSelectedEntries(
            entries: selected,
            settings: settingsProvider.settings,
            sourcePlaylistUrl: cleanUrl,
            truncatedCount: result.truncatedCount,
            totalCount: result.totalCount,
          );

          if (!mounted) return;

          if (addError != null) {
            SnackbarHelper.showTop(
              context,
              addError,
              backgroundColor: const Color(0xFF330000),
            );
          } else {
            _urlController.clear();
            SnackbarHelper.showTop(
              context,
              '⚡ En güncel video kuyruğa eklendi! (Kalan yeni video sayısı: ${result.entries.length - 1})',
              backgroundColor: const Color(0xFF003311),
              duration: const Duration(seconds: 2),
              action: SnackBarAction(
                label: 'Kuyruğu Gör',
                textColor: AmoledTheme.pureWhite,
                onPressed: widget.onNavigateToQueue,
              ),
            );
          }
        }
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (error != null) {
        SnackbarHelper.showTop(
          context,
          error,
          backgroundColor: const Color(0xFF330000),
        );
      } else {
        _urlController.clear();
        SnackbarHelper.showTop(
          context,
          '⚡ Video kuyruğa eklendi!',
          backgroundColor: const Color(0xFF003311),
          action: SnackBarAction(
            label: 'Kuyruğu Gör',
            textColor: AmoledTheme.pureWhite,
            onPressed: widget.onNavigateToQueue,
          ),
        );
      }
    }
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
