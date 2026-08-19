import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:offlineyoutube/ui/screens/youtube_login_screen.dart';
import '../../models/app_settings.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/download_provider.dart';
import '../../services/youtube_api_service.dart';
import '../../services/native_bridge.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isUpdatingYtDlp = false;
  bool _isIgnoringBatteryOpt = true;
  String _versionInfo = 'Offline YouTube';

  @override
  void initState() {
    super.initState();
    _checkBatteryOpt();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _versionInfo =
              'Offline YouTube v${info.version} (Build ${info.buildNumber})';
        });
      }
    } catch (_) {}
  }

  Future<void> _checkBatteryOpt() async {
    final ignored = await NativeBridge.instance.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isIgnoringBatteryOpt = ignored;
      });
    }
  }

  Future<void> _requestBatteryOpt() async {
    await NativeBridge.instance.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(seconds: 1));
    await _checkBatteryOpt();
  }

  Future<void> _updateEngine() async {
    setState(() {
      _isUpdatingYtDlp = true;
    });

    final settingsProvider = context.read<SettingsProvider>();
    final success = await settingsProvider.updateYtDlp();

    if (mounted) {
      setState(() {
        _isUpdatingYtDlp = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'yt-dlp motoru başarıyla güncellendi.'
                : 'yt-dlp motoru güncellenirken bir hata oluştu veya zaten güncel.',
          ),
          backgroundColor:
              success ? const Color(0xFF003311) : const Color(0xFF330000),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final settings = settingsProvider.settings;

    final isOnlyWifi =
        settings.networkMode == NetworkRestrictionMode.anyWifi;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AYARLAR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. yt-dlp Güncelle (EN ÜSTTE)
            AmoledCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AmoledTheme.brandRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: AmoledTheme.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'yt-dlp Motorunu Güncelle',
                          style: TextStyle(
                            color: AmoledTheme.pureWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'YouTube değişikliklerine karşı indirme motorunu günceller.',
                          style: TextStyle(color: AmoledTheme.subText, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isUpdatingYtDlp ? null : _updateEngine,
                    child: _isUpdatingYtDlp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                            ),
                          )
                        : const Text('Güncelle'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1.5 YouTube Giriş Yap (Çerez Entegrasyonu)
            AmoledCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AmoledTheme.brandRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.login_rounded,
                      color: AmoledTheme.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YouTube\'a Giriş Yap',
                          style: TextStyle(
                            color: AmoledTheme.pureWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Yaş kısıtlamalı ve gizli videoları indirmek için oturum açın.',
                          style: TextStyle(color: AmoledTheme.subText, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const YoutubeLoginScreen()),
                      );
                    },
                    child: const Text('Giriş Yap'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1.6 Google Hesabı (Otomatik YouTube Silme)
            AmoledCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Color(0xFF4285F4),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Hesabını Bağla',
                          style: TextStyle(
                            color: AmoledTheme.pureWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          YoutubeApiService().currentUser != null
                              ? 'Bağlı: ${YoutubeApiService().currentUser!.email}'
                              : 'Çöp kutusundaki videoları YouTube\'dan otomatik kalıcı silmek için.',
                          style: const TextStyle(color: AmoledTheme.subText, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YoutubeApiService().currentUser != null
                          ? const Color(0xFF333333)
                          : const Color(0xFF4285F4),
                    ),
                    onPressed: () async {
                      if (YoutubeApiService().currentUser != null) {
                        await YoutubeApiService().signOut();
                        setState(() {});
                      } else {
                        final account = await YoutubeApiService().signIn();
                        if (account == null) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Giriş başarısız. Package Name (com.offlineyoutube.offlineyoutube) veya SHA-1 hatalı olabilir.'),
                              backgroundColor: AmoledTheme.brandRed,
                            ),
                          );
                        } else {
                          setState(() {});
                        }
                      }
                    },
                    child: Text(YoutubeApiService().currentUser != null ? 'Çıkış' : 'Bağla'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Depolama Kotası
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AmoledTheme.brandRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.pie_chart_outline_rounded,
                          color: AmoledTheme.brandRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Depolama Kotası Yöneticisi',
                        style: TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mevcut Kullanım: ${libraryProvider.formattedTotalUsed} / ${settings.maxStorageLimitGB} GB',
                    style: const TextStyle(color: AmoledTheme.subText, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Maksimum Depolama Alanı:',
                        style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 13),
                      ),
                      Text(
                        '${settings.maxStorageLimitGB} GB',
                        style: const TextStyle(
                          color: AmoledTheme.brandRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.maxStorageLimitGB.toDouble().clamp(1.0, 100.0),
                    min: 1.0,
                    max: 100.0,
                    divisions: 99,
                    label: '${settings.maxStorageLimitGB} GB',
                    onChanged: (val) {
                      settingsProvider.updateStorageLimit(val.toInt());
                    },
                  ),
                  const Text(
                    'Depolama bu limite ulaştığında yeni indirmeler otomatik olarak duraklatılır.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Toplam Video Süresi Kotası
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AmoledTheme.brandRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.timer_outlined,
                          color: AmoledTheme.brandRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Toplam Video Süresi Kotası',
                        style: TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mevcut Kullanım / Kota:',
                        style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 13),
                      ),
                      Text(
                        '${libraryProvider.formattedTotalDuration} / ${settings.maxVideoDurationHours} Saat',
                        style: const TextStyle(
                          color: AmoledTheme.brandRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.maxVideoDurationHours
                        .toDouble()
                        .clamp(1.0, 24.0),
                    min: 1.0,
                    max: 24.0,
                    divisions: 23,
                    label: '${settings.maxVideoDurationHours} Saat',
                    onChanged: (val) {
                      settingsProvider.updateMaxVideoDuration(val.toInt());
                    },
                  ),
                  const Text(
                    'İndirilen tüm videoların toplam uzunluğu bu kotayı aşamaz. Kota dolduğunda indirmeler duraklatılır.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Ağ Kuralları (Toplam Video Süresi'nin ALTINDA)
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isOnlyWifi
                              ? AmoledTheme.brandRed.withValues(alpha: 0.15)
                              : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.wifi_rounded,
                          color: isOnlyWifi
                              ? AmoledTheme.brandRed
                              : AmoledTheme.pureWhite,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Ağ Kuralları',
                        style: TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Switch: Sadece Wi-Fi ile İndir
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isOnlyWifi
                            ? AmoledTheme.brandRed.withValues(alpha: 0.2)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnlyWifi
                              ? AmoledTheme.brandRed.withValues(alpha: 0.4)
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Icon(
                        isOnlyWifi ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                        color: isOnlyWifi
                            ? AmoledTheme.brandRed
                            : const Color(0xFF888888),
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Sadece Wi-Fi ile İndir',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      isOnlyWifi
                          ? 'Aktif: Mobil verideyken indirmeler bekletilir. Kapatıldığında 1 saat sonra otomatik olarak tekrar açılır.'
                          : 'Kapalı: Mobil Veri aktif. 1 saat sonra otomatik olarak Wi-Fi moduna geri dönecektir.',
                      style: TextStyle(
                        color: isOnlyWifi
                            ? AmoledTheme.pureWhite.withValues(alpha: 0.9)
                            : const Color(0xFFFFCC00),
                        fontSize: 12,
                      ),
                    ),
                    value: isOnlyWifi,
                    onChanged: (bool value) {
                      settingsProvider.setOnlyWifi(value);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(value
                              ? 'Sadece Wi-Fi ile indirme açıldı.'
                              : 'Mobil veri açıldı. 1 saat sonra otomatik olarak Wi-Fi moduna dönecek.'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                  const Divider(color: AmoledTheme.borderDark),

                  // Switch: Oynatma Listesinde En Yeni Videoları Önce İndir
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: settings.playlistReverseOrder
                            ? AmoledTheme.brandRed.withValues(alpha: 0.2)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: settings.playlistReverseOrder
                              ? AmoledTheme.brandRed.withValues(alpha: 0.4)
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Icon(
                        Icons.playlist_play_rounded,
                        color: settings.playlistReverseOrder
                            ? AmoledTheme.brandRed
                            : const Color(0xFF888888),
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Oynatma Listesinde En Yeni Videoları Önce İndir',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Oynatma listelerinde en son eklenen videolar ilk sıraya alınır.',
                      style: TextStyle(
                        color: settings.playlistReverseOrder
                            ? AmoledTheme.pureWhite.withValues(alpha: 0.9)
                            : AmoledTheme.subText,
                        fontSize: 12,
                      ),
                    ),
                    value: settings.playlistReverseOrder,
                    onChanged: (bool value) {
                      settingsProvider.togglePlaylistReverse(value);
                    },
                  ),
                  const Divider(color: AmoledTheme.borderDark),

                  // Manuel Oynatma Listesi Eşitleme
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AmoledTheme.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sync_rounded,
                          color: Colors.white, size: 22),
                    ),
                    title: const Text(
                      'Oynatma Listelerini Şimdi Eşitle',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Kayıtlı listelerinizdeki yeni videoları kuyruğa ekler.',
                      style: TextStyle(
                        color: AmoledTheme.subText,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Consumer<DownloadProvider>(
                      builder: (context, provider, child) {
                        return provider.isSyncingPlaylists
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: AmoledTheme.brandRed,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right, color: AmoledTheme.subText);
                      },
                    ),
                    onTap: () {
                      final provider = context.read<DownloadProvider>();
                      final settings = context.read<SettingsProvider>().settings;
                      final libraryProvider = context.read<LibraryProvider>();
                      if (!provider.isSyncingPlaylists) {
                        provider.syncSavedPlaylists(
                          settings: settings,
                          libraryProvider: libraryProvider,
                        ).then((result) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result.message ?? 'Eşitleme tamamlandı.'),
                                backgroundColor: AmoledTheme.cardDark,
                              ),
                            );
                          }
                        });
                      }
                    },
                  ),
                  const Divider(color: AmoledTheme.borderDark),

                  // Arka Planda Kesintisiz İndirme (Pil Kısıtlaması)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isIgnoringBatteryOpt
                            ? const Color(0xFF003311)
                            : AmoledTheme.brandRed.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isIgnoringBatteryOpt
                              ? const Color(0xFF00AA44)
                              : AmoledTheme.brandRed.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(
                        _isIgnoringBatteryOpt
                            ? Icons.battery_charging_full_rounded
                            : Icons.battery_alert_rounded,
                        color: _isIgnoringBatteryOpt
                            ? const Color(0xFF00FF66)
                            : AmoledTheme.brandRed,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Arka Planda Kesintisiz İndirme',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _isIgnoringBatteryOpt
                          ? 'Aktif: Ekran kapalıyken veya uygulamadan çıkıldığında indirme devam eder.'
                          : 'Kısıtlı: Pil tasarrufu açık. Ekran kapandığında indirmelerin durmaması için dokunup muafiyet verin.',
                      style: TextStyle(
                        color: _isIgnoringBatteryOpt
                            ? const Color(0xFF00FF66)
                            : const Color(0xFFFFCC00),
                        fontSize: 12,
                      ),
                    ),
                    trailing: _isIgnoringBatteryOpt
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF00FF66), size: 20)
                        : ElevatedButton(
                            onPressed: _requestBatteryOpt,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AmoledTheme.brandRed,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            child: const Text('İzin Ver',
                                style: TextStyle(fontSize: 12)),
                          ),
                    onTap: _requestBatteryOpt,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5. Sürüm Bilgisi
            Center(
              child: Column(
                children: [
                  Text(
                    _versionInfo,
                    style: TextStyle(
                      color: AmoledTheme.pureWhite.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AMOLED UI • Türkçe Altyazı • 2X Dokun & Hızlandır',
                    style: TextStyle(
                      color: AmoledTheme.subText.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
