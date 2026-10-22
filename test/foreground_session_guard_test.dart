import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/foreground_session_guard.dart';

FlowAccountSession driver([String id = '123456', String plate = 'ABC-123']) => FlowAccountSession(
  flowId: id, sessionToken: id * 11, expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: plate);
void main() {
  test('a pending session read cannot authorize after the app pauses', () async {
    final read = Completer<FlowAccountSession?>();
    final guard = ForegroundSessionGuard(loadSession: () => read.future);
    final verification = guard.authorize(driver());
    guard.pause(); read.complete(driver());
    expect(await verification, isFalse);
  });
  test('a prior foreground generation cannot authorize a later resume', () async {
    final first = Completer<FlowAccountSession?>(); var reads = 0;
    final guard = ForegroundSessionGuard(loadSession: () async {
      if (++reads == 1) return first.future; return driver();
    });
    final stale = guard.authorize(driver());
    guard.pause(); guard.resume();
    expect(await guard.authorize(driver()), isTrue);
    first.complete(driver()); expect(await stale, isFalse);
  });
  test('driver, vehicle, token changes and missing login reject retained UI', () async {
    for (final current in <FlowAccountSession?>[null, driver('654321'), driver('123456', 'XYZ987'),
      driver().copyWith(sessionToken: 'b' * 64), driver().copyWith(expiresAt: DateTime.utc(2000))]) {
      final guard = ForegroundSessionGuard(loadSession: () async => current);
      await expectLater(guard.authorize(driver()), throwsA(isA<FlowSessionChanged>()));
    }
  });
  test('storage failure blocks work and a later read can recover without logout', () async {
    var failed = true;
    final guard = ForegroundSessionGuard(loadSession: () async {
      if (failed) throw StateError('keystore busy'); return driver();
    });
    await expectLater(guard.authorize(driver()), throwsStateError);
    failed = false; expect(await guard.authorize(driver()), isTrue);
  });
  test('paused recovery performs no secure-storage read and normalized own plate is accepted', () async {
    var reads = 0;
    final guard = ForegroundSessionGuard(loadSession: () async { reads++; return driver('123456', 'ABC123'); });
    guard.pause(); expect(await guard.authorize(driver()), isFalse); expect(reads, 0);
    guard.resume(); expect(await guard.authorize(driver()), isTrue);
  });
}
