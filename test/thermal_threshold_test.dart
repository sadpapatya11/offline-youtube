import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/services/thermal_policy.dart';

void main() {
  group('Thermal Management & Resource Policy Tests', () {
    test('Thermal rate limits adjust correctly based on ThermalTier', () {
      expect(ThermalPolicy.getDownloadRateLimit(ThermalTier.nominal), equals('3.5M'));
      expect(ThermalPolicy.getDownloadRateLimit(ThermalTier.fair), equals('2.0M'));
      expect(ThermalPolicy.getDownloadRateLimit(ThermalTier.serious), equals('1.0M'));
      expect(ThermalPolicy.getDownloadRateLimit(ThermalTier.critical), equals('500K'));
    });

    test('FFmpeg remuxing thread limits dynamically restrict on warm device or screen off', () {
      // Normal state: 2 threads
      expect(
        ThermalPolicy.getRemuxingThreads(isScreenOff: false, isDeviceWarm: false),
        equals(2),
      );

      // Warm state: throttled to 1 thread
      expect(
        ThermalPolicy.getRemuxingThreads(isScreenOff: false, isDeviceWarm: true),
        equals(1),
      );

      // Screen off state: throttled to 1 thread to conserve power
      expect(
        ThermalPolicy.getRemuxingThreads(isScreenOff: true, isDeviceWarm: false),
        equals(1),
      );

      // Both warm and screen off: throttled to 1 thread
      expect(
        ThermalPolicy.getRemuxingThreads(isScreenOff: true, isDeviceWarm: true),
        equals(1),
      );
    });

    test('Speed, Size, and ETA extraction from standard yt-dlp console logs', () {
      const line1 =
          '[download]   54.47MiB of ~ 120.50MiB at    3.25MiB/s ETA 00:20';
      const line2 =
          '[download]  100% of 45.20MiB in 00:12 at 3.75MiB/s';

      expect(ThermalPolicy.extractSpeed(line1), equals('3.25MiB/s'));
      expect(ThermalPolicy.extractTotalSize(line1), equals('120.50MiB'));
      expect(ThermalPolicy.extractDownloadedSize(line1), equals('54.47MiB'));
      expect(ThermalPolicy.extractEta(line1), equals('00:20'));

      expect(ThermalPolicy.extractSpeed(line2), equals('3.75MiB/s'));
      expect(ThermalPolicy.extractTotalSize(line2), equals('45.20MiB'));
    });
  });
}
