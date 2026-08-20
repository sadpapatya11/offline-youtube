import 'dart:io';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../models/video_item.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class VideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocalThumb = video.thumbnailPath != null &&
        video.thumbnailPath!.isNotEmpty &&
        File(video.thumbnailPath!).existsSync();

    final hasDuration =
        video.durationSeconds != null && video.durationSeconds! > 0;
    final hasUploader =
        video.uploader != null && video.uploader!.isNotEmpty;

    return AmoledCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: EdgeInsets.zero,
      borderColor: isSelected
          ? const Color(0xFF00E676)
          : (isSelectionMode ? const Color(0xFF333333) : null),
      backgroundColor: isSelected ? const Color(0xFF0D2314) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 16:9 Thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasLocalThumb)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(14)),
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
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        color: AmoledTheme.subText,
                        size: 48,
                      ),
                    ),
                  ),

                // Play Butonu (seçim modunda değilse)
                if (!isSelectionMode)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AmoledTheme.pureWhite,
                        size: 24,
                      ),
                    ),
                  ),

                // Seçim onay kutusu (sağ üst)
                if (isSelectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00E676)
                            : Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00E676)
                              : Colors.white70,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.circle_outlined,
                        size: 18,
                        color:
                            isSelected ? Colors.black : Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Bilgi Alanı
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Kanal (varsa)
                if (hasUploader) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.account_circle_outlined,
                        size: 12,
                        color: AmoledTheme.subText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          video.uploader!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AmoledTheme.subText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                ],

                // Alt bilgi satırı: süre • boyut • tarih
                Row(
                  children: [
                    // Süre (varsa)
                    if (hasDuration) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: Colors.white12, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 10, color: AmoledTheme.subText),
                            const SizedBox(width: 3),
                            Text(
                              video.formattedDuration,
                              style: const TextStyle(
                                color: AmoledTheme.pureWhite,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Boyut
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF004D25)
                            : const Color(0xFF162518),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: const Color(0xFF00E676)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        video.formattedSize,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),
                    const Text('•',
                        style: TextStyle(color: AmoledTheme.borderDark, fontSize: 10)),
                    const SizedBox(width: 6),

                    // Tarih
                    Expanded(
                      child: Text(
                        video.formattedDisplayDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // YouTube Linki
                if (video.sourceUrl != null && video.sourceUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(video.sourceUrl!);
                      try {
                        bool launched = false;
                        // YouTube uygulamasına doğrudan açmayı dene
                        if (video.youtubeId != null && video.youtubeId!.isNotEmpty) {
                          final ytAppUri = Uri.parse('vnd.youtube:${video.youtubeId}');
                          launched = await launchUrl(ytAppUri, mode: LaunchMode.externalApplication);
                        }

                        if (!launched) {
                          // Önce YouTube uygulamasında açmayı dene (Android 11+ queries ile)
                          launched = await launchUrl(
                            url,
                            mode: LaunchMode.externalNonBrowserApplication,
                          );
                        }
                        
                        if (!launched) {
                          // YouTube uygulaması yoksa sistem varsayılanıyla (tarayıcı vs) aç
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      } catch (_) {
                        // Son çare: platformun varsayılan davranışı
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.link_rounded,
                          size: 12,
                          color: AmoledTheme.brandRed,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            video.sourceUrl!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AmoledTheme.brandRed,
                              fontSize: 10.5,
                              decoration: TextDecoration.underline,
                              decorationColor: AmoledTheme.brandRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
