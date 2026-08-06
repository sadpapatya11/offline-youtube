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
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Büyük 16:9 Thumbnail ve Süre Rozeti
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasLocalThumb)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.file(
                      File(video.thumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AmoledTheme.cardDark,
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            color: AmoledTheme.subText,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF141414),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        color: AmoledTheme.subText,
                        size: 48,
                      ),
                    ),
                  ),

                // Play Buton Rozeti (Orta)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AmoledTheme.pureWhite,
                      size: 28,
                    ),
                  ),
                ),

                // Süre Rozeti (Sağ Alt)
                if (video.formattedDuration != '--:--')
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        video.formattedDuration,
                        style: const TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                // Türkçe Altyazı Rozeti (Sol Alt)
                if (video.subtitlePath != null)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF003311),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF00E676)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.subtitles_rounded, color: Color(0xFF00E676), size: 12),
                          SizedBox(width: 4),
                          Text(
                            'TR ALTYAZI',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Video Başlığı, Kanal, Boyut ve İndirme Tarihi Bilgileri
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                if (video.uploader != null && video.uploader!.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.account_circle_outlined,
                        size: 14,
                        color: AmoledTheme.subText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          video.uploader!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AmoledTheme.subText,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162518),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        video.formattedSize,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '•',
                      style: TextStyle(color: AmoledTheme.borderDark),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AmoledTheme.subText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateFormat.format(video.downloadedAt),
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
