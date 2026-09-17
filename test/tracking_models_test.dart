import 'package:aims_flow_scanner/models/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackingSession', () {
    test('round-trips active offline GPS queue without losing state', () {
      final startedAt = DateTime.utc(2026, 9, 17, 5, 0);
      final pointAt = DateTime.utc(2026, 9, 17, 5, 1);
      final original = TrackingSession(
        id: 'trip_brutal_1',
        plate: 'SWF-373',
        reference: 'CMR-123',
        startedAt: startedAt,
        active: true,
        points: [
          TrackingPoint(
            id: 'gps_1',
            capturedAt: pointAt,
            latitude: 47.6875,
            longitude: 17.6504,
            accuracy: 4.5,
            speedMps: 13.0,
            heading: 91,
            altitude: 112,
            isMocked: false,
          ),
        ],
      );

      final restored = TrackingSession.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.plate, 'SWF-373');
      expect(restored.reference, 'CMR-123');
      expect(restored.active, isTrue);
      expect(restored.queuedPointCount, 1);
      expect(restored.latestPoint?.latitude, 47.6875);
      expect(restored.latestPoint?.longitude, 17.6504);
      expect(restored.latestPoint?.synced, isFalse);
    });

    test('counts only unsynced points and preserves stop metadata', () {
      final now = DateTime.utc(2026, 9, 17, 5, 0);
      TrackingPoint point(String id, bool synced) => TrackingPoint(
            id: id,
            capturedAt: now,
            latitude: 47,
            longitude: 17,
            accuracy: 5,
            speedMps: 0,
            heading: 0,
            altitude: 0,
            synced: synced,
          );

      final session = TrackingSession(
        id: 'trip_brutal_2',
        plate: 'SIP-115',
        reference: '',
        startedAt: now,
        active: false,
        stoppedAt: now.add(const Duration(minutes: 5)),
        serverStarted: true,
        serverStopped: false,
        lastSyncError: 'offline',
        points: [point('1', true), point('2', false), point('3', false)],
      );

      final restored = TrackingSession.fromJson(session.toJson());
      expect(restored.active, isFalse);
      expect(restored.stoppedAt, isNotNull);
      expect(restored.serverStarted, isTrue);
      expect(restored.serverStopped, isFalse);
      expect(restored.lastSyncError, 'offline');
      expect(restored.queuedPointCount, 2);
    });

    test('negative GPS speed is exposed as zero km/h', () {
      final point = TrackingPoint(
        id: 'gps_negative_speed',
        capturedAt: DateTime.utc(2026, 9, 17),
        latitude: 47,
        longitude: 17,
        accuracy: 5,
        speedMps: -1,
        heading: 0,
        altitude: 0,
      );

      expect(point.speedKmh, 0);
    });
  });
}
