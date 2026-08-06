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
                              key: Key(video.id),
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
                                      'Sil',
                                      style: TextStyle(
                                        color: AmoledTheme.pureWhite,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
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
                                    content: Text('🗑️ "$title" silindi.'),
                                    duration: const Duration(seconds: 4),
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
}
