import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/amoled_theme.dart';

/// Hızlı kaydırıcının sürükleme oranı. Ayrı ve saf tutuluyor ki davranışı
/// widget kurmadan test edilebilsin.
///
/// FIX(kayma): Eski hesap parmağın mutlak konumunu doğrudan orana çeviriyordu
/// (localY / trackHeight) ama thumb, oranı trackHeight eksi thumb yüksekliği
/// üzerinden konumlandırıyordu. İki farklı taban yüzünden parmakla thumb
/// arasında sıfırdan 48 piksele kadar büyüyen bir kayma oluşuyor, kullanıcı
/// şeridin en altına sürüklediğinde thumb parmağın 48 piksel üstünde kalıyordu.
/// Artık oran, sürükleme başındaki oranın üzerine kat edilen mesafenin
/// eklenmesiyle bulunuyor: yakalama noktası sürükleme boyunca sabit kalır.
double fastScrollerDragRatio({
  required double startRatio,
  required double deltaY,
  required double effectiveTrackHeight,
}) {
  if (effectiveTrackHeight <= 0) {
    return startRatio.clamp(0.0, 1.0).toDouble();
  }
  return (startRatio + deltaY / effectiveTrackHeight).clamp(0.0, 1.0).toDouble();
}

class AmoledFastScroller extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final double topPadding;
  final double bottomPadding;

  const AmoledFastScroller({
    super.key,
    required this.controller,
    required this.child,
    this.topPadding = 12.0,
    this.bottomPadding = 12.0,
  });

  @override
  State<AmoledFastScroller> createState() => _AmoledFastScrollerState();
}

