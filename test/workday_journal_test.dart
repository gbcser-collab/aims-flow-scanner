import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/flow_operations_service.dart';
import 'package:aims_flow_scanner/services/flow_workday_service.dart';

class RecordingOps extends FlowOperationsService {
  bool offline = true;
  final sent = <Map<String, dynamic>>[];
  Completer<void>? startGate;
  final startEntered = Completer<void>();

  @override
  Future<void> startWorkday({required FlowAccountSession session,
    required String workdayId, required String plate, required DateTime startedAt,
    required int startKm, int? jobId}) async {
    if (offline) throw StateError('offline');
    if (!startEntered.isCompleted) startEntered.complete();
    if (startGate != null) await startGate!.future;
    sent.add({'action': 'start', 'id': workdayId, 'plate': plate, 'owner': session.flowId});
  }

  @override
  Future<void> finishWorkday({required FlowAccountSession session,
    required String workdayId, required String plate, required DateTime finishedAt,
    required int endKm, DateTime? startedAt, int? startKm, int? startJobId}) async {
    if (offline) throw StateError('offline');
    sent.add({'action': 'finish', 'id': workdayId, 'plate': plate,
      'owner': session.flowId, 'startKm': startKm, 'endKm': endKm,
      'startedAt': startedAt, 'finishedAt': finishedAt});
  }
}

FlowAccountSession driver(String id, [String plate = 'ABC-123']) => FlowAccountSession(
  flowId: id, sessionToken: 'a' * 64, onboardingComplete: true,
  expiresAt: DateTime.utc(2099), plate: plate);

