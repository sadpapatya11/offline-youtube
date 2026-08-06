import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/video_item.dart';
import '../theme/amoled_theme.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.video.filePath);
      if (!await file.exists()) {
        setState(() {
          _error = 'Video dosyası bulunamadı: ${widget.video.filePath}';
        });
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      _controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Video oynatılırken hata oluştu: ${e.toString()}';
        });
      }
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = duration.inHours;
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AmoledTheme.pureBlack,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AmoledTheme.pureWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AmoledTheme.pureWhite,
          ),
        ),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFFF5555), size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AmoledTheme.pureWhite),
                    ),
                  ],
                ),
              )
            : !_isInitialized
                ? const CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                  )
                : GestureDetector(
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                        if (_showControls) ...[
                          // Dark overlay backdrop
                          Container(
                            color: Colors.black38,
                          ),
                          // Center Play/Pause / Rewind / Fast Forward Controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 36,
                                  icon: const Icon(Icons.replay_10_rounded,
                                      color: AmoledTheme.pureWhite),
                                  onPressed: () {
                                    final newPos = _controller.value.position -
                                        const Duration(seconds: 10);
                                    _controller.seekTo(newPos < Duration.zero
                                        ? Duration.zero
                                        : newPos);
                                  },
                                ),
                              ),
                              const SizedBox(width: 28),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 64,
                                  icon: Icon(
                                    _controller.value.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: AmoledTheme.pureWhite,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _controller.value.isPlaying
                                          ? _controller.pause()
                                          : _controller.play();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 28),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 36,
                                  icon: const Icon(Icons.forward_10_rounded,
                                      color: AmoledTheme.pureWhite),
                                  onPressed: () {
                                    final newPos = _controller.value.position +
                                        const Duration(seconds: 10);
                                    _controller.seekTo(newPos);
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Bottom Timeline and Duration with Safe Area and Elevated Position
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              bottom: true,
                              child: Container(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  bottom: 32, // Elevated above Android 3-button and gesture bar
                                  top: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.85),
                                    ],
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        thumbColor: AmoledTheme.pureWhite,
                                        activeTrackColor: AmoledTheme.pureWhite,
                                        inactiveTrackColor:
                                            Colors.white.withValues(alpha: 0.3),
                                        trackHeight: 4,
                                        thumbShape:
                                            const RoundSliderThumbShape(
                                                enabledThumbRadius: 8),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                                overlayRadius: 16),
                                      ),
                                      child: Slider(
                                        value: _controller
                                            .value.position.inMilliseconds
                                            .toDouble()
                                            .clamp(
                                                0.0,
                                                _controller.value.duration
                                                    .inMilliseconds
                                                    .toDouble()),
                                        min: 0.0,
                                        max: _controller
                                            .value.duration.inMilliseconds
                                            .toDouble(),
                                        onChanged: (val) {
                                          _controller.seekTo(Duration(
                                              milliseconds: val.toInt()));
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(
                                                _controller.value.position),
                                            style: const TextStyle(
                                              color: AmoledTheme.pureWhite,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(
                                                _controller.value.duration),
                                            style: TextStyle(
                                              color: AmoledTheme.pureWhite
                                                  .withValues(alpha: 0.7),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
