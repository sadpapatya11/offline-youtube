import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsManager {
  static final SettingsManager instance = SettingsManager._internal();
  SettingsManager._internal();

  static const String _keySettings = 'offlineyoutube_app_settings';

  /// Çözümlenemeyen ayar JSON'unun karantinaya alındığı anahtar.
  static const String _keyCorruptBackup =
      'offlineyoutube_app_settings_corrupt';

  /// Son [loadSettings] çağrısı ayarları OKUYAMADIYSA true olur.
  ///
  /// Neden gerekli: okuma patlayınca varsayılanlara dönülüyor ve kullanıcı herhangi
  /// bir ayarı değiştirdiği anda [saveSettings] bu varsayılanları diske yazıp gerçek
  /// ayarları (özel indirme yolu ve KAYITLI OYNATMA LİSTESİ KÜTÜPHANESİ dahil)
  /// kalıcı olarak siliyordu. Bayrak arayüze taşınmadan üzerine yazma yapılmamalı.
  bool get lastLoadFailed => _lastLoadFailed;
  bool _lastLoadFailed = false;

  Future<AppSettings> loadSettings() async {
    _lastLoadFailed = false;

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e, s) {
      debugPrint('ERROR in loadSettings (prefs): $e\n$s');
      _lastLoadFailed = true;
      return const AppSettings();
    }

    final String? jsonStr;
    try {
      jsonStr = prefs.getString(_keySettings);
    } catch (e, s) {
      debugPrint('ERROR in loadSettings (okuma): $e\n$s');
      _lastLoadFailed = true;
      return const AppSettings();
    }

    // Gerçekten ilk açılış: kayıp yok, varsayılanlar doğru cevap.
    if (jsonStr == null || jsonStr.isEmpty) return const AppSettings();

    try {
      final Map<String, dynamic> map =
          jsonDecode(jsonStr) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (e, s) {
      debugPrint('ERROR in loadSettings (çözümleme): $e\n$s');
      _lastLoadFailed = true;
      // Karantina: bozuk ham JSON üzerine yazılmadan önce ayrı bir anahtarda
      // saklanır, yoksa kullanıcının oynatma listesi kütüphanesi geri dönülmez
      // biçimde gider. Var olan yedek EZİLMEZ (ilk bozulma en değerlisidir).
      try {
        if (prefs.getString(_keyCorruptBackup) == null) {
          await prefs.setString(_keyCorruptBackup, jsonStr);
        }
      } catch (e2, s2) {
        debugPrint('ERROR in loadSettings (karantina): $e2\n$s2');
      }
      return const AppSettings();
    }
  }

  /// Ayarları diske yazar ve BAŞARIYI DÖNDÜRÜR.
  ///
  /// bool dönmesinin nedeni: yazma sessizce yutulduğunda arayüz değişikliği
  /// uygulanmış gösteriyordu; uygulama yeniden açılınca ayar eski hâline dönüyor,
  /// kullanıcı nedenini hiç öğrenemiyordu.
  Future<bool> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(settings.toJson());
      return await prefs.setString(_keySettings, jsonStr);
    } catch (e, s) {
      debugPrint('ERROR in saveSettings: $e\n$s');
      return false;
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
