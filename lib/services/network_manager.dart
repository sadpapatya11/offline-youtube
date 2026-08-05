import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/app_settings.dart';

class NetworkManager {
  static final NetworkManager instance = NetworkManager._internal();
  NetworkManager._internal();

  final Connectivity _connectivity = Connectivity();

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  Future<List<ConnectivityResult>> getCurrentConnectivity() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      return [ConnectivityResult.none];
    }
  }

  Future<bool> isWifiConnected() async {
    final results = await getCurrentConnectivity();
    return results.contains(ConnectivityResult.wifi);
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

    if (settings.networkMode == NetworkRestrictionMode.anyWifi) {
      if (!isWifi) {
        return {
          'allowed': false,
          'reason':
              'Ayarlarınızda "Sadece Wi-Fi ile İndir" aktif. Mobil veriyle indirmek için Ayarlar\'dan Wi-Fi kısıtlamasını kapatın.',
        };
      }
      return {'allowed': true, 'reason': ''};
    }

    return {'allowed': true, 'reason': ''};
  }
}
