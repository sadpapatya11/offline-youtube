enum NetworkRestrictionMode {
  selectedWifi, // Sadece Seçili Wi-Fi (SSID)
  anyWifi, // Herhangi bir Wi-Fi
  allNetworks, // Mobil Veri ve Wi-Fi (Tüm Ağlar)
}

class AppSettings {
  final int maxStorageLimitGB; // Min 1 GB
  final int maxVideoDurationHours; // Min 1 Saat
  final NetworkRestrictionMode networkMode;
  final String allowedWifiSsid;
  final String customDownloadPath;
  final bool autoDownloadOnPaste;
  final bool playlistReverseOrder;
  final List<String> savedPlaylists;

  const AppSettings({
    this.maxStorageLimitGB = 20,
    this.maxVideoDurationHours = 6,
    this.networkMode = NetworkRestrictionMode.allNetworks, // Varsayılan tüm ağlar (mobil veri + wifi)
    this.allowedWifiSsid = '',
    this.customDownloadPath = '/storage/emulated/0/Download/.offlineyoutube',
    this.autoDownloadOnPaste = true,
    this.playlistReverseOrder = true,
    this.savedPlaylists = const [],
  });

  AppSettings copyWith({
    int? maxStorageLimitGB,
    int? maxVideoDurationHours,
    NetworkRestrictionMode? networkMode,
    String? allowedWifiSsid,
    String? customDownloadPath,
    bool? autoDownloadOnPaste,
    bool? playlistReverseOrder,
    List<String>? savedPlaylists,
  }) {
    return AppSettings(
      maxStorageLimitGB: maxStorageLimitGB ?? this.maxStorageLimitGB,
      maxVideoDurationHours: maxVideoDurationHours ?? this.maxVideoDurationHours,
      networkMode: networkMode ?? this.networkMode,
      allowedWifiSsid: allowedWifiSsid ?? this.allowedWifiSsid,
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
        'allowedWifiSsid': allowedWifiSsid,
        'customDownloadPath': customDownloadPath,
        'autoDownloadOnPaste': autoDownloadOnPaste,
        'playlistReverseOrder': playlistReverseOrder,
        'savedPlaylists': savedPlaylists,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        maxStorageLimitGB: json['maxStorageLimitGB'] as int? ?? 20,
        maxVideoDurationHours: json['maxVideoDurationHours'] as int? ?? 6,
        networkMode: NetworkRestrictionMode.values[
            (json['networkMode'] as int? ?? 2).clamp(0, NetworkRestrictionMode.values.length - 1)],
        allowedWifiSsid: json['allowedWifiSsid'] as String? ?? '',
        customDownloadPath: json['customDownloadPath'] as String? ??
            '/storage/emulated/0/Download/.offlineyoutube',
        autoDownloadOnPaste: json['autoDownloadOnPaste'] as bool? ?? true,
        playlistReverseOrder: json['playlistReverseOrder'] as bool? ?? true,
        savedPlaylists: (json['savedPlaylists'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
