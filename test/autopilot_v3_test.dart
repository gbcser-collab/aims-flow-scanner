import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/driver_api_service.dart';

void main() {
  test('Autopilot R97 parses refined decision feed', () {
    final state = DriverAutopilotStatus.fromJson({
      'version': 'R97',
      'mode': 'enroute',
      'actionCode': 'navigate_next',
      'secondaryActionCode': 'signal_delay',
      'severity': 'high',
      'riskScore': 72,
      'confidence': 88,
      'reasonCodes': ['late', 'gps_stale'],
      'refreshAfterSeconds': 10,
      'reference': 'AIMS-97',
      'seen': true,
      'accepted': true,
      'totalStops': 4,
      'completedStops': 2,
      'progressPct': 50,
      'gpsFresh': false,
      'gpsAccuracyMeters': 18.5,
      'currentSpeedKmh': 74.2,
      'documentsRequired': false,
      'sequenceAnomaly': false,
      'isLate': true,
      'dataQuality': {
        'gps': 'stale',
        'nextStop': 'complete',
        'schedule': 'known',
      },
      'alertFingerprint': 'abc123',
      'jobId': 96,
      'gpsAgeMinutes': 24,
      'stationaryMinutes': 4,
      'stopDwellMinutes': 18,
      'distanceKm': 82.5,
      'etaMinutes': 73,
      'plannedAt': '2026-09-26T20:00:00+00:00',
      'timeBufferMinutes': -12,
      'updatedAt': '2026-09-26T18:00:00+00:00',
      'nextStop': {
        'id': 7,
        'type': 'delivery',
        'order': 3,
        'company': 'AIMS Test',
        'address': '9027 Győr',
      },
    });

    expect(state.version, 'R97');
    expect(state.actionCode, 'navigate_next');
    expect(state.secondaryActionCode, 'signal_delay');
    expect(state.riskScore, 72);
    expect(state.confidence, 88);
    expect(state.reasonCodes, contains('late'));
    expect(state.refreshAfterSeconds, 10);
    expect(state.progressPct, 50);
    expect(state.isLate, isTrue);
    expect(state.gpsAccuracyMeters, 18.5);
    expect(state.currentSpeedKmh, 74.2);
    expect(state.dataQuality['gps'], 'stale');
    expect(state.alertFingerprint, 'abc123');
    expect(state.jobId, 96);
    expect(state.distanceKm, 82.5);
    expect(state.etaMinutes, 73);
    expect(state.nextStop?['company'], 'AIMS Test');
  });

  test('Autopilot R97 remains backward compatible with older feed', () {
    final state = DriverAutopilotStatus.fromJson({
      'mode': 'idle',
      'actionCode': 'wait_job',
      'severity': 'info',
      'reference': '',
      'seen': false,
      'accepted': false,
      'totalStops': 0,
      'completedStops': 0,
      'gpsFresh': false,
      'documentsRequired': false,
      'sequenceAnomaly': false,
    });

    expect(state.version, 'R95');
    expect(state.secondaryActionCode, isEmpty);
    expect(state.riskScore, 0);
    expect(state.confidence, 100);
    expect(state.refreshAfterSeconds, 30);
    expect(state.progressPct, 0);
    expect(state.isLate, isFalse);
  });
}
