import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/video_item.dart';
import '../../services/playback_manager.dart';
import '../theme/amoled_theme.dart';

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

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

  // Hız Yönetimi
  double _baseSpeed = 1.0;
  bool _isHolding2X = false;

  // Kaldığı Yerden Devam Etme (Playback Position)
  int _lastSavedPosMs = 0;

  // Altyazı Yönetimi (Varsayılan olarak KAPALI)
  bool _showSubtitles = false;
  List<SubtitleCue> _subtitleCues = [];
  String _currentSubtitleText = '';

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadSubtitles();
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

      // Kayıtlı kaldığı yeri yükle
      final savedPos =
          await PlaybackManager.instance.getPosition(widget.video.id);

      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      _controller.addListener(_onPlayerTick);

      final totalDuration = _controller.value.duration.inMilliseconds;
      if (savedPos > 2000 && savedPos < (totalDuration - 4000)) {
        await _controller.seekTo(Duration(milliseconds: savedPos));
        _lastSavedPosMs = savedPos;
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Kaldığınız yerden devam ediliyor: ${_formatDuration(Duration(milliseconds: savedPos))}',
                style: const TextStyle(
                  color: AmoledTheme.pureWhite,
                  fontWeight: FontWeight.w600,
                ),
              ),
              action: SnackBarAction(
                label: 'Başa Dön',
                textColor: const Color(0xFF00E676),
                onPressed: () {
                  _controller.seekTo(Duration.zero);
                  PlaybackManager.instance.savePosition(widget.video.id, 0);
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

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

  void _onPlayerTick() {
    if (!mounted || !_isInitialized) return;

    final posMs = _controller.value.position.inMilliseconds;
    final durMs = _controller.value.duration.inMilliseconds;

    // Periyodik olarak (her 2 saniyede bir) pozisyonu kaydet
    if ((posMs - _lastSavedPosMs).abs() > 2000) {
      _lastSavedPosMs = posMs;
      if (durMs > 0 && posMs >= durMs - 3000) {
        PlaybackManager.instance.savePosition(widget.video.id, 0);
      } else {
        PlaybackManager.instance.savePosition(widget.video.id, posMs);
      }
    }

    // Altyazı güncellemesi
    if (_showSubtitles && _subtitleCues.isNotEmpty) {
      final pos = _controller.value.position;
      final activeCue = _subtitleCues.firstWhere(
        (cue) => pos >= cue.start && pos <= cue.end,
        orElse: () => SubtitleCue(
          start: Duration.zero,
          end: Duration.zero,
          text: '',
        ),
      );
      if (activeCue.text != _currentSubtitleText) {
        setState(() {
          _currentSubtitleText = activeCue.text;
        });
      }
    } else if (_currentSubtitleText.isNotEmpty) {
      setState(() {
        _currentSubtitleText = '';
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _loadSubtitles() async {
    String? path = widget.video.subtitlePath;

    // Eğer modelde subtitlePath yoksa dosya sisteminde ara
    if (path == null || !File(path).existsSync()) {
      final base = widget.video.filePath.substring(
          0, widget.video.filePath.lastIndexOf('.'));
      for (final ext in [
        'tr.vtt',
        'tr-orig.vtt',
        'tr-TR.vtt',
        'tr.srt',
        'vtt',
        'srt'
      ]) {
        final candidate = '$base.$ext';
        if (File(candidate).existsSync()) {
          path = candidate;
          break;
        }
      }
    }

    if (path != null && File(path).existsSync()) {
      try {
        final content = await File(path).readAsString();
        final cues = _parseSubtitleFile(content);
        if (mounted) {
          setState(() {
            _subtitleCues = cues;
          });
        }
      } catch (_) {}
    }
  }

  List<SubtitleCue> _parseSubtitleFile(String content) {
    final List<SubtitleCue> cues = [];
    final lines = content.split(RegExp(r'\r?\n'));

    Duration? start;
    Duration? end;
    final List<String> textLines = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        if (start != null && end != null && textLines.isNotEmpty) {
          final cleanText = textLines
              .join('\n')
              .replaceAll(RegExp(r'<[^>]*>'), '') // HTML/VTT tag temizliği
              .trim();
          if (cleanText.isNotEmpty) {
            cues.add(SubtitleCue(start: start, end: end, text: cleanText));
          }
        }
        start = null;
        end = null;
        textLines.clear();
        continue;
      }

      if (line.contains('-->')) {
        final parts = line.split('-->');
        if (parts.length == 2) {
          start = _parseTimestamp(parts[0].trim());
          end = _parseTimestamp(parts[1].trim().split(' ').first);
        }
      } else if (start != null && end != null) {
        // İndeks satırlarını veya format satırlarını atla
        if (!RegExp(r'^\d+$').hasMatch(line) && !line.startsWith('NOTE') && !line.startsWith('WEBVTT')) {
          textLines.add(line);
        }
      }
    }

    if (start != null && end != null && textLines.isNotEmpty) {
      final cleanText = textLines
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (cleanText.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleanText));
      }
    }

    return cues;
  }

  Duration _parseTimestamp(String timestamp) {
    final clean = timestamp.replaceAll(',', '.');
    final parts = clean.split(':');
    int h = 0;
    int m = 0;
    double s = 0.0;

    if (parts.length == 3) {
      h = int.tryParse(parts[0]) ?? 0;
      m = int.tryParse(parts[1]) ?? 0;
      s = double.tryParse(parts[2]) ?? 0.0;
    } else if (parts.length == 2) {
      m = int.tryParse(parts[0]) ?? 0;
      s = double.tryParse(parts[1]) ?? 0.0;
    }

    final totalMs = (h * 3600 + m * 60 + s) * 1000;
    return Duration(milliseconds: totalMs.round());
  }

  @override
  void dispose() {
    if (_isInitialized) {
      final posMs = _controller.value.position.inMilliseconds;
      final durMs = _controller.value.duration.inMilliseconds;
      if (durMs > 0 && posMs >= durMs - 3000) {
        PlaybackManager.instance.savePosition(widget.video.id, 0);
      } else if (posMs > 1000) {
        PlaybackManager.instance.savePosition(widget.video.id, posMs);
      }
      _controller.removeListener(_onPlayerTick);
      _controller.dispose();
    }
    super.dispose();
  }

  void _setSpeed(double speed) {
    setState(() {
      _baseSpeed = speed;
    });
    _controller.setPlaybackSpeed(speed);
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AmoledTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Oynatma Hızı',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AmoledTheme.subText, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: speeds.map((s) {
                    final isSelected = (_baseSpeed == s);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _setSpeed(s);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00E676)
                                : AmoledTheme.accentGray,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00E676)
                                  : AmoledTheme.borderDark,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            s == 1.0 ? '1.0x (Normal)' : '${s}x',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : AmoledTheme.pureWhite,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
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
        backgroundColor: Colors.black.withValues(alpha: 0.5),
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AmoledTheme.pureWhite,
          ),
        ),
        actions: [
          // Altyazı Butonu (Varsa aktifleşir / Açılıp kapatılabilir)
          if (_subtitleCues.isNotEmpty)
            IconButton(
              icon: Icon(
                _showSubtitles
                    ? Icons.closed_caption_rounded
                    : Icons.closed_caption_off_rounded,
                color: _showSubtitles
                    ? const Color(0xFF00E676)
                    : AmoledTheme.subText,
              ),
              tooltip:
                  _showSubtitles ? 'Altyazıyı Kapat' : 'Türkçe Altyazıyı Aç',
              onPressed: () {
                setState(() {
                  _showSubtitles = !_showSubtitles;
                });
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_showSubtitles
                        ? 'Türkçe altyazı açıldı.'
                        : 'Altyazı kapatıldı.'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          // Hız Seçici Butonu
          TextButton(
            onPressed: _showSpeedPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${_baseSpeed}x',
                style: const TextStyle(
                  color: AmoledTheme.pureWhite,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    // Ekrana basılı tutulduğunda 2 kat hızlı oynatma
                    onLongPressStart: (_) {
                      setState(() {
                        _isHolding2X = true;
                      });
                      _controller.setPlaybackSpeed(2.0);
                    },
                    onLongPressEnd: (_) {
                      setState(() {
                        _isHolding2X = false;
                      });
                      _controller.setPlaybackSpeed(_baseSpeed);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),

                        // 2X HIZLI OYNATILIYOR ROZETİ (Basılı Tutulduğunda)
                        if (_isHolding2X)
                          Positioned(
                            top: 64,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFFFFCC00),
                                      width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFCC00)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.fast_forward_rounded,
                                        color: Color(0xFFFFCC00), size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      '2X Hızında Oynatılıyor',
                                      style: TextStyle(
                                        color: AmoledTheme.pureWhite,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // ALTYAZI KATMANI
                        if (_showSubtitles && _currentSubtitleText.isNotEmpty)
                          Positioned(
                            bottom: _showControls ? 110 : 40,
                            left: 20,
                            right: 20,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _currentSubtitleText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AmoledTheme.pureWhite,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // KONTROL DÜĞMELERİ KATMANI
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
                                  bottom: 32, // Elevated above Android gesture/button bar
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
