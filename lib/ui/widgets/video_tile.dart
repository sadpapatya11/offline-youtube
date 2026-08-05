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

    return AmoledCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AmoledTheme.accentGray,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AmoledTheme.borderDark),
            ),
            child: const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: AmoledTheme.pureWhite,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 14),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      video.formattedSize,
                      style: const TextStyle(
                        color: AmoledTheme.subText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '•',
                      style: TextStyle(color: AmoledTheme.borderDark),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateFormat.format(video.downloadedAt),
                      style: const TextStyle(
                        color: Color(0xFF777777),
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
