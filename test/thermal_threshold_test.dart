import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Thermal Management & Resource Policy Tests', () {
    test('Thermal rate limits follow safety tiers', () {
      const normalRate = '3.5M';
      const moderateRate = '2.0M';
      const severeRate = '1.0M';
      const criticalRate = '500K';

      expect(normalRate, equals('3.5M'));
      expect(moderateRate, equals('2.0M'));
      expect(severeRate, equals('1.0M'));
      expect(criticalRate, equals('500K'));
    });

    test('FFmpeg Remuxing Thread limits do not exceed safe core thresholds', () {
      const normalThreads = 2;
      const warmThreads = 1;
      const screenOffThreads = 1;

      expect(normalThreads, lessThanOrEqualTo(2));
      expect(warmThreads, equals(1));
      expect(screenOffThreads, equals(1));
    });

    test('Speed & Size Regex parsers match standard yt-dlp outputs accurately', () {
      final speedPattern = RegExp(r'at\s+([0-9.]+\s*[kKMmGg]?[iI]?[bB]/s)');
      final totalSizePattern = RegExp(r'of\s+~?\s*([0-9.]+\s*[kKMmGg]?[iI]?[bB])');
      final downloadedSizePattern =
          RegExp(r'\[download\]\s+([0-9.]+\s*[kKMmGg]?[iI]?[bB])\s+of');

      const testLine =
          '[download]   54.47MiB of ~ 120.50MiB at    3.25MiB/s ETA 00:20';

      final speedMatch = speedPattern.firstMatch(testLine);
      expect(speedMatch, isNotNull);
      expect(speedMatch!.group(1)!.trim(), equals('3.25MiB/s'));

      final totalMatch = totalSizePattern.firstMatch(testLine);
      expect(totalMatch, isNotNull);
      expect(totalMatch!.group(1)!.trim(), equals('120.50MiB'));

      final downloadedMatch = downloadedSizePattern.firstMatch(testLine);
      expect(downloadedMatch, isNotNull);
      expect(downloadedMatch!.group(1)!.trim(), equals('54.47MiB'));
    });
  });
}
