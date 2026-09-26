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
    expect(
      GpsPointQuality.acceptable(
        latitude: 47.4979,
        longitude: 19.0402,
        accuracy: 10,
        speedMps: 20,
        capturedAt: now.add(const Duration(seconds: 10)),
        now: now.add(const Duration(seconds: 10)),
        previousLatitude: 47.6875,
        previousLongitude: 17.6504,
        previousAccuracy: 10,
        previousCapturedAt: now,
      ),
      isFalse,
    );
  });

  test('accepts plausible motorway movement', () {
    expect(
      GpsPointQuality.acceptable(
        latitude: 47.6899,
        longitude: 17.6504,
        accuracy: 9,
        speedMps: 27,
        capturedAt: now.add(const Duration(seconds: 10)),
        now: now.add(const Duration(seconds: 10)),
        previousLatitude: 47.6875,
        previousLongitude: 17.6504,
        previousAccuracy: 9,
        previousCapturedAt: now,
      ),
      isTrue,
    );
  });

  test('recognizes stationary GPS jitter', () {
    expect(
      GpsPointQuality.isStationaryJitter(
        latitude: 47.68753,
        longitude: 17.65042,
        accuracy: 8,
        speedMps: .2,
        previousLatitude: 47.6875,
        previousLongitude: 17.6504,
        previousAccuracy: 7,
        previousSpeedMps: .1,
      ),
      isTrue,
    );
  });
}