class _AmoledFastScrollerState extends State<AmoledFastScroller>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _hideTimer;
  bool _isDragging = false;
  double _thumbPositionRatio = 0.0; // 0.0 to 1.0

  /// Liste gerçekten kaydırılabiliyor mu. Kaydırılamıyorken ne thumb çizilir ne
  /// de yakalama alanı kurulur.
  bool _canScroll = false;
  double _dragStartGlobalY = 0.0;
  double _dragStartRatio = 0.0;

  static const double _thumbHeight = 48.0;

  /// Thumb'ın çevresine eklenen dokunma payı: 48 piksellik göstergeye 12'şer
  /// piksel eklenince parmak için 72 piksellik bir hedef kalır.
  static const double _thumbTouchPadding = 12.0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AmoledFastScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  /// Göstergenin durumunu kaydırma konumundan yeniden türetir.
  ///
  /// FIX(bayat-thumb): Eskiden yalnızca maxScrollExtent > 0 iken güncelleme
  /// yapılıyordu. Kullanıcı uzun listede dibe inip aramayla listeyi tek videoya
  /// daralttığında liste başa dönüyor ama kırmızı thumb ekranın dibinde asılı
  /// kalıyor, kullanıcıya hâlâ listenin sonundaymış gibi görünüyordu. Artık
  /// kaydırılamayan listede oran sıfırlanıyor ve gösterge hiç çizilmiyor.
  void _syncThumbFromPosition() {
    if (!mounted || _isDragging) return;
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    final canScroll = position.maxScrollExtent > 0;
    final ratio = canScroll
        ? (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0).toDouble()
        : 0.0;

    if (canScroll != _canScroll || ratio != _thumbPositionRatio) {
      setState(() {
        _canScroll = canScroll;
        _thumbPositionRatio = ratio;
      });
    }
  }

  void _onScroll() {
    // mounted ve hasClients kapıları burada da duruyor: dispose sonrası gelen
    // geç bir bildirimde _showScrollbar atılmış _fadeController'a dokunur.
    if (!mounted || _isDragging) return;
    if (!widget.controller.hasClients) return;

    _syncThumbFromPosition();
    if (_canScroll) {
      _showScrollbar();
    }
  }

  void _showScrollbar() {
    _hideTimer?.cancel();
    if (!_fadeController.isCompleted) {
      _fadeController.forward();
    }
    if (!_isDragging) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_isDragging) {
          _fadeController.reverse();
        }
      });
    }
  }

  /// Sürüklemeyi mutlak konum yerine kat edilen mesafeyle işler; parmağın
  /// thumb üzerindeki yakalama noktası korunur.
  void _handleDrag(double globalY, double effectiveTrackHeight) {
    if (!widget.controller.hasClients) return;
    final maxScroll = widget.controller.position.maxScrollExtent;
    // FIX(sahte-kontrol): Kaydırılamayan listede setState ile thumb'ı oynatmak,
    // parmağı takip eden ama hiçbir şeyi kaydırmayan sahte bir kontrol
    // üretiyordu; kullanıcı listeyi kilitlenmiş sanıyordu.
    if (maxScroll <= 0) return;

    final ratio = fastScrollerDragRatio(
      startRatio: _dragStartRatio,
      deltaY: globalY - _dragStartGlobalY,
      effectiveTrackHeight: effectiveTrackHeight,
    );

    if (ratio != _thumbPositionRatio) {
      setState(() {
        _thumbPositionRatio = ratio;
      });
    }
    widget.controller.jumpTo((ratio * maxScroll).clamp(0.0, maxScroll));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final trackHeight = (totalHeight - widget.topPadding - widget.bottomPadding)
            .clamp(1.0, double.infinity);
        final effectiveTrackHeight = (trackHeight - _thumbHeight).clamp(1.0, double.infinity);
        final thumbTop = widget.topPadding + (_thumbPositionRatio * effectiveTrackHeight);
        final grabHeight = _thumbHeight + _thumbTouchPadding * 2;
        final maxGrabTop = (totalHeight - grabHeight).clamp(0.0, double.infinity);
        final grabTop = (thumbTop - _thumbTouchPadding).clamp(0.0, maxGrabTop);

        return Stack(
          children: [
            // FIX(bayat-thumb-2): ScrollController yalnızca piksel değiştiğinde
            // haber verir. Kullanıcı listenin başındayken arama kutusuna yazıp
            // listeyi kaydırılamaz hale getirdiğinde piksel zaten sıfır olduğu
            // için tek bir bildirim gelmiyor, gösterge ekranda kalıyor ve
            // sürüklendiğinde hiçbir şeyi kaydırmayan sahte bir kontrole
            // dönüşüyordu. İçerik ölçüleri değiştiğinde Flutter ayrıca
            // ScrollMetricsNotification yayınlar (kare bittikten sonra, bir
            // mikrogörevde), durumu oradan da tazeliyoruz.
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                _syncThumbFromPosition();
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification ||
                      notification is OverscrollNotification ||
                      notification is UserScrollNotification) {
                    _showScrollbar();
                  }
                  return false;
                },
                child: widget.child,
              ),
            ),
            // FIX(serit): Yakalama alanı eskiden sağ kenarı boydan boya kaplayan
            // 32 piksellik bir şeritti ve dokunulan yere anında ışınlıyordu.
            // Telefonu sağ eliyle tutan kullanıcı listeyi 40 piksel kaydırmak
            // isterken listenin ortasına fırlıyor, aşağı çekerek yenileme ise
            // hiç tetiklenmiyordu (şerit dikey sürüklemeyi yutuyordu). Alan
            // artık yalnızca thumb'ın çevresi kadar; dışındaki dokunuşlar
            // doğrudan listeye geçtiği için normal kaydırma ve yenileme çalışır.
            if (_canScroll)
              Positioned(
                top: grabTop,
                right: 0,
                width: 32,
                height: grabHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) {
                    _dragStartGlobalY = details.globalPosition.dy;
                    _dragStartRatio = _thumbPositionRatio;
                    setState(() {
                      _isDragging = true;
                    });
                    _showScrollbar();
                  },
                  onVerticalDragUpdate: (details) {
                    _handleDrag(details.globalPosition.dy, effectiveTrackHeight);
                  },
                  onVerticalDragEnd: (details) {
                    setState(() {
                      _isDragging = false;
                    });
                    _showScrollbar(); // Starts 3s hide timer
                  },
                  onVerticalDragCancel: () {
                    setState(() {
                      _isDragging = false;
                    });
                    _showScrollbar();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            // Scrollbar Thumb
            if (_canScroll)
              Positioned(
                top: thumbTop,
                right: 4,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _isDragging ? 7.0 : 4.5,
                    height: _thumbHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _isDragging
                            ? [
                                AmoledTheme.brandRed,
                                const Color(0xFFFF5252),
                              ]
                            : [
                                AmoledTheme.brandRed.withValues(alpha: 0.85),
                                AmoledTheme.brandRed.withValues(alpha: 0.5),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isDragging
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.transparent,
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AmoledTheme.brandRed.withValues(
                              alpha: _isDragging ? 0.6 : 0.25),
                          blurRadius: _isDragging ? 8 : 4,
                          spreadRadius: _isDragging ? 1 : 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
