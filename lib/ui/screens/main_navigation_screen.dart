import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/download_provider.dart';
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
    final activeCount = downloadProvider.activeDownloadCount;

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
            const BottomNavigationBarItem(
              icon: Icon(Icons.video_library_outlined),
              activeIcon: Icon(Icons.video_library_rounded),
              label: 'İndirilenler',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount',
                    style: const TextStyle(
                        color: AmoledTheme.pureBlack,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
                backgroundColor: AmoledTheme.pureWhite,
                child: const Icon(Icons.download_outlined),
              ),
              activeIcon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount',
                    style: const TextStyle(
                        color: AmoledTheme.pureBlack,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
                backgroundColor: AmoledTheme.pureWhite,
                child: const Icon(Icons.download_rounded),
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
