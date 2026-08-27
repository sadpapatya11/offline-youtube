import 'package:flutter/foundation.dart';

import '../services/storage_manager.dart';

enum NetworkRestrictionMode {
  anyWifi, // Sadece Wi-Fi
  allNetworks, // Mobil Veri ve Wi-Fi (Tüm Ağlar)
}

class AppSettings {
  final int maxStorageLimitGB; // Min 1 GB
  final int maxVideoDurationHours; // Min 1 Saat
  final NetworkRestrictionMode networkMode;
  final String customDownloadPath;
  final bool autoDownloadOnPaste;
  final bool playlistReverseOrder;
  final List<String> savedPlaylists;

  const AppSettings({
    this.maxStorageLimitGB = 20,
    this.maxVideoDurationHours = 10000,
    this.networkMode = NetworkRestrictionMode.anyWifi, // Varsaylan Sadece Wi-Fi
    this.customDownloadPath = StorageManager.defaultHiddenPath,
    this.autoDownloadOnPaste = true,
    this.playlistReverseOrder = true,
    this.savedPlaylists = const [],
  });

  AppSettings copyWith({
    int? maxStorageLimitGB,
    int? maxVideoDurationHours,
    NetworkRestrictionMode? networkMode,
    String? customDownloadPath,
    bool? autoDownloadOnPaste,
    bool? playlistReverseOrder,
    List<String>? savedPlaylists,
  }) {
    return AppSettings(
      maxStorageLimitGB: maxStorageLimitGB ?? this.maxStorageLimitGB,
      maxVideoDurationHours: maxVideoDurationHours ?? this.maxVideoDurationHours,
      networkMode: networkMode ?? this.networkMode,
      customDownloadPath: customDownloadPath ?? this.customDownloadPath,
      autoDownloadOnPaste: autoDownloadOnPaste ?? this.autoDownloadOnPaste,
      playlistReverseOrder: playlistReverseOrder ?? this.playlistReverseOrder,
      savedPlaylists: savedPlaylists ?? this.savedPlaylists,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxStorageLimitGB': maxStorageLimitGB,
        'maxVideoDurationHours': maxVideoDurationHours,
        'networkMode': networkMode.index,
        'customDownloadPath': customDownloadPath,
        'autoDownloadOnPaste': autoDownloadOnPaste,
        'playlistReverseOrderV3': playlistReverseOrder,
        'savedPlaylists': savedPlaylists,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        maxStorageLimitGB: _readLimit(json['maxStorageLimitGB'], 20),
        maxVideoDurationHours: _readLimit(json['maxVideoDurationHours'], 6),
        networkMode: NetworkRestrictionMode.values[
            (json['networkMode'] as int? ?? 0).clamp(0, NetworkRestrictionMode.values.length - 1)],
        customDownloadPath: json['customDownloadPath'] as String? ??
            StorageManager.defaultHiddenPath,
        autoDownloadOnPaste: json['autoDownloadOnPaste'] as bool? ?? true,
        playlistReverseOrder: json['playlistReverseOrderV3'] as bool? ?? true,
        savedPlaylists: (json['savedPlaylists'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  /// Kayıtlı sayısal sınırı okur ve alt sınırı uygular.
  ///
  /// Kayıtta 0 (veya negatif) bir değer kuyruğu KALICI kilitliyordu:
  /// processNextQueue `usedBytes >= maxBytes` ve
  /// `totalDurationSec >= maxDurationSec` kapılarında her görevi "kota doldu"
  /// diye hataya düşürüyor, kullanıcı ayarı elle düzeltene kadar tek bir indirme
  /// bile başlamıyordu. Hemen aşağıdaki networkMode clamp'i ile aynı kalıp.
  /// Değer yoksa varsayılan, geçersizse izin verilen en küçük değer (1) kullanılır;
  /// varsayılana yükseltmek kullanıcının hiç vermediği bir sınırı uydurmak olurdu.
  static int _readLimit(dynamic raw, int fallback) {
    if (raw is! num) return fallback;
    final value = raw.toInt();
    return value < 1 ? 1 : value;
  }

  /// Değer eşitliği: ayarların GERÇEKTEN değişip değişmediği ölçülebilsin diye.
  ///
  /// main.dart'taki ProxyProvider update'i her SettingsProvider veya
  /// LibraryProvider bildiriminde koşuyor. Kimlik karşılaştırmasıyla "değişmedi"
  /// denemediği için her indirme bitişinde onSettingsChanged çağrılıyor, o da
  /// processNextQueue üzerinden iki tam disk taraması (getUsedStorageBytes +
  /// scanDownloadedVideos) başlatıyordu.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.maxStorageLimitGB == maxStorageLimitGB &&
          other.maxVideoDurationHours == maxVideoDurationHours &&
          other.networkMode == networkMode &&
          other.customDownloadPath == customDownloadPath &&
          other.autoDownloadOnPaste == autoDownloadOnPaste &&
          other.playlistReverseOrder == playlistReverseOrder &&
          listEquals(other.savedPlaylists, savedPlaylists);

  @override
  int get hashCode => Object.hash(
        maxStorageLimitGB,
        maxVideoDurationHours,
        networkMode,
        customDownloadPath,
        autoDownloadOnPaste,
        playlistReverseOrder,
        Object.hashAll(savedPlaylists),
      );
}
