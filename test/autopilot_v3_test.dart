import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/driver_api_service.dart';

void main() {
  test('Autopilot V3 parses driver decision feed', () {
    final state = DriverAutopilotStatus.fromJson({
      'mode': 'enroute',
      'actionCode': 'navigate_next',
      'severity': 'warn',
      'reference': 'AIMS-95',
      'seen': true,
      'accepted': true,
      'totalStops': 4,
      'completedStops': 2,
      'gpsFresh': true,
      'documentsRequired': false,
      'sequenceAnomaly': false,
      'jobId': 95,
      'gpsAgeMinutes': 2,
      'stationaryMinutes': 4,
      'stopDwellMinutes': null,
      'distanceKm': 82.5,
      'etaMinutes': 73,
      'plannedAt': '2026-09-26T20:00:00+00:00',
      'timeBufferMinutes': 22,
      'nextStop': {
        'id': 7,
        'type': 'delivery',
        'order': 3,
        'company': 'AIMS Test',
        'address': '9027 Győr',
      },
    });

    expect(state.actionCode, 'navigate_next');
    expect(state.jobId, 95);
    expect(state.totalStops, 4);
    expect(state.completedStops, 2);
    expect(state.distanceKm, 82.5);
    expect(state.etaMinutes, 73);
    expect(state.nextStop?['company'], 'AIMS Test');
  });

  test('Autopilot V3 safely defaults missing fields', () {
    final state = DriverAutopilotStatus.fromJson(const {});
    expect(state.mode, 'idle');
    expect(state.actionCode, 'wait_job');
    expect(state.totalStops, 0);
    expect(state.documentsRequired, isFalse);
  });
}
