import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/tracking_workday_guard.dart';

void main() {
  final driver = FlowAccountSession(flowId: '123456', sessionToken: 'a' * 64,
    expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: 'ABC-123');
  final state = <String, Object>{'active': true, 'flowId': '123456', 'plate': 'ABC123',
    'workdayId': '123456-day', 'startedAt': '2026-01-01T08:00:00Z'};
  String journal(Map<String, Object> state) => jsonEncode({'journalVersion': 3,
    'states': {'123456:ABC123': state}});

  test('secure-storage outage remains retryable and active day recovers', () async {
    var unavailable = true;
    final guard = TrackingWorkdayGuard(readJournal: () async => journal(state),
      loadSession: () async { if (unavailable) throw StateError('keystore busy'); return driver; });
    await expectLater(guard.isActive(), throwsStateError);
    expect(guard.retryRequired, isTrue);
    unavailable = false;
    expect(await guard.isActive(), isTrue); expect(guard.retryRequired, isFalse);
  });
  test('journal read failure cannot be mistaken for a finished day', () async {
    var unavailable = true;
    final guard = TrackingWorkdayGuard(readJournal: () async {
      if (unavailable) throw StateError('preferences unavailable'); return journal(state);
    }, loadSession: () async => driver);
    await expectLater(guard.isActive(), throwsStateError); expect(guard.retryRequired, isTrue);
    unavailable = false; expect(await guard.isActive(), isTrue);
  });
  test('damaged or unsupported journals fail closed and keep recovery eligible', () async {
    for (final raw in ['{broken', '[]', '{"journalVersion":4,"states":{}}',
      '{"journalVersion":3,"states":[]}', journal({'active': 'true'})]) {
      final guard = TrackingWorkdayGuard(readJournal: () async => raw, loadSession: () async => driver);
      await expectLater(guard.isActive(), throwsFormatException); expect(guard.retryRequired, isTrue);
    }
  });
  test('confirmed closure after storage recovery clears retry eligibility', () async {
    var raw = '{broken';
    final guard = TrackingWorkdayGuard(readJournal: () async => raw, loadSession: () async => driver);
    await expectLater(guard.isActive(), throwsFormatException);
    raw = journal({...state, 'active': false});
    expect(await guard.isActive(), isFalse); expect(guard.retryRequired, isFalse);
  });
  test('missing, expired or different driver never authorizes retained workday', () async {
    for (final session in <FlowAccountSession?>[null, driver.copyWith(expiresAt: DateTime.utc(2000)),
      FlowAccountSession(flowId: '654321', sessionToken: 'b' * 64,
        expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: 'ABC123'),
      driver.copyWith(plate: 'OTHER123')]) {
      final guard = TrackingWorkdayGuard(readJournal: () async => journal(state), loadSession: () async => session);
      expect(await guard.isActive(), isFalse); expect(guard.retryRequired, isFalse);
    }
  });
  test('points before day start and mismatched stored ownership are rejected', () async {
    var stored = state;
    final guard = TrackingWorkdayGuard(readJournal: () async => journal(stored), loadSession: () async => driver);
    expect(await guard.isActive(capturedAt: DateTime.utc(2026, 1, 1, 7)), isFalse);
    expect(await guard.isActive(capturedAt: DateTime.utc(2026, 1, 1, 8)), isTrue);
    stored = {...state, 'flowId': '654321'}; expect(await guard.isActive(), isFalse);
    stored = {...state, 'plate': 'OTHER123'}; expect(await guard.isActive(), isFalse);
  });
  test('existing legacy identity remains supported and absent journals stop', () async {
    String? raw = jsonEncode({...state}..remove('flowId'));
    final guard = TrackingWorkdayGuard(readJournal: () async => raw, loadSession: () async => driver);
    expect(await guard.isActive(), isTrue);
    raw = null; expect(await guard.isActive(), isFalse); expect(guard.retryRequired, isFalse);
  });
}
