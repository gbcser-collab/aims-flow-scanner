import 'dart:math';

class GpsPointQuality {
  const GpsPointQuality._();

  static const double maxAccuracyM = 120;
  static const double maxSensorSpeedMps = 65;
  static const double maxImpliedSpeedKmh = 190;

  static bool validCoordinates(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  static double distanceMeters(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const radius = 6371008.8;
    final p1 = latitude1 * pi / 180;
    final p2 = latitude2 * pi / 180;
    final dp = (latitude2 - latitude1) * pi / 180;
    final dl = (longitude2 - longitude1) * pi / 180;
    final a = sin(dp / 2) * sin(dp / 2) +
        cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
    return 2 * radius * asin(min(1, sqrt(a)));
  }

  static bool acceptable({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speedMps,
    required DateTime capturedAt,
    DateTime? now,
    double? previousLatitude,
    double? previousLongitude,
    double? previousAccuracy,
    DateTime? previousCapturedAt,
  }) {
    if (!validCoordinates(latitude, longitude)) return false;
    if (!accuracy.isFinite || accuracy <= 0 || accuracy > maxAccuracyM) {
      return false;
    }
    if (!speedMps.isFinite || speedMps < 0 || speedMps > maxSensorSpeedMps) {
      return false;
    }

    final currentNow = now ?? DateTime.now();
    if (capturedAt.isAfter(currentNow.add(const Duration(minutes: 2)))) {
      return false;
    }
    if (currentNow.difference(capturedAt) > const Duration(minutes: 3)) {
      return false;
    }

    if (previousLatitude != null &&
        previousLongitude != null &&
        previousCapturedAt != null &&
        validCoordinates(previousLatitude, previousLongitude) &&
        capturedAt.isAfter(previousCapturedAt)) {
      final seconds =
          capturedAt.difference(previousCapturedAt).inMilliseconds / 1000;
      if (seconds > 0) {
        final meters = distanceMeters(
          previousLatitude,
          previousLongitude,
          latitude,
          longitude,
        );
        final impliedKmh = meters / seconds * 3.6;
        final accuracyPad = max(
          10.0,
          max(accuracy, previousAccuracy ?? accuracy),
        );
        if (impliedKmh > maxImpliedSpeedKmh &&
            meters > max(250.0, accuracyPad * 4)) {
          return false;
        }
      }
    }

    return true;
  }

  static bool isStationaryJitter({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speedMps,
    required double previousLatitude,
    required double previousLongitude,
    required double previousAccuracy,
    required double previousSpeedMps,
  }) {
    if (speedMps >= 1.5 || previousSpeedMps >= 1.5) return false;
    final meters = distanceMeters(
      previousLatitude,
      previousLongitude,
      latitude,
      longitude,
    );
    final tolerance = max(8.0, max(accuracy, previousAccuracy) * .8);
    return meters <= tolerance;
  }
}
