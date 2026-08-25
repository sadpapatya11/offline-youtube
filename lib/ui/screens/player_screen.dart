import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

/// Oynatıcının saf karar mantığı.
///
/// NEDEN ayrı: video_player widget'ı testte platform kanalı istediği için bu
/// kurallar State içinde kaldığı sürece hiç doğrulanamıyordu; ayrılınca
/// regresyon testi yazılabiliyor (test/fix_oynatici_test.dart).
class PlayerLogic {
  const PlayerLogic._();

  /// Slider'ın göstereceği milisaniye değeri.
  ///
  /// NEDEN: Değer doğrudan controller'dan okunduğunda sürükleme sırasında
  /// tutamak parmağı takip etmiyor, decoder'ın yetiştiği konuma geri
  /// sıçrıyordu. Sürükleme boyunca yerel taslak değer gösterilir.
  static double sliderValueMs({
    required double? dragValueMs,
    required int positionMs,
    required int durationMs,
  }) {
    final maxMs = durationMs > 0 ? durationMs.toDouble() : 0.0;
    final raw = dragValueMs ?? positionMs.toDouble();
    return raw.clamp(0.0, maxMs);
  }

  /// Tick sırasında kalıcılaştırılacak pozisyon; null ise kayıt yapılmaz.
  ///
  /// NEDEN durationMs kapısı: Oynatıcı değeri hata sonrası sıfırlandığında
  /// (position 0, duration 0) eski kod savePosition(id, 0) çağırıyordu.
  /// PlaybackManager 1000 ms altını "kaydı sil" olarak yorumladığı için
  /// 45. dakikada codec hatası alan kullanıcının kaldığı yer siliniyordu.
  static int? positionToPersistOnTick({
    required int positionMs,
    required int durationMs,
    required int lastSavedPosMs,
  }) {
    if (durationMs <= 0) return null;
    if ((positionMs - lastSavedPosMs).abs() <= 2000) return null;
    if (positionMs >= durationMs - 3000) return 0;
    return positionMs;
  }

  /// Pozisyon değişimi ekranda gerçekten bir piksel değiştiriyor mu.
  ///
  /// NEDEN: Kontroller gizli ve altyazı kapalıyken pozisyona bağlı hiçbir şey
  /// çizilmiyor; buna rağmen saniyede 3 ila 4 setState tüm Scaffold'u yeniden
  /// kuruyordu (2 saatlik izlemede on binlerce gereksiz rebuild).
  static bool shouldRebuildForTick({
    required bool controlsVisible,
    required bool subtitlesVisible,
    required int positionMs,
    required int lastRenderedPosMs,
  }) {
    if (!controlsVisible && !subtitlesVisible) return false;
    return (positionMs - lastRenderedPosMs).abs() >= 250;
  }

  /// Oynatıcı hata verdiğinde kullanıcıya gösterilecek metin.
  ///
  /// NEDEN: errorDescription null olabiliyor; doğrudan basılsaydı ekranda
  /// "null" yazacak ya da boş kalacaktı, kullanıcı donmuş ekranın nedenini
  /// yine göremeyecekti.
  static String playbackErrorMessage(String? errorDescription) {
    final detail = errorDescription?.trim() ?? '';
    if (detail.isEmpty) {
      return 'Video oynatılamadı. Dosya bozuk olabilir veya codec bu cihazda '
          'desteklenmiyor olabilir.';
    }
    return 'Video oynatılırken hata oluştu:\n$detail';
  }
}

class PlayerScreen extends StatefulWidget {
  final VideoItem video;
  final List<VideoItem>? playlist;
  final int? initialIndex;

