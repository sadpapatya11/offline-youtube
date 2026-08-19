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
    this.maxVideoDurationHours = 6,
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
        maxStorageLimitGB: json['maxStorageLimitGB'] as int? ?? 20,
        maxVideoDurationHours: json['maxVideoDurationHours'] as int? ?? 6,
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
}
