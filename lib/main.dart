import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/download_provider.dart';
import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/amoled_theme.dart';
import 'services/background_sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSyncManager.initialize();

  // Set system UI overlay style to pure black AMOLED
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AmoledTheme.pureBlack,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const OfflineYoutubeApp());
}

class OfflineYoutubeApp extends StatelessWidget {
  const OfflineYoutubeApp({super.key});

  // FIX(startup-race): Ayarların "yükleniyor -> yüklendi" geçişini izlemek
  // için önceki durumu hatırlar (indirme klasörü ancak ayar yüklemesi
  // tamamlanınca oluşturuluyor). StatelessWidget içinde static olmalı.
  static bool _lastSettingsLoading = true;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProxyProvider2<SettingsProvider, LibraryProvider, DownloadProvider>(
          create: (_) => DownloadProvider(),
          update: (_, settingsProvider, libraryProvider, downloadProvider) {
            final provider = downloadProvider ?? DownloadProvider();
            provider.onLibraryNeedsRefresh = () => libraryProvider.refresh();
            // FIX(startup-race): Ayarlar yüklenip indirme klasörü
            // oluşturulduğunda kütüphaneyi yeniden tara — aksi halde
            // klasör-öncesi boş tarama sonucu ekranda kalıyordu.
            final wasLoading = _lastSettingsLoading;
            _lastSettingsLoading = settingsProvider.isLoading;
            if (wasLoading && !settingsProvider.isLoading) {
              libraryProvider.refresh();
            }
            if (!settingsProvider.isLoading) {
              provider.onSettingsChanged(settingsProvider.settings);
            }
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Offline YouTube',
        debugShowCheckedModeBanner: false,
        theme: AmoledTheme.themeData,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
