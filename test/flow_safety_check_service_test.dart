import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/flow_safety_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Safety Check stays pending locally until operations backend exists',
      () async {
    final session = FlowAccountSession(
      flowId: '123456',
      expiresAt: DateTime.utc(2030, 1, 1),
      plate: 'ABC-123',
      currentKm: 188420,
    );

    await FlowSafetyCheckService.instance.saveAndSubmit(
      session: session,
      plate: 'ABC-123',
      km: 188430,
      statuses: const {
        'oil': 'ok',
        'coolant': 'ok',
        'tires': 'ok',
        'steering': 'ok',
      },
      photoPaths: const {
        'oil': '/offline/oil.jpg',
        'coolant': '/offline/coolant.jpg',
        'tires': '/offline/tires.jpg',
        'odometer': '/offline/km.jpg',
      },
    );

    final latest = await FlowSafetyCheckService.instance.latestRecord();
    expect(latest, isNotNull);
    expect(latest!.km, 188430);
    expect(latest.hasProblem, isFalse);
    expect(latest.synced, isFalse);
    expect(await FlowSafetyCheckService.instance.pendingCount(), 1);
  });

  test('Safety Check exposes problem status for driver history', () {
    final record = FlowSafetyCheckRecord(
      id: 'test',
      plate: 'ABC-123',
      km: 188500,
      createdAt: DateTime.utc(2026, 10, 19),
      statuses: const {
        'oil': 'ok',
        'coolant': 'problem',
        'tires': 'ok',
        'steering': 'ok',
      },
      photoPaths: const {},
    );

    expect(record.hasProblem, isTrue);
  });
}
