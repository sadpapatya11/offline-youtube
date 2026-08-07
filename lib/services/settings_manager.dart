import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsManager {
  static final SettingsManager instance = SettingsManager._internal();
  SettingsManager._internal();

  static const String _keySettings = 'offlineyoutube_app_settings';

  Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keySettings);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return AppSettings.fromJson(map);
      }
    } catch (e) {
      // Ignored
    }
    return const AppSettings();
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(settings.toJson());
      await prefs.setString(_keySettings, jsonStr);
    } catch (e) {
      // Ignored
    }
  }

  static const String _keyWifiDisabledTimestamp = 'offlineyoutube_wifi_disabled_time';

  Future<void> saveWifiDisabledTimestamp(int timestampMs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyWifiDisabledTimestamp, timestampMs);
    } catch (_) {}
  }

  Future<int?> getWifiDisabledTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyWifiDisabledTimestamp);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearWifiDisabledTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyWifiDisabledTimestamp);
    } catch (_) {}
  }
}
