import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/video_item.dart';
import '../../providers/library_provider.dart';
import '../theme/amoled_theme.dart';
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
            icon: const Icon(Icons.refresh_rounded, color: AmoledTheme.pureWhite),
            onPressed: () => library.refresh(),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Summary Header
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

          // Video List
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
                            return VideoTile(
                              video: video,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlayerScreen(video: video),
                                  ),
                                );
                              },
                              onDelete: () => _confirmDelete(context, video),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, VideoItem video) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Videoyu Sil',
            style: TextStyle(color: AmoledTheme.pureWhite)),
        content: Text(
          '${video.title} cihazınızdan kalıcı olarak silinecek. Emin misiniz?',
          style: const TextStyle(color: AmoledTheme.subText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AmoledTheme.subText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5555),
              foregroundColor: AmoledTheme.pureWhite,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LibraryProvider>().deleteVideo(video);
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
