import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/flow_workday_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('workday keeps stable id and pending state while ops backend is offline',
      () async {
    final session = FlowAccountSession(
      flowId: '123456',
      sessionToken: '',
      onboardingComplete: true,
      expiresAt: DateTime.utc(2030, 1, 1),
      plate: 'ABC-123',
      currentKm: 100000,
    );
    final acceptedAt = DateTime.utc(2026, 10, 19, 8, 30);

    final started = await FlowWorkdayService.instance.startIfNeeded(
      session: session,
      plate: 'ABC-123',
      startKm: 100000,
      jobId: 42,
      startedAt: acceptedAt,
    );

    expect(started.active, isTrue);
    expect(started.startedAt, acceptedAt);
    expect(started.startKm, 100000);
    expect(started.workdayId, contains('123456'));
    expect(started.workdayId, endsWith('-42'));
    expect(started.syncPending, isTrue);

    final reloaded = await FlowWorkdayService.instance.load();
    expect(reloaded.workdayId, started.workdayId);
    expect(reloaded.syncPending, isTrue);

    final finished = await FlowWorkdayService.instance.finish(
      session: session,
      plate: 'ABC-123',
      endKm: 100180,
    );
    expect(finished.active, isFalse);
    expect(finished.workdayId, started.workdayId);
    expect(finished.endKm, 100180);
    expect(finished.syncPending, isTrue);
  });

  test('workday rejects closing odometer below opening value', () async {
    final session = FlowAccountSession(
      flowId: '654321',
      sessionToken: '',
      onboardingComplete: true,
      expiresAt: DateTime.utc(2030, 1, 1),
      plate: 'XYZ-987',
      currentKm: 200000,
    );
    await FlowWorkdayService.instance.startIfNeeded(
      session: session,
      plate: 'XYZ-987',
      startKm: 200000,
      jobId: 7,
    );

    expect(
      () => FlowWorkdayService.instance.finish(
        session: session,
        plate: 'XYZ-987',
        endKm: 199999,
      ),
      throwsStateError,
    );
  });
}
