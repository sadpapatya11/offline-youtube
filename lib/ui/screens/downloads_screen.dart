import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trashed_video_item.dart';
import '../../models/video_item.dart';
import '../../providers/library_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final allVideos = library.videos;

    final filteredVideos = _searchQuery.isEmpty
        ? allVideos
        : allVideos
            .where((v) =>
                v.title.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('İNDİRİLENLER'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: library.trashCount > 0,
              label: Text(
                '${library.trashCount}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFFFFCC00),
              textColor: Colors.black,
              child: const Icon(Icons.restore_from_trash_rounded,
                  color: AmoledTheme.pureWhite),
            ),
            tooltip: 'Geri Dönüşüm Kutusu',
            onPressed: () => _showTrashModal(context, library),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AmoledTheme.pureWhite),
            onPressed: () => library.refresh(),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Column(
        children: [
          // Arama & Özet Başlığı
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AmoledTheme.pureWhite),
                  decoration: InputDecoration(
                    hintText: 'İndirilen videolarda ara...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AmoledTheme.subText),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: AmoledTheme.subText),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Toplam ${allVideos.length} video',
                      style: const TextStyle(
                        color: AmoledTheme.subText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Kullanılan: ${library.formattedTotalUsed}',
                      style: const TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: AmoledTheme.borderDark, height: 1),

          // Video Listesi
          Expanded(
            child: library.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                    ),
                  )
                : filteredVideos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.video_library_outlined,
                              size: 64,
                              color: Color(0xFF444444),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Henüz indirilmiş video yok'
                                  : 'Aramanızla eşleşen video bulunamadı',
                              style: const TextStyle(
                                color: AmoledTheme.subText,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AmoledTheme.pureWhite,
                        backgroundColor: AmoledTheme.cardDark,
                        onRefresh: () => library.refresh(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredVideos.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final video = filteredVideos[index];
                            return Dismissible(
                              key: Key('download_video_${video.id}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: AmoledTheme.brandRed,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Geri Dönüşüme At',
                                      style: TextStyle(
                                        color: AmoledTheme.pureWhite,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.delete_sweep_rounded,
                                      color: AmoledTheme.pureWhite,
                                      size: 26,
                                    ),
                                  ],
                                ),
                              ),
                              onDismissed: (direction) {
                                final title = video.title;
                                context.read<LibraryProvider>().deleteVideo(video);
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '🗑️ "$title" Geri Dönüşüm Kutusu\'na taşındı (24 saat sonra silinir).'),
                                    duration: const Duration(seconds: 4),
                                    action: SnackBarAction(
                                      label: 'Geri Al',
                                      textColor: const Color(0xFF00E676),
                                      onPressed: () {
                                        final trashed = library.trashedVideos.firstWhere(
                                          (t) => t.video.id == video.id,
                                          orElse: () => TrashedVideoItem(
                                              video: video, deletedAt: DateTime.now()),
                                        );
                                        library.restoreVideo(trashed);
                                      },
                                    ),
                                  ),
                                );
                              },
                              child: VideoTile(
                                video: video,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PlayerScreen(video: video),
                                    ),
                                  );
                                },
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

  void _showTrashModal(BuildContext context, LibraryProvider library) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AmoledTheme.pureBlack,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return Consumer<LibraryProvider>(
          builder: (ctx, lib, _) {
            final trashedList = lib.trashedVideos;
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sürükleme Tutamacı
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AmoledTheme.accentGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Başlık & Bilgi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_delete_rounded,
                              color: Color(0xFFFFCC00), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Geri Dönüşüm Kutusu',
                            style: TextStyle(
                              color: AmoledTheme.pureWhite,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (trashedList.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text(
                            'Tümünü Temizle',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                backgroundColor: AmoledTheme.cardDark,
                                title: const Text('Tüm Çöpü Temizle',
                                    style: TextStyle(color: Colors.white)),
                                content: const Text(
                                  'Geri Dönüşüm Kutusundaki tüm videolar kalıcı olarak silinecektir. Bu işlem geri alınamaz.',
                                  style: TextStyle(color: AmoledTheme.subText),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Vazgeç',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('Kalıcı Olarak Sil',
                                        style: TextStyle(color: Color(0xFFFF5252))),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await lib.emptyTrash();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Silinen videolar 24 saat boyunca burada saklanır, ardından kalıcı olarak silinir.',
                    style: TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AmoledTheme.borderDark, height: 1),
                  const SizedBox(height: 12),

                  // Liste
                  Expanded(
                    child: trashedList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 48,
                                    color: AmoledTheme.subText.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Geri Dönüşüm Kutusu Boş',
                                  style: TextStyle(
                                    color: AmoledTheme.subText,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: trashedList.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 10),
                            itemBuilder: (c, i) {
                              final item = trashedList[i];
                              final video = item.video;
                              final hasThumb = video.thumbnailPath != null &&
                                  File(video.thumbnailPath!).existsSync();

                              return AmoledCard(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 56,
                                        height: 42,
                                        color: AmoledTheme.cardDark,
                                        child: hasThumb
                                            ? Image.file(
                                                File(video.thumbnailPath!),
                                                fit: BoxFit.cover,
                                              )
                                            : const Icon(
                                                Icons.movie_outlined,
                                                color: AmoledTheme.subText,
                                                size: 20,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            video.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AmoledTheme.pureWhite,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFCC00)
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '⏱️ ${item.formattedRemainingTime}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFCC00),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                video.formattedSize,
                                                style: const TextStyle(
                                                  color: AmoledTheme.subText,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.restore_rounded,
                                          color: Color(0xFF00E676), size: 24),
                                      tooltip: 'Geri Yükle',
                                      onPressed: () async {
                                        await lib.restoreVideo(item);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  '✅ "${video.title}" geri yüklendi.'),
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_forever_rounded,
                                          color: Color(0xFFFF5252),
                                          size: 22),
                                      tooltip: 'Kalıcı Sil',
                                      onPressed: () async {
                                        await lib.deletePermanently(item);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
