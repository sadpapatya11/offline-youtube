enum ThermalTier {
  nominal,
  fair,
  serious,
  critical,
}

class ThermalPolicy {
  const ThermalPolicy();

  static const String rateNominal = '3.5M';
  static const String rateFair = '2.0M';
  static const String rateSerious = '1.0M';
  static const String rateCritical = '500K';

  static final RegExp _speedPattern =
      RegExp(r'at\s+([0-9.]+\s*[kKMmGg]?[iI]?[bB]/s)');
  static final RegExp _totalSizePattern =
      RegExp(r'of\s+~?\s*([0-9.]+\s*[kKMmGg]?[iI]?[bB])');
  static final RegExp _downloadedSizePattern =
      RegExp(r'\[download\]\s+([0-9.]+\s*[kKMmGg]?[iI]?[bB])\s+of');
  static final RegExp _etaPattern = RegExp(r'ETA\s+([0-9:]+)');

  /// Returns the maximum download rate limit based on device thermal tier
  static String getDownloadRateLimit(ThermalTier tier) {
    switch (tier) {
      case ThermalTier.nominal:
        return rateNominal;
      case ThermalTier.fair:
        return rateFair;
      case ThermalTier.serious:
        return rateSerious;
      case ThermalTier.critical:
        return rateCritical;
    }
  }

  /// Calculates max thread count allowed for FFmpeg remuxing / encoding
  static int getRemuxingThreads({
    required bool isScreenOff,
    required bool isDeviceWarm,
  }) {
    if (isScreenOff || isDeviceWarm) {
      return 1;
    }
    return 2;
  }

  /// Extracts download speed from yt-dlp console line
  static String? extractSpeed(String logLine) {
    final match = _speedPattern.firstMatch(logLine);
    return match?.group(1)?.trim();
  }

  /// Extracts total file size estimate from yt-dlp console line
  static String? extractTotalSize(String logLine) {
    final match = _totalSizePattern.firstMatch(logLine);
    return match?.group(1)?.trim();
  }

  /// Extracts downloaded size from yt-dlp console line
  static String? extractDownloadedSize(String logLine) {
    final match = _downloadedSizePattern.firstMatch(logLine);
    return match?.group(1)?.trim();
  }

  /// Extracts ETA string from yt-dlp console line
  static String? extractEta(String logLine) {
    final match = _etaPattern.firstMatch(logLine);
    return match?.group(1)?.trim();
  }
}
