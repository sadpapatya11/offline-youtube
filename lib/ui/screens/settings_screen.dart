import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_settings.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
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
                ? 'yt-dlp motoru başarıyla en güncel sürüme yükseltildi.'
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
    final usedGB =
        (libraryProvider.totalUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AYARLAR VE KISITLAMALAR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Ağ ve İndirme Kısıtlamaları
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
                          Icons.network_check_rounded,
                          color: isOnlyWifi
                              ? AmoledTheme.brandRed
                              : AmoledTheme.pureWhite,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
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

                  // Switch 1: Sadece Wi-Fi ile İndir
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
                          ? 'Aktif: Mobil verideyken indirmeler bekletilir, Wi-Fi bağlanınca başlar.'
                          : 'Kapalı: Hem Mobil Veri hem Wi-Fi üzerinden indirmeye izin verilir.',
                      style: TextStyle(
                        color: isOnlyWifi
                            ? AmoledTheme.pureWhite.withValues(alpha: 0.9)
                            : AmoledTheme.subText,
                        fontSize: 12,
                      ),
                    ),
                    value: isOnlyWifi,
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

                  // Switch 2: Oynatma Listesinde En Yeni Videoları Önce İndir
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
                      'Oynatma listelerinde en son eklenen / yayınlanan videolar ilk sıraya alınır.',
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

                  // Switch 3: Bağlantı Yapıştırıldığında Otomatik Başlat
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: settings.autoDownloadOnPaste
                            ? AmoledTheme.brandRed.withValues(alpha: 0.2)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: settings.autoDownloadOnPaste
                              ? AmoledTheme.brandRed.withValues(alpha: 0.4)
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        color: settings.autoDownloadOnPaste
                            ? AmoledTheme.brandRed
                            : const Color(0xFF888888),
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Bağlantı Yapıştırıldığında Otomatik Başlat',
                      style: TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Manuel butonlara basmadan yapıştırıldığı an en yüksek kalitede indirir.',
                      style: TextStyle(
                        color: settings.autoDownloadOnPaste
                            ? AmoledTheme.pureWhite.withValues(alpha: 0.9)
                            : AmoledTheme.subText,
                        fontSize: 12,
                      ),
                    ),
                    value: settings.autoDownloadOnPaste,
                    onChanged: (bool value) {
                      settingsProvider.toggleAutoDownload(value);
                    },
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
                    'Depolama bu limite ulaştığında yeni indirmeler otomatik olarak engellenir.',
                    style: TextStyle(color: Color(0xFF777777), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Video Süresi Sınırı
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

            // 4. Gizli Depolama & İzinler
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
                          Icons.folder_special_outlined,
                          color: AmoledTheme.brandRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
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

            // 5. yt-dlp Güncelleme
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
                              valueColor: AlwaysStoppedAnimation<Color>(AmoledTheme.pureWhite),
                            ),
                          )
                        : const Text('Güncelle'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6. Sürüm Bilgisi Rozeti
            Center(
              child: Column(
                children: [
                  Text(
                    'Offline YouTube v1.3.1 (Build 6)',
                    style: TextStyle(
                      color: AmoledTheme.pureWhite.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toplam Süre Kotası • Geri Dönüşüm Kutusu • Otomasyon',
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
