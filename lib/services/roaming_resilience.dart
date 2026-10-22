import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  /// An offline point keeps the vehicle it belonged to when captured.
  static bool queueBelongsToVehicle(
    Map<String, dynamic> point,
    String activePlate,
  ) {
    String normalize(Object? value) => (value?.toString() ?? '')
        .trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final active = normalize(activePlate);
    final plate = normalize(point['plate']);
    final label = normalize(point['vehicleLabel']);
    if (active.isEmpty || (plate.isEmpty && label.isEmpty)) return false;
    return (plate.isEmpty || plate == active) &&
        (label.isEmpty || label == active);
  }

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
    String scope = '',
  }) {
    final raw =
        '${deviceId.trim()}|${timestamp.toUtc().microsecondsSinceEpoch}|'
        '${latitude.toStringAsFixed(6)}|${longitude.toStringAsFixed(6)}|$scope';
    return 'pt2_${sha256.convert(utf8.encode(raw))}';
  }
}

