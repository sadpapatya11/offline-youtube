import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/amoled_theme.dart';

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

  void _onScroll() {
    if (!mounted || _isDragging) return;
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    if (position.maxScrollExtent > 0) {
      final ratio = (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
      setState(() {
        _thumbPositionRatio = ratio;
      });
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

  void _handleDrag(double localY, double availableHeight) {
    if (availableHeight <= 0) return;
    final ratio = (localY / availableHeight).clamp(0.0, 1.0);
    setState(() {
      _thumbPositionRatio = ratio;
    });

    if (widget.controller.hasClients) {
      final maxScroll = widget.controller.position.maxScrollExtent;
      if (maxScroll > 0) {
        final targetOffset = (ratio * maxScroll).clamp(0.0, maxScroll);
        widget.controller.jumpTo(targetOffset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final trackHeight = (totalHeight - widget.topPadding - widget.bottomPadding)
            .clamp(1.0, double.infinity);
        const thumbHeight = 48.0;
        final effectiveTrackHeight = (trackHeight - thumbHeight).clamp(1.0, double.infinity);
        final thumbTop = widget.topPadding + (_thumbPositionRatio * effectiveTrackHeight);

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
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
            // Fast Scroller Overlay Right Strip
            Positioned(
              top: widget.topPadding,
              bottom: widget.bottomPadding,
              right: 0,
              width: 32, // Narrow right-aligned touch area to prevent accidental touches
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (details) {
                  setState(() {
                    _isDragging = true;
                  });
                  _showScrollbar();
                  _handleDrag(details.localPosition.dy, trackHeight);
                },
                onVerticalDragUpdate: (details) {
                  _handleDrag(details.localPosition.dy, trackHeight);
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
            Positioned(
              top: thumbTop,
              right: 4,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isDragging ? 7.0 : 4.5,
                  height: thumbHeight,
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
