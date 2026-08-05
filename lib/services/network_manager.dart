import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/app_settings.dart';

class NetworkManager {
  static final NetworkManager instance = NetworkManager._internal();
  NetworkManager._internal();

  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getCurrentWifiSsid() async {
    try {
      final ssid = await _networkInfo.getWifiName();
      if (ssid != null) {
        // Strip extra quotes if present (e.g. "MySSID" -> MySSID)
        return ssid.replaceAll('"', '').trim();
      }
    } catch (e) {
      // Ignored
    }
    return null;
  }

  Future<List<ConnectivityResult>> getCurrentConnectivity() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      return [ConnectivityResult.none];
    }
  }

  Future<Map<String, dynamic>> checkNetworkPermissionAndStatus(AppSettings settings) async {
    // If all networks (mobil veri + wifi) is selected, allow immediately
    if (settings.networkMode == NetworkRestrictionMode.allNetworks) {
      return {'allowed': true, 'reason': ''};
    }

    final connectivity = await getCurrentConnectivity();
    final isWifi = connectivity.contains(ConnectivityResult.wifi);
    final isMobile = connectivity.contains(ConnectivityResult.mobile);
    final isNone = connectivity.contains(ConnectivityResult.none) && !isWifi && !isMobile;

    if (isNone) {
      return {
        'allowed': false,
        'reason': 'İnternet bağlantısı bulunamadı.',
      };
    }

    switch (settings.networkMode) {
      case NetworkRestrictionMode.selectedWifi:
        if (!isWifi) {
          return {
            'allowed': false,
            'reason': 'İndirme yalnızca seçili Wi-Fi ağında yapılabilir.',
          };
        }
        final currentSsid = await getCurrentWifiSsid();
        if (settings.allowedWifiSsid.isNotEmpty &&
            currentSsid != null &&
            currentSsid != settings.allowedWifiSsid) {
          return {
            'allowed': false,
            'reason':
                'Geçerli Wi-Fi ($currentSsid), izin verilen ağ (${settings.allowedWifiSsid}) ile eşleşmiyor.',
          };
        }
        return {'allowed': true, 'reason': ''};

      case NetworkRestrictionMode.anyWifi:
        if (!isWifi) {
          return {
            'allowed': false,
            'reason':
                'Ayarlarınızda "Sadece Wi-Fi ile İndir" aktif. Mobil veriyle indirmek için Ayarlar\'dan Wi-Fi kısıtlamasını kapatın.',
          };
        }
        return {'allowed': true, 'reason': ''};

      case NetworkRestrictionMode.allNetworks:
        return {'allowed': true, 'reason': ''};
    }
  }
}
