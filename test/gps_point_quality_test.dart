import 'package:aims_flow_scanner/services/gps_point_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 0, 0, 0);

  test('accepts a normal accurate urban GPS fix', () {
    expect(
      GpsPointQuality.acceptable(
        latitude: 47.6875,
        longitude: 17.6504,
        accuracy: 8,
        speedMps: 12,
        capturedAt: now,
        now: now,
      ),
      isTrue,
    );
  });

  test('rejects low accuracy GPS fixes', () {
    expect(
      GpsPointQuality.acceptable(
        latitude: 47.6875,
        longitude: 17.6504,
        accuracy: 180,
        speedMps: 0,
        capturedAt: now,
        now: now,
      ),
      isFalse,
    );
  });

  test('rejects an impossible teleport between consecutive fixes', () {
    final result = GpsPointQuality.assess(
      latitude: 47.4979,
      longitude: 19.0402,
      accuracy: 10,
      speedMps: 20,
      capturedAt: now.add(const Duration(seconds: 10)),
      now: now.add(const Duration(seconds: 10)),
      previousLatitude: 47.6875,
      previousLongitude: 17.6504,
      previousAccuracy: 10,
      previousSpeedMps: 20,
      previousCapturedAt: now,
    );
    expect(result.accepted, isFalse);
    expect(result.reason, 'impossible_jump');
  });

  test('accepts plausible motorway movement', () {
    final result = GpsPointQuality.assess(
      latitude: 47.6899,
      longitude: 17.6504,
      accuracy: 9,
      speedMps: 27,
      capturedAt: now.add(const Duration(seconds: 10)),
      now: now.add(const Duration(seconds: 10)),
      previousLatitude: 47.6875,
      previousLongitude: 17.6504,
      previousAccuracy: 9,
      previousSpeedMps: 27,
      previousCapturedAt: now,
    );
    expect(result.accepted, isTrue);
    expect(result.score, greaterThanOrEqualTo(80));
  });

  test('recognizes stationary GPS jitter', () {
    final result = GpsPointQuality.assess(
      latitude: 47.68753,
      longitude: 17.65042,
      accuracy: 8,
      speedMps: .2,
      capturedAt: now.add(const Duration(seconds: 8)),
      now: now.add(const Duration(seconds: 8)),
      previousLatitude: 47.6875,
      previousLongitude: 17.6504,
      previousAccuracy: 7,
      previousSpeedMps: .1,
      previousCapturedAt: now,
    );
    expect(result.accepted, isTrue);
    expect(result.stationaryJitter, isTrue);
  });

  test('stabilization damps a weak stationary jump', () {
    final stable = GpsPointQuality.stabilize(
      latitude: 47.6878,
      longitude: 17.6508,
      accuracy: 55,
      speedMps: .2,
      stationaryJitter: true,
      previousLatitude: 47.6875,
      previousLongitude: 17.6504,
    );
    expect(stable.latitude, lessThan(47.6876));
    expect(stable.longitude, lessThan(17.6505));
  });

  test('stabilization reacts quickly while moving', () {
    final stable = GpsPointQuality.stabilize(
      latitude: 47.6880,
      longitude: 17.6510,
      accuracy: 8,
      speedMps: 25,
      stationaryJitter: false,
      previousLatitude: 47.6875,
      previousLongitude: 17.6504,
    );
    expect(stable.latitude, greaterThan(47.68785));
    expect(stable.longitude, greaterThan(17.65085));
  });

  test('marks older but still accepted fixes as stale quality', () {
    final result = GpsPointQuality.assess(
      latitude: 47.6875,
      longitude: 17.6504,
      accuracy: 12,
      speedMps: 0,
      capturedAt: now.subtract(const Duration(seconds: 100)),
      now: now,
    );
    expect(result.accepted, isTrue);
    expect(result.quality, GpsFixQuality.stale);
  });
}
