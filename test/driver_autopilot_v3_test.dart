import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/driver_api_service.dart';

void main() {
  test('parses idle Autopilot V3 state', () {
    final x = DriverAutopilotStatus.fromJson({
      'mode': 'idle',
      'actionCode': 'wait_job',
      'severity': 'info',
      'reference': '',
      'seen': false,
      'accepted': false,
      'totalStops': 0,
      'completedStops': 0,
      'gpsFresh': true,
      'documentsRequired': false,
      'sequenceAnomaly': false,
    });
    expect(x.mode, 'idle');
    expect(x.actionCode, 'wait_job');
    expect(x.totalStops, 0);
  });

  test('parses active next-step state', () {
    final x = DriverAutopilotStatus.fromJson({
      'mode': 'enroute',
      'actionCode': 'navigate_next',
      'severity': 'warn',
      'reference': 'AIMS-42',
      'seen': true,
      'accepted': true,
      'totalStops': 4,
      'completedStops': 1,
      'gpsFresh': true,
      'documentsRequired': false,
      'sequenceAnomaly': false,
      'gpsAgeMinutes': 2,
      'stationaryMinutes': 11,
      'distanceKm': 84.5,
      'etaMinutes': 74,
      'timeBufferMinutes': 18,
      'nextStop': {
        'id': 7,
        'type': 'pickup',
        'order': 2,
        'company': 'Test Logistics',
        'address': '9027 Győr',
        'arrived': false,
      },
    });
    expect(x.nextStop?['company'], 'Test Logistics');
    expect(x.etaMinutes, 74);
    expect(x.distanceKm, 84.5);
  });

  test('parses critical workflow anomaly', () {
    final x = DriverAutopilotStatus.fromJson({
      'mode': 'attention',
      'actionCode': 'refresh_job',
      'severity': 'high',
      'reference': 'AIMS-99',
      'seen': true,
      'accepted': true,
      'totalStops': 3,
      'completedStops': 1,
      'gpsFresh': false,
      'documentsRequired': false,
      'sequenceAnomaly': true,
    });
    expect(x.severity, 'high');
    expect(x.sequenceAnomaly, isTrue);
    expect(x.gpsFresh, isFalse);
  });
}
