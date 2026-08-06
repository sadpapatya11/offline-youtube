import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/video_item.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class VideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final hasLocalThumb = video.thumbnailPath != null &&
        video.thumbnailPath!.isNotEmpty &&
        File(video.thumbnailPath!).existsSync();

    return AmoledCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail or Icon Container
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 68,
              height: 48,
              decoration: BoxDecoration(
                color: AmoledTheme.accentGray,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AmoledTheme.borderDark),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasLocalThumb)
                    Image.file(
                      File(video.thumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: AmoledTheme.pureWhite,
                          size: 28,
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: AmoledTheme.pureWhite,
                        size: 28,
                      ),
                    ),
                  // Subtle play icon badge overlay
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AmoledTheme.pureWhite,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      video.formattedSize,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '•',
                      style: TextStyle(color: AmoledTheme.borderDark),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateFormat.format(video.downloadedAt),
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert,
              color: AmoledTheme.subText,
              size: 20,
            ),
            onPressed: () => _showOptionsBottomSheet(context),
          ),
        ],
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AmoledTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AmoledTheme.borderDark),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AmoledTheme.borderDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: AmoledTheme.borderDark),
              ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded,
                    color: AmoledTheme.pureWhite),
                title: const Text('Videoyu Oynat',
                    style: TextStyle(color: AmoledTheme.pureWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF5555)),
                title: const Text('Videoyu Sil',
                    style: TextStyle(color: Color(0xFFFF5555))),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
