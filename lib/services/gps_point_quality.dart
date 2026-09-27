import 'dart:math';

enum GpsFixQuality {
  excellent,
  good,
  degraded,
  stale,
  rejected,
}

class GpsAssessment {
  const GpsAssessment({
    required this.accepted,
    required this.quality,
    required this.score,
    required this.reason,
    required this.stationaryJitter,
    required this.age,
    required this.impliedSpeedKmh,
    required this.distanceFromPreviousM,
  });

  final bool accepted;
  final GpsFixQuality quality;
  final int score;
  final String reason;
  final bool stationaryJitter;
  final Duration age;
  final double? impliedSpeedKmh;
  final double? distanceFromPreviousM;

  bool get fresh => accepted && quality != GpsFixQuality.stale;
}

class GpsPointQuality {
  const GpsPointQuality._();

  static const double maxAccuracyM = 120;
  static const double maxSensorSpeedMps = 65;
  static const double maxImpliedSpeedKmh = 190;
  static const Duration maxFreshAge = Duration(minutes: 3);

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

  static GpsAssessment assess({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speedMps,
    required DateTime capturedAt,
    DateTime? now,
    double? previousLatitude,
    double? previousLongitude,
    double? previousAccuracy,
    double? previousSpeedMps,
    DateTime? previousCapturedAt,
  }) {
    final currentNow = now ?? DateTime.now();
    var age = currentNow.difference(capturedAt);
    if (age.isNegative) age = Duration.zero;

    GpsAssessment reject(String reason) => GpsAssessment(
          accepted: false,
          quality: GpsFixQuality.rejected,
          score: 0,
          reason: reason,
          stationaryJitter: false,
          age: age,
          impliedSpeedKmh: null,
          distanceFromPreviousM: null,
        );

    if (!validCoordinates(latitude, longitude)) {
      return reject('invalid_coordinates');
    }
    if (!accuracy.isFinite || accuracy <= 0 || accuracy > maxAccuracyM) {
      return reject('low_accuracy');
    }
    if (!speedMps.isFinite || speedMps < 0 || speedMps > maxSensorSpeedMps) {
      return reject('invalid_sensor_speed');
    }
    if (capturedAt.isAfter(currentNow.add(const Duration(minutes: 2)))) {
      return reject('future_timestamp');
    }
    if (currentNow.difference(capturedAt) > maxFreshAge) {
      return reject('stale_timestamp');
    }

    double? meters;
    double? impliedKmh;
    if (previousLatitude != null &&
        previousLongitude != null &&
        previousCapturedAt != null &&
        validCoordinates(previousLatitude, previousLongitude) &&
        capturedAt.isAfter(previousCapturedAt)) {
      final seconds =
          capturedAt.difference(previousCapturedAt).inMilliseconds / 1000;
      if (seconds > 0) {
        meters = distanceMeters(
          previousLatitude,
          previousLongitude,
          latitude,
          longitude,
        );
        impliedKmh = meters / seconds * 3.6;
        final accuracyPad = max(
          10.0,
          max(accuracy, previousAccuracy ?? accuracy),
        );
        if (impliedKmh > maxImpliedSpeedKmh &&
            meters > max(250.0, accuracyPad * 4)) {
          return reject('impossible_jump');
        }
      }
    }

    final jitter = previousLatitude != null &&
        previousLongitude != null &&
        previousAccuracy != null &&
        previousSpeedMps != null &&
        isStationaryJitter(
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          speedMps: speedMps,
          previousLatitude: previousLatitude,
          previousLongitude: previousLongitude,
          previousAccuracy: previousAccuracy,
          previousSpeedMps: previousSpeedMps,
        );

    var score = 100;
    if (accuracy > 10) score -= 8;
    if (accuracy > 20) score -= 10;
    if (accuracy > 35) score -= 12;
    if (accuracy > 60) score -= 18;
    if (accuracy > 90) score -= 20;

    final ageSeconds = age.inSeconds;
    if (ageSeconds > 15) score -= 6;
    if (ageSeconds > 45) score -= 10;
    if (ageSeconds > 90) score -= 16;

    if (impliedKmh != null &&
        speedMps > 1 &&
        (impliedKmh - speedMps * 3.6).abs() > 90) {
      score -= 12;
    }
    if (jitter) score -= 4;
    score = score.clamp(1, 100);

    final quality = age > const Duration(seconds: 90)
        ? GpsFixQuality.stale
        : score >= 88
            ? GpsFixQuality.excellent
            : score >= 70
                ? GpsFixQuality.good
                : GpsFixQuality.degraded;

    return GpsAssessment(
      accepted: true,
      quality: quality,
      score: score,
      reason: jitter ? 'stationary_jitter' : 'ok',
      stationaryJitter: jitter,
      age: age,
      impliedSpeedKmh: impliedKmh,
      distanceFromPreviousM: meters,
    );
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
    return assess(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speedMps: speedMps,
      capturedAt: capturedAt,
      now: now,
      previousLatitude: previousLatitude,
      previousLongitude: previousLongitude,
      previousAccuracy: previousAccuracy,
      previousCapturedAt: previousCapturedAt,
    ).accepted;
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

  /// Adaptive smoothing for the coordinate used by the backend/map logic.
  /// It intentionally reacts faster while driving and damps weak stationary
  /// fixes heavily, which prevents a parked vehicle from "walking" on the map.
  static double smoothingFactor({
    required double accuracy,
    required double speedMps,
    required bool stationaryJitter,
  }) {
    if (stationaryJitter) return 0.05;
    if (speedMps >= 12) return accuracy <= 25 ? 0.82 : 0.62;
    if (speedMps >= 3) return accuracy <= 25 ? 0.68 : 0.48;
    if (accuracy <= 12) return 0.38;
    if (accuracy <= 35) return 0.25;
    return 0.14;
  }

  static ({double latitude, double longitude}) stabilize({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speedMps,
    required bool stationaryJitter,
    double? previousLatitude,
    double? previousLongitude,
  }) {
    if (previousLatitude == null ||
        previousLongitude == null ||
        !validCoordinates(previousLatitude, previousLongitude)) {
      return (latitude: latitude, longitude: longitude);
    }
    final factor = smoothingFactor(
      accuracy: accuracy,
      speedMps: speedMps,
      stationaryJitter: stationaryJitter,
    );
    return (
      latitude: previousLatitude + (latitude - previousLatitude) * factor,
      longitude: previousLongitude + (longitude - previousLongitude) * factor,
    );
  }
}