FlowWorkdayService service(RecordingOps ops, {Future<void> Function()? stop}) =>
    FlowWorkdayService(operations: ops, beginTracking: (_) async {},
      endTracking: stop ?? () async {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('multiple offline days survive restart and replay their full snapshots', () async {
    final ops = RecordingOps();
    final account = driver('123456');
    var workday = service(ops);
    final ids = <String>[];
    for (var day = 1; day <= 3; day++) {
      final started = await workday.startIfNeeded(session: account,
        plate: account.plate, startKm: 1000 + day * 100,
        startedAt: DateTime.utc(2025, 1, day));
      ids.add(started.workdayId);
      await workday.finish(session: account, plate: account.plate,
        endKm: 1050 + day * 100);
      workday = service(ops); // New service instance reads only persisted data.
    }
    expect(await workday.pendingCount(session: account), 3);
    ops.offline = false;
    await workday.flushPending(session: account, plate: account.plate);
    expect(ops.sent.map((item) => item['id']).toList(), ids);
    expect(ops.sent.every((item) => item['action'] == 'finish'), isTrue);
    expect(ops.sent.map((item) => item['startKm']).toList(), [1100, 1200, 1300]);
    expect(ops.sent.map((item) => item['endKm']).toList(), [1150, 1250, 1350]);
    expect(await workday.pendingCount(session: account), 0);
    expect((await workday.load(session: account)).active, isFalse);
  });

  test('a new driver on the same vehicle cannot send or inherit another day', () async {
    final ops = RecordingOps();
    final workday = service(ops);
    final a = driver('123456');
    final b = driver('654321');
    await workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await workday.finish(session: a, plate: a.plate, endKm: 1100);
    expect((await workday.load(session: b)).workdayId, isEmpty);
    await workday.startIfNeeded(session: b, plate: b.plate, startKm: 1100);
    ops.offline = false;
    await workday.flushPending(session: b, plate: b.plate);
    expect(ops.sent.map((item) => item['owner']).toList(), ['654321']);
    expect(await workday.pendingCount(session: a), 1);
    expect((await workday.load(session: a)).endKm, 1100);
    await workday.flushPending(session: a, plate: a.plate);
    expect((await workday.load(session: b)).active, isTrue);
    expect((await workday.load()).flowId, '654321');
  });

  test('vehicle reassignment retains old plate without relabelling a queued day', () async {
    final ops = RecordingOps();
    final workday = service(ops);
    final a = driver('123456');
    await workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await workday.finish(session: a, plate: a.plate, endKm: 1100);
    final changed = a.copyWith(plate: 'XYZ-987');
    await workday.startIfNeeded(session: changed, plate: changed.plate, startKm: 2000);
    ops.offline = false;
    await workday.flushPending(session: changed, plate: changed.plate);
    expect(ops.sent.single['plate'], 'XYZ-987');
    expect(await workday.pendingCount(session: a), 1);
    await workday.flushPending(session: a, plate: a.plate);
    expect(ops.sent.last['plate'], 'ABC-123');
    expect(ops.sent.last['endKm'], 1100);
  });

  test('late start acknowledgement cannot reopen or erase a local finish', () async {
    final ops = RecordingOps()..offline = false;
    ops.startGate = Completer<void>();
    final stopped = Completer<void>();
    final workday = service(ops, stop: () async { stopped.complete(); });
    final a = driver('123456');
    final starting = workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await ops.startEntered.future.timeout(const Duration(seconds: 2));
    final finishing = workday.finish(session: a, plate: a.plate, endKm: 1100);
    await stopped.future.timeout(const Duration(seconds: 2));
    expect((await workday.load(session: a)).active, isFalse);
    expect((await workday.load(session: a)).syncPending, isTrue);
    ops.startGate!.complete();
    await Future.wait([starting, finishing]);
    final state = await workday.load(session: a);
    expect(state.active, isFalse);
    expect(state.endKm, 1100);
    expect(state.syncPending, isFalse);
    expect(ops.sent.map((item) => item['action']).toList(), ['start', 'finish']);
    expect(await workday.pendingCount(session: a), 0);
  });

  test('concurrent starts share one durable workday and one pending item', () async {
    final workday = service(RecordingOps());
    final a = driver('123456');
    final states = await Future.wait(List.generate(2, (_) =>
      workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000)));
    expect(states[0].workdayId, states[1].workdayId);
    expect(await workday.pendingCount(session: a), 1);
  });

  test('upgrade captures original identity before a new login replaces hints', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_flow_id', '123456');
    await prefs.setString('aims_driver_plate', 'ABC-123');
    await prefs.setString('aims_flow_workday_v2', jsonEncode({
      'active': false, 'workdayId': '123456-old-day', 'startKm': 1000,
      'endKm': 1100, 'startedAt': '2025-01-01T08:00:00Z',
      'finishedAt': '2025-01-01T16:00:00Z', 'syncPending': true,
    }));
    await FlowSessionStore.instance.save(driver('654321', 'XYZ-987'));
    final ops = RecordingOps()..offline = false;
    final workday = service(ops);
    final old = driver('123456');
    expect((await workday.load(session: old)).plate, 'ABC-123');
    await workday.flushPending(session: old, plate: old.plate);
    expect(ops.sent.single['id'], '123456-old-day');
    expect(ops.sent.single['plate'], 'ABC-123');
  });

  test('unknown legacy vehicle stays preserved without guessing a new plate', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_flow_id', '654321');
    await prefs.setString('aims_driver_plate', 'XYZ-987');
    await prefs.setString('aims_flow_workday_v2', jsonEncode({
      'active': false, 'workdayId': '123456-old-day', 'startKm': 1000,
      'endKm': 1100, 'startedAt': '2025-01-01T08:00:00Z',
      'finishedAt': '2025-01-01T16:00:00Z', 'syncPending': true,
    }));
    final ops = RecordingOps()..offline = false;
    final workday = service(ops);
    final old = driver('123456');
    await workday.flushPending(session: old, plate: old.plate);
    expect(ops.sent, isEmpty);
    expect(await workday.pendingCount(session: old), 1);
    expect(prefs.getString('aims_flow_workday_v2'), contains('123456-old-day'));
  });

  test('malformed stored journal is never replaced by a new workday', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_flow_workday_v2', '{broken');
    final workday = service(RecordingOps());
    final a = driver('123456');
    await expectLater(workday.startIfNeeded(session: a, plate: a.plate,
      startKm: 1000), throwsStateError);
    expect(prefs.getString('aims_flow_workday_v2'), '{broken');
  });

  test('wrong vehicle is rejected before local state or queue changes', () async {
    final workday = service(RecordingOps());
    final a = driver('123456');
    await expectLater(workday.startIfNeeded(session: a, plate: 'XYZ-987',
      startKm: 1000), throwsStateError);
    expect(await workday.pendingCount(session: a), 0);
  });

  test('finishing a different inactive driver cannot stop the active driver GPS', () async {
    var stops = 0;
    final workday = service(RecordingOps(), stop: () async { stops++; });
    final a = driver('123456');
    final b = driver('654321');
    await workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await workday.finish(session: b, plate: b.plate, endKm: 1100);
    expect(stops, 0);
    expect((await workday.load(session: a)).active, isTrue);
    expect(await workday.pendingCount(session: a), 1);
  });

  test('retry failure retains every remaining day and a later retry drains it', () async {
    final ops = RecordingOps();
    final workday = service(ops);
    final a = driver('123456');
    for (var i = 0; i < 2; i++) {
      await workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000 + i * 100);
      await workday.finish(session: a, plate: a.plate, endKm: 1100 + i * 100);
    }
    await workday.flushPending(session: a, plate: a.plate);
    expect(await workday.pendingCount(session: a), 2);
    expect(ops.sent, isEmpty);
    ops.offline = false;
    await workday.flushPending(session: a, plate: a.plate);
    await workday.flushPending(session: a, plate: a.plate);
    expect(ops.sent.length, 2);
    expect(await workday.pendingCount(session: a), 0);
  });
  test('slow GPS start, close and next start keep their durable order across services', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final finished = Completer<void>();
    final events = <String>[];
    var starts = 0;
    Future<void> begin(String plate) async {
      starts++; events.add('begin$starts');
      if (starts == 1) { started.complete(); await gate.future; }
      if (starts == 2) finished.complete();
    }
    final ops = RecordingOps();
    final a = driver('123456');
    final first = FlowWorkdayService(operations: ops, beginTracking: begin,
      endTracking: () async { events.add('stop'); });
    final second = FlowWorkdayService(operations: ops, beginTracking: begin,
      endTracking: () async { events.add('stop'); });
    await first.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await started.future;
    await first.finish(session: a, plate: a.plate, endKm: 1100);
    expect((await first.load(session: a)).active, isFalse);
    await second.startIfNeeded(session: a, plate: a.plate, startKm: 1100);
    expect(events, ['begin1']);
    gate.complete(); await finished.future.timeout(const Duration(seconds: 2));
    expect(events, ['begin1', 'stop', 'begin2']);
    expect((await second.load(session: a)).active, isTrue);
  });
  test('failed GPS transition cannot poison the following local closure', () async {
    final stopped = Completer<void>();
    final workday = FlowWorkdayService(operations: RecordingOps(),
      beginTracking: (_) async { throw StateError('GPS unavailable'); },
      endTracking: () async { stopped.complete(); });
    final a = driver('123456');
    await workday.startIfNeeded(session: a, plate: a.plate, startKm: 1000);
    await workday.finish(session: a, plate: a.plate, endKm: 1100);
    await stopped.future.timeout(const Duration(seconds: 2));
    expect((await workday.load(session: a)).active, isFalse);
  });

}
