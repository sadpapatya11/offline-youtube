import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_settings.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
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

  Future<void> _updateEngine() async {
    setState(() {
      _isUpdatingYtDlp = true;
    });
    final success = await NativeBridge.instance.updateYtDlp();
    setState(() {
      _isUpdatingYtDlp = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'yt-dlp motoru başarıyla güncellendi!'
              : 'yt-dlp güncellemesi başarısız oldu.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final settings = settingsProvider.settings;

    final usedGB =
        (libraryProvider.totalUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    final isOnlyWifi = settingsProvider.isOnlyWifiEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AYARLAR VE KISITLAMALAR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ağ ve İndirme Kısıtlamaları
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.network_check_rounded, color: AmoledTheme.pureWhite, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Ağ ve Bağlantı Kuralı',
                        style: TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Sadece Wi-Fi ile İndir',
                      style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      isOnlyWifi
                          ? 'Aktif: Mobil verideyken indirmeler bekletilir, Wi-Fi bağlanınca başlar.'
                          : 'Kapalı: Hem Mobil Veri hem Wi-Fi üzerinden indirmeye izin verilir.',
                      style: const TextStyle(color: AmoledTheme.subText, fontSize: 12),
                    ),
                    value: isOnlyWifi,
                    activeColor: AmoledTheme.pureWhite,
                    onChanged: (bool value) {
                      settingsProvider.setOnlyWifi(value);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(value
                              ? 'Ağ kısıtlaması: Yalnızca Wi-Fi aktif edildi.'
                              : 'Ağ kısıtlaması: Mobil Veri ve Wi-Fi aktif edildi.'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const Divider(color: AmoledTheme.borderDark),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Oynatma Listesinde En Yeni Videoları Önce İndir',
                      style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Oynatma listelerinde en son eklenen / yayınlanan videolar ilk sıraya alınır.',
                      style: TextStyle(color: AmoledTheme.subText, fontSize: 12),
                    ),
                    value: settings.playlistReverseOrder,
                    activeColor: AmoledTheme.pureWhite,
                    onChanged: (bool value) {
                      settingsProvider.togglePlaylistReverse(value);
                    },
                  ),
                  const Divider(color: AmoledTheme.borderDark),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Bağlantı Yapıştırıldığında Otomatik Başlat',
                      style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Manuel butonlara basmadan yapıştırıldığı an en yüksek kalitede indirir.',
                      style: TextStyle(color: AmoledTheme.subText, fontSize: 12),
                    ),
                    value: settings.autoDownloadOnPaste,
                    activeColor: AmoledTheme.pureWhite,
                    onChanged: (bool value) {
                      settingsProvider.toggleAutoDownload(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Depolama Kotası
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.pie_chart_outline_rounded, color: AmoledTheme.pureWhite, size: 20),
                      SizedBox(width: 8),
                      Text(
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
                    'Mevcut Kullanım: $usedGB GB / ${settings.maxStorageLimitGB} GB',
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
                          color: AmoledTheme.pureWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AmoledTheme.pureWhite,
                      inactiveTrackColor: AmoledTheme.accentGray,
                      thumbColor: AmoledTheme.pureWhite,
                    ),
                    child: Slider(
                      value: settings.maxStorageLimitGB.toDouble().clamp(1.0, 100.0),
                      min: 1.0,
                      max: 100.0,
                      divisions: 99,
                      label: '${settings.maxStorageLimitGB} GB',
                      onChanged: (val) {
                        settingsProvider.updateStorageLimit(val.toInt());
                      },
                    ),
                  ),
                  const Text(
                    'Depolama bu limite ulaştığında yeni indirmeler otomatik olarak engellenir.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Video Süresi Sınırı
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.timer_outlined, color: AmoledTheme.pureWhite, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Maksimum Video Uzunluğu',
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
                        'Maksimum Süre:',
                        style: TextStyle(color: AmoledTheme.pureWhite, fontSize: 13),
                      ),
                      Text(
                        '${settings.maxVideoDurationHours} Saat',
                        style: const TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AmoledTheme.pureWhite,
                      inactiveTrackColor: AmoledTheme.accentGray,
                      thumbColor: AmoledTheme.pureWhite,
                    ),
                    child: Slider(
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
                  ),
                  const Text(
                    'Bu süreden daha uzun olan videolar indirme öncesi metadata kontrolüyle filtrelenir.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Gizli Depolama & İzinler
            AmoledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_special_outlined, color: AmoledTheme.pureWhite, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Gizli Depolama ve İzinler',
                        style: TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'İndirilen Dosya Yolu:',
                    style: TextStyle(color: AmoledTheme.subText, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    settings.customDownloadPath,
                    style: const TextStyle(
                      color: AmoledTheme.pureWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Klasör içindeki .nomedia dosyası sayesinde indirilen içerikler cihaz galerisinde ve medya oynatıcılarda görünmez.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        settingsProvider.hasStoragePermission
                            ? 'Tüm Dosyalara Erişim İzni: Verildi'
                            : 'Tüm Dosyalara Erişim İzni: Gerekli',
                        style: TextStyle(
                          color: settingsProvider.hasStoragePermission
                              ? const Color(0xFF00FF66)
                              : const Color(0xFFFFCC00),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!settingsProvider.hasStoragePermission)
                        ElevatedButton(
                          onPressed: () => settingsProvider.requestPermission(),
                          child: const Text('İzin Ver'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // yt-dlp Güncelleme
            AmoledCard(
              child: Row(
                children: [
                  const Icon(Icons.system_update_alt_rounded, color: AmoledTheme.pureWhite),
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
                          'YouTube backend değişikliklerine karşı motoru güncel tutar.',
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
                              valueColor: AlwaysStoppedAnimation<Color>(AmoledTheme.pureBlack),
                            ),
                          )
                        : const Text('Güncelle'),
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