  const PlayerScreen({
    super.key,
    required this.video,
    this.playlist,
    this.initialIndex,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late List<VideoItem> _playlist;
  late int _currentIndex;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  String? _error;

  // FIX(leak): Yükleme nesli sayacı — hızlı Sonraki/Önceki dokunuşlarında
  // eski yüklemeler kendi controller'larını dispose edip geri döner; böylece
  // çift dispose ve aynı anda iki videonun ses vermesi önlenir.
  int _loadGeneration = 0;

  // Hız Yönetimi
  double _baseSpeed = 1.0;
  bool _isHolding2X = false;

  // Kaldığı Yerden Devam Etme
  int _lastSavedPosMs = 0;
  bool _hasAutoAdvanced = false;

  // FIX(progress): İlerleme çubuğu/süre etiketinin rebuild eşiği — pozisyon
  // 250ms'den fazla değişince setState (her tick'te rebuild'e gerek yok).
  int _lastRenderedPosMs = 0;

  // FIX(oynatici): Sürükleme sırasındaki yerel taslak değer. NEDEN: Slider
  // değeri doğrudan controller'dan okununca tutamak parmağı takip etmiyor,
  // üstelik her pointer move olayında bir seekTo platform kanalına gidiyordu.
  double? _dragValueMs;

  // Altyazı Yönetimi
  bool _showSubtitles = false;
  List<SubtitleCue> _subtitleCues = [];
  String _currentSubtitleText = '';

  // Çift Dokunma İleri/Geri Bildirimi
  String? _seekFeedbackText;
  Timer? _seekFeedbackTimer;
  Timer? _controlsTimer;

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    // FIX(oynatici): Ekran kapandıktan sonra kurulan zamanlayıcı, kapatılmış
    // State'in tüm alanlarını (oynatma listesi, altyazı listesi) 1,5 saniye
    // daha canlı tutuyordu.
    if (!mounted) return;
    if (_showControls) {
      _controlsTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    _resetControlsTimer();
  }

  // FIX(oynatici): İki GestureDetector'da birebir kopyalanan 2X mantığı tek
  // yere alındı; kopya kaldığı sürece iptal düzeltmesinin bir tarafta
  // unutulması kaçınılmazdı.
  void _startHold2X() {
    final c = _controller;
    if (c == null || !_isInitialized) return;
    setState(() {
      _isHolding2X = true;
    });
    c.setPlaybackSpeed(2.0);
  }

  /// Basılı tutma bittiğinde ya da iptal edildiğinde normal hıza döner.
  ///
  /// NEDEN: Sistem işaretçiyi iptal ettiğinde (bildirim gölgesi aşağı çekilir,
  /// ekran bölme, gelen çağrı) onLongPressEnd hiç çağrılmıyor; video 2.0x
  /// hızda kilitli kalıyor ve rozet ekrandan gitmiyordu.
  void _endHold2X() {
    if (!_isHolding2X) return;
    setState(() {
      _isHolding2X = false;
    });
    _controller?.setPlaybackSpeed(_baseSpeed);
  }

  VideoItem get currentVideo =>
      (_playlist.isNotEmpty && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : widget.video;

  @override
  void initState() {
    super.initState();
    // FIX(oynatici): Uygulama arka plana alındığında sesi durdurabilmek için
    // yaşam döngüsünü dinle.
    WidgetsBinding.instance.addObserver(this);
    _playlist = (widget.playlist != null && widget.playlist!.isNotEmpty)
        ? List.from(widget.playlist!)
        : [widget.video];

    if (widget.initialIndex != null &&
        widget.initialIndex! >= 0 &&
        widget.initialIndex! < _playlist.length) {
      _currentIndex = widget.initialIndex!;
    } else {
      final idx = _playlist.indexWhere((v) => v.id == widget.video.id);
      _currentIndex = idx >= 0 ? idx : 0;
    }

    _loadAndPlayCurrentVideo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // FIX(oynatici): Uygulama arka plana alındığında video sesi çalmaya devam
    // ediyordu: kullanıcı başka uygulamada müzik açtığında iki ses üst üste
    // biniyor, ekran kapalıyken de video sessizce oynayıp pili tüketiyordu.
    // Duraklatmadan önce konumu kaydediyoruz ki süreç arka planda öldürülürse
    // kaldığı yer kaybolmasın. Geri dönüşte bilinçli olarak kendiliğinden
    // devam ettirmiyoruz: oynatmayı yeniden başlatma kararı kullanıcının.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _endHold2X();
      final c = _controller;
      if (c != null && _isInitialized && c.value.isPlaying) {
        _saveCurrentPosition();
        c.pause();
        // Kontroller açıksa oynat/duraklat ikonu eski hâlde kalmasın.
        setState(() {});
      }
    }
  }

  Future<void> _loadAndPlayCurrentVideo() async {
    // FIX(leak): Her çağrı yeni bir nesil üretir; yalnızca en güncel nesil
    // controller'ı atayabilir. Eski nesil (hızlı Sonraki/Önceki ya da geri
    // dönüş) kendi controller'ını dispose edip sessizce sonlanır.
    final generation = ++_loadGeneration;

    _hasAutoAdvanced = false;
    _error = null;
    _isInitialized = false;
    _subtitleCues = [];
    _currentSubtitleText = '';
    _lastSavedPosMs = 0;
    _dragValueMs = null;
    // FIX(oynatici): Yeni video kontroller açık başlasın ve önceki videodan
    // kalan gizleme zamanlayıcısı onları hemen kapatmasın. Silinmiş bir
    // dosyaya geçildiğinde hata ekranında geri oku bile kalmıyordu.
    _showControls = true;
    _controlsTimer?.cancel();

    if (mounted) setState(() {});

    final vid = currentVideo;
    final file = File(vid.filePath);

    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _error = 'Video dosyası bulunamadı:\n${vid.filePath}';
        });
      }
      return;
    }

    // FIX(leak): Controller'ı try dışında tutuyoruz ki herhangi bir adım
    // hata verirse bile dispose edebilelim.
    VideoPlayerController? newController;

    try {
      // Bu nesil hâlâ geçerli değilse mevcut controller'a dokunma.
      if (generation != _loadGeneration) return;

      final oldController = _controller;
      if (oldController != null) {
        oldController.removeListener(_onPlayerTick);
        await oldController.dispose();
        _controller = null;
      }

      final savedPos = await PlaybackManager.instance.getPosition(vid.id);

      newController = VideoPlayerController.file(file);
      await newController.initialize();

      // FIX(leak): Initialize sırasında kullanıcı başka videoya geçtiyse veya
      // ekrandan ayrıldıysa bu controller'ı çalıştırmadan at.
      if (!mounted || generation != _loadGeneration) {
        await newController.dispose();
        return;
      }

      newController.addListener(_onPlayerTick);

      final totalDuration = newController.value.duration.inMilliseconds;
      if (savedPos > 2000 && savedPos < (totalDuration - 4000)) {
        await newController.seekTo(Duration(milliseconds: savedPos));
        _lastSavedPosMs = savedPos;
      }

      await newController.setPlaybackSpeed(_baseSpeed);
      await newController.play();

      if (!mounted || generation != _loadGeneration) {
        // FIX(leak): Oyuncu başlatılırken geri tuşuna basıldı — arka planda
        // ses veren, UI'sız bir video asla bırakma.
        await newController.dispose();
        return;
      }

      setState(() {
        _controller = newController;
        _isInitialized = true;
      });

      // FIX(screen): Oynatma sırasında ekranın kapanmasını engelle.
      await WakelockPlus.enable();

      await _loadSubtitlesFor(vid, generation);

      // FIX(oynatici): Altyazı okuması await içerdiği için burada artık eski
      // nesil olabiliriz; kullanıcı bu sırada Sonraki'ye bastıysa yeni videonun
      // zamanlayıcısını ezmemeliyiz.
      if (mounted && generation == _loadGeneration) {
        _resetControlsTimer();
      }
    } catch (e) {
      // FIX(leak): Controller oluşturuldu ama _controller'a atanamadan hata
      // oluştuysa burada dispose et (ör. initialize() fırlattı).
      await newController?.dispose();
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = 'Video oynatılırken hata oluştu: ${e.toString()}';
        });
      }
    }
  }

  void _onPlayerTick() {
    final c = _controller;
    if (!mounted || !_isInitialized || c == null) return;

    // FIX(oynatici): Oynatma sırasında oluşan platform hataları hiç
    // okunmuyordu. 45. dakikada bozuk parçaya denk gelen kullanıcı donmuş bir
    // ekranla kalıyor, üstelik value sıfırlandığı için aşağıdaki kayıt dalı
    // savePosition(id, 0) çağırıp kaldığı yer bilgisini siliyordu.
    if (c.value.hasError) {
      _controlsTimer?.cancel();
      if (_error == null) {
        setState(() {
          _showControls = true;
          _error = PlayerLogic.playbackErrorMessage(c.value.errorDescription);
        });
      }
      return;
    }

    final posMs = c.value.position.inMilliseconds;
    final durMs = c.value.duration.inMilliseconds;

    // FIX(progress): Pozisyon değişince ekranı güncelle — eski kodda yalnızca
    // altyazı değişiminde setState vardı; altyazı kapalıyken ilerleme çubuğu
    // ve süre etiketi hiç ilerlemiyordu.
    if (PlayerLogic.shouldRebuildForTick(
      controlsVisible: _showControls,
      subtitlesVisible: _showSubtitles && _subtitleCues.isNotEmpty,
      positionMs: posMs,
      lastRenderedPosMs: _lastRenderedPosMs,
    )) {
      _lastRenderedPosMs = posMs;
      setState(() {});
    }

    // Periyodik olarak pozisyonu kaydet
    final persistMs = PlayerLogic.positionToPersistOnTick(
      positionMs: posMs,
      durationMs: durMs,
      lastSavedPosMs: _lastSavedPosMs,
    );
    if (persistMs != null) {
      _lastSavedPosMs = posMs;
      PlaybackManager.instance.savePosition(currentVideo.id, persistMs);
    }

    // Video bittiğinde otomatik sıradaki videoya geçiş
    if (durMs > 0 &&
        posMs >= (durMs - 500) &&
        !_hasAutoAdvanced &&
        _currentIndex < _playlist.length - 1) {
      _hasAutoAdvanced = true;
      PlaybackManager.instance.savePosition(currentVideo.id, 0);
      _playNextVideo();
      return;
    }

    // Altyazı güncellemesi
    if (_showSubtitles && _subtitleCues.isNotEmpty) {
      final pos = c.value.position;
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
    }
  }

  Future<void> _loadSubtitlesFor(VideoItem vid, int generation) async {
    String? path = vid.subtitlePath;

    if (path == null || !File(path).existsSync()) {
      final lastDot = vid.filePath.lastIndexOf('.');
      final base =
          lastDot > 0 ? vid.filePath.substring(0, lastDot) : vid.filePath;
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
        // FIX(oynatici): Büyük bir .vtt okunurken kullanıcı Sonraki'ye basarsa
        // eski videonun cue'ları yeni videonun üstüne biniyor, CC düğmesi
        // yanlış videoda beliriyor ve alakasız altyazı çiziliyordu.
        if (mounted && generation == _loadGeneration) {
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
              .replaceAll(RegExp(r'<[^>]*>'), '')
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
        if (!RegExp(r'^\d+$').hasMatch(line) &&
            !line.startsWith('NOTE') &&
            !line.startsWith('WEBVTT')) {
          textLines.add(line);
        }
      }
    }

    if (start != null && end != null && textLines.isNotEmpty) {
      final cleanText =
          textLines.join('\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();
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

  void _playPreviousVideo() {
    if (_currentIndex > 0) {
      _saveCurrentPosition();
      setState(() {
        _currentIndex--;
      });
      _loadAndPlayCurrentVideo();
    }
  }

  void _playNextVideo() {
    if (_currentIndex < _playlist.length - 1) {
      _saveCurrentPosition();
      setState(() {
        _currentIndex++;
      });
      _loadAndPlayCurrentVideo();
    }
  }

  void _saveCurrentPosition() {
    final c = _controller;
    if (c != null && _isInitialized) {
      final posMs = c.value.position.inMilliseconds;
      final durMs = c.value.duration.inMilliseconds;
      if (durMs > 0 && posMs >= durMs - 3000) {
        PlaybackManager.instance.savePosition(currentVideo.id, 0);
      } else if (posMs > 1000) {
        PlaybackManager.instance.savePosition(currentVideo.id, posMs);
      }
    }
  }

  void _triggerSeekFeedback(String text) {
    _seekFeedbackTimer?.cancel();
    setState(() {
      _seekFeedbackText = text;
    });
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _seekFeedbackText = null;
        });
      }
    });
  }

  void _seekRelative(int seconds) {
    final c = _controller;
    if (c == null || !_isInitialized) return;
    final currentPos = c.value.position;
    final targetPos = currentPos + Duration(seconds: seconds);
    final clampedPos = targetPos < Duration.zero
        ? Duration.zero
        : (targetPos > c.value.duration ? c.value.duration : targetPos);
    c.seekTo(clampedPos);
    _triggerSeekFeedback(seconds > 0 ? '+$seconds sn' : '$seconds sn');
    // FIX(oynatici): Sarma da bir kullanıcı etkileşimi. Sayaç sıfırlanmadığı
    // için kontroller tam elin altındayken kayboluyor, art arda sarmak isteyen
    // kullanıcı her seferinde ekrana yeniden dokunmak zorunda kalıyordu.
    _resetControlsTimer();
  }

  @override
  void dispose() {
    // FIX(screen): Ekran kilidini bırak (oynatıcı kapandı).
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _seekFeedbackTimer?.cancel();
    // FIX(oynatici): Bekleyen gizleme zamanlayıcısı kapatılmış State'i ve
    // dolaylı olarak controller'ı 1,5 saniye daha canlı tutuyordu; listede
    // hızlıca video değiştiren kullanıcıda onlarca bekleyen timer birikiyordu.
    _controlsTimer?.cancel();
    _saveCurrentPosition();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onPlayerTick);
      c.dispose();
    }
    super.dispose();
  }

  void _setSpeed(double speed) {
    setState(() {
      _baseSpeed = speed;
    });
    _controller?.setPlaybackSpeed(speed);
    _resetControlsTimer();
  }

  void _showSpeedPicker() {
    // FIX(oynatici): Sheet açıkken sayaç işlemeye devam ettiği için kullanıcı
    // hız seçerken arkadaki kontroller kayboluyor, sheet kapanınca oynatıcı
    // çıplak kalıyordu. Sheet kapanana kadar sayacı durdur, sonra yeniden kur.
    _controlsTimer?.cancel();
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
    ).whenComplete(() {
      if (mounted) _resetControlsTimer();
    });
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
    final c = _controller;
    final hasMultiple = _playlist.length > 1;

    return Scaffold(
      backgroundColor: AmoledTheme.pureBlack,
      extendBodyBehindAppBar: true,
      // FIX(oynatici): Hata ve yükleme durumunda da AppBar çizilsin. Kontroller
      // gizlendikten sonra silinmiş bir videoya geçen kullanıcıda geri oku
      // kalmıyor, oynatıcıdan çıkmanın uygulama içi yolu tamamen kapanıyordu.
      appBar: (_showControls || _error != null || !_isInitialized)
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AmoledTheme.pureWhite),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentVideo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AmoledTheme.pureWhite,
                    ),
                  ),
                  if (hasMultiple)
                    Text(
                      '${_currentIndex + 1} / ${_playlist.length} video',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AmoledTheme.subText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              actions: [
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
                _resetControlsTimer();
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
      ) : null,
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
                    const SizedBox(height: 16),
                    // FIX(oynatici): Tek videoluk oynatmada hata ekranında hiç
                    // eylem yoktu; geçici bir codec veya IO hatasında
                    // kullanıcının yapabileceği tek şey ekranı terk etmekti.
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF222222),
                        foregroundColor: AmoledTheme.pureWhite,
                      ),
                      onPressed: _loadAndPlayCurrentVideo,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Yeniden Dene'),
                    ),
                    const SizedBox(height: 8),
                    if (hasMultiple && _currentIndex < _playlist.length - 1)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF222222),
                          foregroundColor: AmoledTheme.pureWhite,
                        ),
                        onPressed: _playNextVideo,
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Sonraki Videoya Geç'),
                      ),
                  ],
                ),
              )
            : (!_isInitialized || c == null)
                ? const CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),

                      // Çift Dokunma & Basılı Tutma Alanı
                      // FIX(oynatici): SizedBox.expand, Positioned.fill'in
                      // yerini aldı. NEDEN: Stack boyutu konumlandırılmamış en
                      // büyük çocuğa göre belirleniyor. Kontroller gizliyken bu
                      // katman konumlandırılmış olduğu için Stack videonun
                      // letterbox alanına kadar küçülüyor, siyah bantlara
                      // dokunmak hiçbir şey yapmıyordu ve kullanıcı kontrolleri
                      // geri getiremiyordu. Expand ile dokunma alanı her
                      // durumda tam ekran.
                      SizedBox.expand(
                        child: Row(
                          children: [
                            // Sol taraf: Çift dokunma 10s geri
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onDoubleTap: () => _seekRelative(-10),
                                onTap: _toggleControls,
                                onLongPressStart: (_) => _startHold2X(),
                                onLongPressEnd: (_) => _endHold2X(),
                                // FIX(oynatici): Sistem işaretçiyi iptal
                                // ettiğinde (PointerCancel) onLongPressEnd hiç
                                // çağrılmıyor ve video 2.0x hızda kilitli
                                // kalıyordu. _endHold2X kendi içinde
                                // _isHolding2X kontrolü yaptığı için basılı
                                // tutmaya dönüşmeyen normal dokunuşlarda da
                                // tetiklenmesi zararsız.
                                onLongPressCancel: _endHold2X,
                              ),
                            ),
                            // Sağ taraf: Çift dokunma 10s ileri
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onDoubleTap: () => _seekRelative(10),
                                onTap: _toggleControls,
                                onLongPressStart: (_) => _startHold2X(),
                                onLongPressEnd: (_) => _endHold2X(),
                                // FIX(oynatici): Sistem işaretçiyi iptal
                                // ettiğinde (PointerCancel) onLongPressEnd hiç
                                // çağrılmıyor ve video 2.0x hızda kilitli
                                // kalıyordu. _endHold2X kendi içinde
                                // _isHolding2X kontrolü yaptığı için basılı
                                // tutmaya dönüşmeyen normal dokunuşlarda da
                                // tetiklenmesi zararsız.
                                onLongPressCancel: _endHold2X,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2X HIZLI OYNATILIYOR ROZETİ
                      if (_isHolding2X)
                        Positioned(
                          top: 80,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFFFCC00), width: 1.5),
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

                      // Hızlı Sarma Geri Bildirimi
                      if (_seekFeedbackText != null)
                        IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.white38, width: 1),
                            ),
                            child: Text(
                              _seekFeedbackText!,
                              style: const TextStyle(
                                color: AmoledTheme.pureWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                      // ALTYAZI KATMANI
                      if (_showSubtitles && _currentSubtitleText.isNotEmpty)
                        Positioned(
                          bottom: _showControls ? 120 : 40,
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
                        IgnorePointer(
                          child: Container(
                            color: Colors.black38,
                          ),
                        ),
                        // Orta Kontrol Butonları (Önceki, Geri 10s, Oynat/Duraklat, İleri 10s, Sonraki)
                        // FIX(oynatici): Satır sabit 344 dp genişlikte
                        // (48+12+52+20+80+20+52+12+48). 320 dp genişliğindeki
                        // küçük ekranlarda ve büyük sistem yazı tipi ölçeğinde
                        // taşıyordu: release'de en sağdaki Sonraki butonunun bir
                        // kısmı ekran dışında kalıyor, dokunma alanı kesiliyordu.
                        // scaleDown yalnız sığmadığında küçültür, geniş
                        // ekranlarda hiçbir şeyi değiştirmez.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasMultiple) ...[
                                IconButton(
                                  iconSize: 32,
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    color: _currentIndex > 0
                                        ? AmoledTheme.pureWhite
                                        : Colors.white24,
                                  ),
                                  onPressed: _currentIndex > 0
                                      ? _playPreviousVideo
                                      : null,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 36,
                                  icon: const Icon(Icons.replay_10_rounded,
                                      color: AmoledTheme.pureWhite),
                                  onPressed: () => _seekRelative(-10),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 64,
                                  icon: Icon(
                                    c.value.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: AmoledTheme.pureWhite,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (c.value.isPlaying) {
                                        c.pause();
                                      } else {
                                        c.play();
                                      }
                                      _resetControlsTimer();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 20),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 36,
                                  icon: const Icon(Icons.forward_10_rounded,
                                      color: AmoledTheme.pureWhite),
                                  onPressed: () => _seekRelative(10),
                                ),
                              ),
                              if (hasMultiple) ...[
                                const SizedBox(width: 12),
                                IconButton(
                                  iconSize: 32,
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: _currentIndex < _playlist.length - 1
                                        ? AmoledTheme.pureWhite
                                        : Colors.white24,
                                  ),
                                  onPressed:
                                      _currentIndex < _playlist.length - 1
                                          ? _playNextVideo
                                          : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Alt Süre Çubuğu
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
                                bottom: 32,
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
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: 0.3),
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 8),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 16),
                                    ),
                                    child: Slider(
                                      value: PlayerLogic.sliderValueMs(
                                        dragValueMs: _dragValueMs,
                                        positionMs:
                                            c.value.position.inMilliseconds,
                                        durationMs:
                                            c.value.duration.inMilliseconds,
                                      ),
                                      min: 0.0,
                                      max: c.value.duration.inMilliseconds
                                          .toDouble(),
                                      // FIX(oynatici): Sürükleme boyunca yalnız
                                      // yerel taslak değer güncellenir. Eski kod
                                      // her pointer move olayında seekTo atıyor,
                                      // tek sürüklemede onlarca seek isteği
                                      // platform kanalına gidiyor ve tutamak
                                      // parmağın gerisine düşüyordu.
                                      onChanged: (val) {
                                        setState(() {
                                          _dragValueMs = val;
                                        });
                                      },
                                      onChangeStart: (val) {
                                        _controlsTimer?.cancel();
                                        setState(() {
                                          _dragValueMs = val;
                                        });
                                      },
                                      onChangeEnd: (val) {
                                        final target =
                                            Duration(milliseconds: val.toInt());
                                        // Taslak değer, seek gerçekten
                                        // uygulanana kadar duruyor: erken
                                        // temizlenirse tutamak bir kare boyunca
                                        // eski konuma geri sıçrar.
                                        c.seekTo(target).whenComplete(() {
                                          if (!mounted) return;
                                          setState(() {
                                            _dragValueMs = null;
                                          });
                                          _resetControlsTimer();
                                        });
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
                                          _formatDuration(c.value.position),
                                          style: const TextStyle(
                                            color: AmoledTheme.pureWhite,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          _formatDuration(c.value.duration),
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
    );
  }
}
