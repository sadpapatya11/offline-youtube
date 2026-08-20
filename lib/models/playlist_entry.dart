/// Oynatma listesi / kanal bağlantısından çözümlenmiş tek bir video girdisi.
///
/// Kuyruğa eklenmeden ÖNCE kullanıcıya gösterilen ara temsildir: seçim ekranı
/// bu listeyi gösterir, kullanıcı hangilerini indireceğini işaretler.
class PlaylistEntry {
  final String url;
  final String title;

  /// Saniye cinsinden süre. `0` = **bilinmiyor** (`--flat-playlist` süreyi
  /// çoğu zaman döndürmez). Sıfır ile "bilinmiyor" karıştırılmamalıdır.
  final int durationSeconds;

  final String? thumbnail;
  final String? uploader;
  final String? uploadDate;

  /// Video zaten kuyrukta ya da kütüphanede mi. Seçim ekranı bunu işaretler ve
  /// varsayılan seçime dahil etmez; kullanıcı isterse yine seçebilir.
  final bool alreadyPresent;

  const PlaylistEntry({
    required this.url,
    required this.title,
    this.durationSeconds = 0,
    this.thumbnail,
    this.uploader,
    this.uploadDate,
    this.alreadyPresent = false,
  });

  bool get hasDuration => durationSeconds > 0;

  String get formattedDuration =>
      hasDuration ? formatDuration(durationSeconds) : '--:--';

  /// Saniyeyi `d:ss` / `s:dd:ss` biçimine çevirir.
  static String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Bir bağlantının çözümlenme sonucu.
class PlaylistFetchResult {
  final List<PlaylistEntry> entries;

  /// Bağlantının içerdiği toplam video sayısı (üst sınır uygulanmadan önce).
  final int totalCount;

  /// Kaynak bağlantı — kuyruğa eklenen görevlere `sourcePlaylistUrl` olarak
  /// yazılır, senkron temizliği bu bilgiye dayanır.
  final String sourceUrl;

  const PlaylistFetchResult({
    required this.entries,
    required this.totalCount,
    required this.sourceUrl,
  });

  /// Üst sınır nedeniyle listelenemeyen video sayısı. Sessiz kırpma yasak:
  /// bu sayı kullanıcıya gösterilir.
  int get truncatedCount => totalCount - entries.length;

  bool get isTruncated => truncatedCount > 0;

  /// Henüz kuyrukta/kütüphanede olmayan girdiler — varsayılan seçim adayları.
  List<PlaylistEntry> get selectableEntries =>
      entries.where((e) => !e.alreadyPresent).toList();

  int get alreadyPresentCount => entries.where((e) => e.alreadyPresent).length;
}
