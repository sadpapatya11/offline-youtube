import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_settings.dart';
import 'providers/download_provider.dart';
import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/amoled_theme.dart';
import 'services/background_sync_manager.dart';
import 'services/youtube_api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSyncManager.initialize();
  YoutubeApiService().init();

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

class OfflineYoutubeApp extends StatefulWidget {
  const OfflineYoutubeApp({super.key});

  @override
  State<OfflineYoutubeApp> createState() => _OfflineYoutubeAppState();
}

class _OfflineYoutubeAppState extends State<OfflineYoutubeApp> {
  // FIX(startup-race): Ayarların "yükleniyor -> yüklendi" geçişini izlemek
  // için önceki durumu hatırlar (indirme klasörü ancak ayar yüklemesi
  // tamamlanınca oluşturuluyor).
  //
  // Bu alan eskiden StatelessWidget içinde static'ti: uygulama aynı süreçte
  // ikinci kez ayağa kalktığında (widget testlerinde art arda pumpWidget)
  // bayat "false" değeri kalıyor, ayar yüklemesi bitse bile kütüphane bir daha
  // hiç taranmıyordu. State alanı her örnekte sıfırdan başlar.
  bool _lastSettingsLoading = true;

  // En son UYGULANAN ayarlar. update her SettingsProvider VEYA LibraryProvider
  // bildiriminde koşuyor; koşulsuz onSettingsChanged çağrısı her indirme
  // bitişinde processNextQueue'yu, o da getUsedStorageBytes + scanDownloadedVideos
  // ile iki tam disk taramasını tetikliyordu. 300 videoluk kütüphanede arayüz
  // takılıyordu. Kuyruk gerçekten durmaz: ağ değişimi, görev ekleme, uygulamaya
  // dönüş ve tamamlanma yollarının hepsi processNextQueue'yu ayrıca çağırıyor.
  AppSettings? _appliedSettings;

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
              final settings = settingsProvider.settings;
              if (_appliedSettings != settings) {
                _appliedSettings = settings;
                provider.onSettingsChanged(settings);
              }
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
