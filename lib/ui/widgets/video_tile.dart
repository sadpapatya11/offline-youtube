import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/video_item.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class VideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
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
          // Küçük Resim (Thumbnail) veya Play Rozeti
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 72,
              height: 50,
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
                  // Oynat ikonu rozeti
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
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
          // Başlık ve Bilgiler
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
          const SizedBox(width: 8),
          // Sağ tarafta oynatma yönlendirici ok
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF444444),
            size: 20,
          ),
        ],
      ),
    );
  }
}
