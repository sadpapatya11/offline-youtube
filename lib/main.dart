import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/download_provider.dart';
import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/amoled_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
            if (!settingsProvider.isLoading) {
              provider.onSettingsChanged(settingsProvider.settings);
            }
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'offlineyoutube',
        debugShowCheckedModeBanner: false,
        theme: AmoledTheme.themeData,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
