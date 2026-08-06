import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../theme/amoled_theme.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final libraryProvider = context.watch<LibraryProvider>();

    final activeCount = downloadProvider.activeDownloadCount;
    final isDownloading = downloadProvider.isDownloadingActive;
    final downloadedCount = libraryProvider.videos.length;

    final screens = [
      HomeScreen(onNavigateToQueue: () => _navigateToTab(2)),
      const DownloadsScreen(),
      const QueueScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AmoledTheme.pureBlack,
          border: Border(
            top: BorderSide(color: AmoledTheme.borderDark, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _navigateToTab,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_filled),
              label: 'Ana Sayfa',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: downloadedCount > 0,
                label: Text(
                  '$downloadedCount',
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                backgroundColor: const Color(0xFF333333),
                child: const Icon(Icons.video_library_outlined),
              ),
              activeIcon: Badge(
                isLabelVisible: downloadedCount > 0,
                label: Text(
                  '$downloadedCount',
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                backgroundColor: AmoledTheme.brandRed,
                child: const Icon(Icons.video_library_rounded),
              ),
              label: 'İndirilenler',
            ),
            BottomNavigationBarItem(
              icon: AnimatedDownloadIcon(
                isDownloading: isDownloading,
                isActiveTab: false,
                badgeCount: activeCount,
              ),
              activeIcon: AnimatedDownloadIcon(
                isDownloading: isDownloading,
                isActiveTab: true,
                badgeCount: activeCount,
              ),
              label: 'Kuyruk',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Ayarlar',
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedDownloadIcon extends StatefulWidget {
  final bool isDownloading;
  final bool isActiveTab;
  final int badgeCount;

  const AnimatedDownloadIcon({
    super.key,
    required this.isDownloading,
    required this.isActiveTab,
    required this.badgeCount,
  });

  @override
  State<AnimatedDownloadIcon> createState() => _AnimatedDownloadIconState();
}

class _AnimatedDownloadIconState extends State<AnimatedDownloadIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnimation = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isDownloading) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedDownloadIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDownloading != oldWidget.isDownloading) {
      if (widget.isDownloading) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: widget.badgeCount > 0,
      label: Text(
        '${widget.badgeCount}',
        style: const TextStyle(
          color: AmoledTheme.pureWhite,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
      backgroundColor: AmoledTheme.brandRed,
      child: widget.isDownloading
          ? AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _slideAnimation.value),
                  child: const Icon(
                    Icons.arrow_circle_down_rounded,
                    color: AmoledTheme.brandRed,
                  ),
                );
              },
            )
          : Icon(
              widget.isActiveTab
                  ? Icons.download_rounded
                  : Icons.download_outlined,
            ),
    );
  }
}
