import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/flow_operations_service.dart';
import 'package:aims_flow_scanner/services/flow_safety_check_service.dart';
import 'package:aims_flow_scanner/services/flow_workday_service.dart';

class SafetyOps extends FlowOperationsService {
  bool offline = true;
  int? rejectedKm;
  Completer<void>? gate;
  final entered = Completer<void>();
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> submitSafetyCheck({required FlowAccountSession session,
    required String id, required String plate, required int km,
    required Map<String, String> statuses, required Map<String, String> photoPaths,
    required DateTime createdAt}) async {
    if (offline) throw StateError('offline');
    if (km == rejectedKm) {
      throw FlowOperationException('missing photo', code: 'safety_local_photo_missing', statusCode: 422);
    }
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    sent.add({'id': id, 'owner': session.flowId, 'plate': plate, 'km': km});
  }
}

FlowAccountSession account(String id, [String plate = 'ABC-123']) => FlowAccountSession(
  flowId: id, sessionToken: 'a' * 64, expiresAt: DateTime.utc(2099),
  onboardingComplete: true, plate: plate);
const statuses = {'oil': 'ok', 'coolant': 'ok', 'tires': 'ok', 'steering': 'ok'};
const photos = {'oil': '/oil.jpg', 'coolant': '/water.jpg', 'tires': '/tire.jpg', 'odometer': '/km.jpg'};
Future<void> save(FlowSafetyCheckService service, FlowAccountSession session, [int km = 1000]) =>
  service.saveAndSubmit(session: session, plate: session.plate, km: km,
    statuses: statuses, photoPaths: photos);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('more than 30 unsent checks survive subsequent saves and a service restart', () async {
    final ops = SafetyOps();
    var service = FlowSafetyCheckService(operations: ops);
    final a = account('123456');
    for (var i = 0; i < 35; i++) { await save(service, a, 1000 + i); }
    service = FlowSafetyCheckService(operations: ops);
    expect(await service.pendingCount(session: a), 35);
    ops.offline = false;
    await service.flushPending(session: a);
    expect(ops.sent.length, 35);
    expect(ops.sent.map((r) => r['km']).toList(), List.generate(35, (i) => 1000 + i));
    expect(await service.pendingCount(session: a), 0);
    expect((await service.recentRecords(session: a, limit: 100)).length, 30);
  });

  test('acknowledging a slow upload preserves a check saved while it was in flight', () async {
    final ops = SafetyOps()..offline = false;
    ops.gate = Completer<void>();
    final service = FlowSafetyCheckService(operations: ops);
    final a = account('123456');
    final first = save(service, a, 1000);
    await ops.entered.future.timeout(const Duration(seconds: 2));
    final second = save(service, a, 1001);
    expect(await service.pendingCount(session: a), 2);
    ops.gate!.complete();
    await Future.wait([first, second]);
    expect(ops.sent.map((r) => r['km']).toList(), [1000, 1001]);
    expect((await service.recentRecords(session: a)).length, 2);
    expect(await service.pendingCount(session: a), 0);
  });

  test('one rejected record cannot block later valid checks or disappear', () async {
    final ops = SafetyOps();
    final service = FlowSafetyCheckService(operations: ops);
    final a = account('123456');
    await save(service, a, 1000);
    await save(service, a, 1001);
    ops.offline = false;
    ops.rejectedKm = 1000;
    await service.flushPending(session: a);
    expect(ops.sent.single['km'], 1001);
    expect(await service.pendingCount(session: a), 1);
    expect((await service.recentRecords(session: a)).length, 2);
    ops.rejectedKm = null;
    await service.flushPending(session: a);
    expect(ops.sent.last['km'], 1000);
    expect(await service.pendingCount(session: a), 0);
  });

  test('driver switch on the same vehicle cannot inherit or send another check', () async {
    final ops = SafetyOps();
    final service = FlowSafetyCheckService(operations: ops);
    final a = account('123456');
    final b = account('654321');
    await save(service, a);
    expect(await service.latestRecord(session: b), isNull);
    ops.offline = false;
    await save(service, b, 1100);
    expect(ops.sent.single['owner'], '654321');
    expect(await service.pendingCount(session: a), 1);
    await service.flushPending(session: a);
    expect(ops.sent.last['owner'], '123456');
  });

  test('reassigned vehicle does not relabel or upload a previous vehicle record', () async {
    final ops = SafetyOps();
    final service = FlowSafetyCheckService(operations: ops);
    final old = account('123456');
    await save(service, old);
    final changed = account('123456', 'XYZ-987');
    ops.offline = false;
    await save(service, changed, 2000);
    expect(ops.sent.single['plate'], 'XYZ-987');
    expect(await service.pendingCount(session: changed), 1);
    expect((await service.recentRecords(session: changed)).single.km, 2000);
    await service.flushPending(session: old);
    expect(ops.sent.last['plate'], 'ABC-123');
  });

  test('legacy records with unknown owner stay preserved without attribution', () async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = FlowSafetyCheckRecord(id: 'old', plate: 'ABC-123', km: 1000,
      createdAt: DateTime.utc(2025), statuses: statuses, photoPaths: photos);
    await prefs.setString('aims_flow_safety_records_v1', jsonEncode([legacy.toJson()]));
    final ops = SafetyOps()..offline = false;
    final service = FlowSafetyCheckService(operations: ops);
    await service.flushPending(session: account('123456'));
    expect(ops.sent, isEmpty);
    expect(await service.unidentifiedPendingCount(), 1);
    expect(await service.latestRecord(session: account('123456')), isNull);
  });

  test('malformed journal cannot be silently replaced by a new check', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_flow_safety_records_v1', '{broken');
    await expectLater(save(FlowSafetyCheckService(operations: SafetyOps()), account('123456')), throwsStateError);
    expect(prefs.getString('aims_flow_safety_records_v1'), '{broken');
  });

  test('payload maps are frozen before asynchronous storage or upload', () async {
    final service = FlowSafetyCheckService(operations: SafetyOps());
    final mutableStatuses = Map<String, String>.from(statuses);
    final mutablePhotos = Map<String, String>.from(photos);
    final a = account('123456');
    final saving = service.saveAndSubmit(session: a, plate: a.plate, km: 1000,
      statuses: mutableStatuses, photoPaths: mutablePhotos);
    mutableStatuses['oil'] = 'problem';
    mutablePhotos['oil'] = '/replacement.jpg';
    await saving;
    final record = (await service.latestRecord(session: a))!;
    expect(record.statuses['oil'], 'ok');
    expect(record.photoPaths['oil'], '/oil.jpg');
    expect(() => record.statuses['oil'] = 'problem', throwsUnsupportedError);
  });

  test('incomplete checklist is rejected before a pending item is created', () async {
    final service = FlowSafetyCheckService(operations: SafetyOps());
    final a = account('123456');
    await expectLater(service.saveAndSubmit(session: a, plate: a.plate, km: 1000,
      statuses: const {'oil': 'ok'}, photoPaths: photos), throwsStateError);
    expect(await service.pendingCount(), 0);
  });

  test('prompt requires a fresh reliable stationary fix and uses owner-specific schedule', () async {
    final service = FlowSafetyCheckService(operations: SafetyOps());
    final a = account('123456');
    final b = account('654321');
    final prefs = await SharedPreferences.getInstance();
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
    await prefs.setString('aims_flow_safety_next_due_v2:123456:ABC123', yesterday);
    await prefs.setString('aims_flow_safety_next_due_v2:654321:ABC123', yesterday);
    Position fix({double speed = 0, double accuracy = 5, DateTime? at}) => Position(
      latitude: 47, longitude: 17, timestamp: at ?? DateTime.now(), accuracy: accuracy,
      altitude: 0, altitudeAccuracy: 1, heading: 0, headingAccuracy: 1,
      speed: speed, speedAccuracy: 1);
    FlowWorkdayState day(FlowAccountSession s) => FlowWorkdayState(active: true,
      flowId: s.flowId, plate: s.plate, startedAt: DateTime.now().subtract(const Duration(hours: 2)));
    Future<bool> prompt(FlowAccountSession s, Position p) => service.shouldPrompt(
      session: s, workday: day(s), hasActiveJob: false, position: p);
    expect(await prompt(a, fix()), isTrue);
    expect(await prompt(a, fix(speed: -1)), isFalse);
    expect(await prompt(a, fix(speed: double.nan)), isFalse);
    expect(await prompt(a, fix(speed: 10)), isFalse);
    expect(await prompt(a, fix(accuracy: 100)), isFalse);
    expect(await prompt(a, fix(at: DateTime.now().subtract(const Duration(minutes: 5)))), isFalse);
    await service.snooze(session: a);
    expect(await prompt(a, fix()), isFalse);
    expect(await prompt(b, fix()), isTrue);
  });
}
