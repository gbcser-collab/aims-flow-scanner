import 'dart:math';

class RoamingResilience {
  const RoamingResilience._();

  static bool validCoordinates(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  static double finiteOrZero(double value) => value.isFinite ? value : 0;

  /// Fast, bounded recovery schedule for roaming and temporary data loss.
  ///
  /// The first retries happen after 1, 2, 4 and 8 seconds. A prolonged outage
  /// never pushes the next attempt beyond 30 seconds, so the local GPS queue
  /// starts draining quickly after the phone regains a usable data path.
  static Duration retryDelay(int failureCount) {
    if (failureCount <= 0) return Duration.zero;
    const seconds = <int>[1, 2, 4, 8, 12, 20, 30];
    final index = min(failureCount - 1, seconds.length - 1);
    return Duration(seconds: seconds[index]);
  }

  static bool isFresh(
    DateTime capturedAt,
    DateTime now, {
    Duration maxAge = const Duration(minutes: 15),
  }) {
    final age = now.toUtc().difference(capturedAt.toUtc());
    return age >= Duration.zero && age <= maxAge;
  }

  static bool isDelayed(
    DateTime capturedAt,
    DateTime now, {
    Duration threshold = const Duration(minutes: 2),
  }) {
    return now.toUtc().difference(capturedAt.toUtc()) > threshold;
  }

  static String pointId({
    required String deviceId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) {
    final raw =
        '${deviceId.trim()}|${timestamp.toUtc().microsecondsSinceEpoch}|'
        '${latitude.toStringAsFixed(6)}|${longitude.toStringAsFixed(6)}';
    var hash = 0x811c9dc5;
    for (final code in raw.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'pt_${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
