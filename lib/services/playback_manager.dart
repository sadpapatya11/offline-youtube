import 'package:shared_preferences/shared_preferences.dart';

class PlaybackManager {
  static final PlaybackManager instance = PlaybackManager._internal();
  PlaybackManager._internal();

  static const String _keyPrefix = 'playback_pos_';

  /// Videonun oynatıcıdaki son pozisyonunu milisaniye cinsinden kaydeder
  Future<void> savePosition(String videoId, int positionMs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (positionMs <= 1000) {
        await prefs.remove('$_keyPrefix$videoId');
      } else {
        await prefs.setInt('$_keyPrefix$videoId', positionMs);
      }
    } catch (_) {}
  }

  /// Videonun kayıtlı son pozisyonunu milisaniye olarak döndürür
  Future<int> getPosition(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_keyPrefix$videoId') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Video silindiğinde pozisyon bilgisini temizler
  Future<void> clearPosition(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$videoId');
    } catch (_) {}
  }

  /// Tüm kayıtlı video pozisyonlarını temizler
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
