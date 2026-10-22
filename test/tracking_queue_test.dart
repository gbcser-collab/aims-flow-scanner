import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/roaming_resilience.dart';
import 'package:aims_flow_scanner/services/tracking_point_queue.dart';
import 'package:aims_flow_scanner/services/tracking_queue_sync.dart';

FlowAccountSession account(String id, [String plate = 'ABC123']) =>
    FlowAccountSession(flowId: id, plate: plate, sessionToken: id * 11,
      expiresAt: DateTime.utc(2099), onboardingComplete: true);

String point(String id, {String owner = '123456', String plate = 'ABC123'}) =>
    jsonEncode({'pointId': id, 'flowId': owner, 'plate': plate,
      'vehicleLabel': plate, 'deviceId': 'original-device',
      'timestamp': '2026-01-01T12:00:00Z', 'latitude': 47.0, 'longitude': 17.0});

http.Response accepted() => http.Response('{"ok":true,"registeredVehicle":true}', 200);

void main() {
  late Directory root;
  late TrackingPointQueue queue;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flow-gps-test-');
    queue = TrackingPointQueue(directory: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('failed replacement preserves the whole original queue after restart', () async {
    await queue.append(point('old'));
    var fail = true;
    final failing = TrackingPointQueue(directory: () async => root,
      beforeReplace: (_) async { if (fail) throw const FileSystemException('disk full'); });
    await expectLater(failing.append(point('new')), throwsA(isA<FileSystemException>()));
    expect(await queue.snapshot(), [point('old')]);
    fail = false;
    await failing.append(point('new'));
    expect(await queue.snapshot(), [point('old'), point('new')]);
  });

  test('acknowledgement failure retains data for safe replay', () async {
    await queue.append(point('old'));
    final failing = TrackingPointQueue(directory: () async => root,
      beforeReplace: (_) async => throw const FileSystemException('disk full'));
    await expectLater(failing.acknowledge([point('old')]), throwsA(isA<FileSystemException>()));
    expect(await queue.snapshot(), [point('old')]);
  });

  test('concurrent appends and partial acknowledgements preserve other owners', () async {
    await Future.wait(List.generate(30, (i) => queue.append(point('$i'))));
    await queue.append(point('other', owner: '654321'));
    await Future.wait([queue.acknowledge([point('1'), point('3')]), queue.append(point('new'))]);
    final remaining = await queue.snapshot();
    expect(remaining.length, 30);
    expect(remaining, containsAll([point('other', owner: '654321'), point('new')]));
    expect(remaining, isNot(contains(point('1'))));
  });

  test('more than 20000 unsent points remain in the active queue', () async {
    final lines = List.generate(20000, (i) => point('$i'));
    await File('${root.path}/aims_tracking_queue.jsonl').writeAsString('${lines.join('\n')}\n');
    await queue.append(point('20000'));
    final stored = await queue.snapshot();
    expect(stored.length, 20001);
    expect(stored.first, lines.first);
  });

  test('foreign and legacy records do not block own points or get relabelled', () async {
    final foreign = List.generate(45, (i) => point('b$i', owner: '654321'));
    for (final line in foreign) { await queue.append(line); }
    await queue.append(point('legacy', owner: ''));
    await queue.append(point('old-car', plate: 'OTHER999'));
    await queue.append(point('mine'));
    final sent = <Map<String, dynamic>>[];
    final result = await TrackingQueueSync(queue: queue, loadSession: () async => account('123456'),
      send: (_, payload) async { sent.add(payload); return accepted(); }).run();
    expect(result.sent, 1);
    expect(sent.single['pointId'], 'mine');
    expect(sent.single['deviceId'], 'original-device');
    expect(await queue.snapshot(), [...foreign, point('legacy', owner: ''), point('old-car', plate: 'OTHER999')]);
    expect(result.more, isFalse);
    expect(result.error, isNotNull);
  });

  test('driver switch during response sends no next point with the old token', () async {
    for (final line in [point('a1'), point('a2'), point('b1', owner: '654321')]) {
      await queue.append(line);
    }
    var current = account('123456');
    final sent = <String>[];
    final sync = TrackingQueueSync(queue: queue, loadSession: () async => current,
      send: (session, payload) async {
        sent.add('${session.flowId}:${payload['pointId']}');
        current = account('654321');
        return accepted();
      });
    final result = await sync.run();
    expect(result.more, isTrue);
    expect(sent, ['123456:a1']);
    await sync.run();
    expect(sent, ['123456:a1', '654321:b1']);
    expect(await queue.snapshot(), [point('a2')]);
  });

  test('slow acknowledgement cannot erase points saved during upload', () async {
    await queue.append(point('first'));
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    final sync = TrackingQueueSync(queue: queue, loadSession: () async => account('123456'),
      send: (_, __) { entered.complete(); return response.future; });
    final running = sync.run();
    await entered.future;
    await queue.append(point('later'));
    response.complete(accepted());
    await running;
    expect(await queue.snapshot(), [point('later')]);
  });

  test('invalid acknowledgement and authentication failures retain original bytes', () async {
    final original = point('first');
    await queue.append(original);
    for (final response in [http.Response('html', 200),
      http.Response('{"ok":true,"registeredVehicle":false}', 200), http.Response('{}', 403)]) {
      final result = await TrackingQueueSync(queue: queue, loadSession: () async => account('123456'),
        send: (_, __) async => response).run();
      expect(result.retryAfter, isNotNull);
      expect(await queue.snapshot(), [original]);
    }
  });

  test('corrupt and permanently rejected records are archived before removal', () async {
    await queue.append('broken-json');
    await queue.append(point('conflict'));
    await queue.append(point('valid'));
    final result = await TrackingQueueSync(queue: queue, loadSession: () async => account('123456'),
      send: (_, payload) async => payload['pointId'] == 'conflict'
        ? http.Response('{"error":"point_identity_conflict"}', 409) : accepted()).run();
    expect(result.sent, 1);
    expect(await queue.snapshot(), isEmpty);
    final archive = (await File('${root.path}/aims_tracking_queue_corrupt.jsonl').readAsLines())
      .map((line) => jsonDecode(line)['raw']).toList();
    expect(archive, ['broken-json', point('conflict')]);
  });

  test('bounded batches continue only when an own point remains', () async {
    for (var i = 0; i < 5; i++) { await queue.append(point('$i')); }
    final sync = TrackingQueueSync(queue: queue, loadSession: () async => account('123456'),
      batchSize: 3, send: (_, __) async => accepted());
    expect((await sync.run()).more, isTrue);
    expect((await queue.snapshot()).length, 2);
    expect((await sync.run()).more, isFalse);
    expect(await queue.snapshot(), isEmpty);
  });

  test('a full upload batch acknowledges with one durable queue rewrite', () async {
    for (var i = 0; i < 40; i++) { await queue.append(point('$i')); }
    var replacements = 0;
    final measured = TrackingPointQueue(directory: () async => root,
      beforeReplace: (_) async { replacements++; });
    final result = await TrackingQueueSync(queue: measured,
      loadSession: () async => account('123456'),
      send: (_, __) async => accepted()).run();
    expect(result.sent, 40);
    expect(replacements, 1);
    expect(await queue.snapshot(), isEmpty);
  });

  test('interrupted append replays its durable journal without losing older points', () async {
    await queue.append(point('old'));
    await File('${root.path}/aims_tracking_queue.jsonl').writeAsString('partial', mode: FileMode.append);
    await File('${root.path}/aims_tracking_append.pending').writeAsString(point('recovered'));
    final restarted = TrackingPointQueue(directory: () async => root);
    expect(await restarted.snapshot(), [point('old'), 'partial', point('recovered')]);
    expect(await File('${root.path}/aims_tracking_append.pending').exists(), isFalse);
    await TrackingQueueSync(queue: restarted, loadSession: () async => account('123456'),
      send: (_, __) async => accepted()).run();
    expect(await restarted.snapshot(), isEmpty);
    expect(await restarted.quarantinedCount(), 1);
  });

  test('append writes only the new record regardless of offline backlog size', () async {
    await File('${root.path}/aims_tracking_queue.jsonl').writeAsString(
      List.generate(20000, (i) => point('$i')).join('\n'));
    final bytes = <int>[];
    final measured = TrackingPointQueue(directory: () async => root,
      beforeReplace: (file) async { bytes.add(await file.length()); });
    await measured.append(point('new'));
    expect(bytes.single, utf8.encode(point('new')).length);
    expect(await measured.count(), 20001);
    await measured.append(point('next'));
    expect(await measured.count(), 20002);
  });

  test('known 32 bit collision now produces distinct stable point IDs', () {
    String idFor(int i) => RoamingResilience.pointId(deviceId: 'SIP-115-device',
      timestamp: DateTime.utc(2026, 9, 20, 8).add(Duration(seconds: i * 15)),
      latitude: 47 + (i % 1000) / 10000,
      longitude: 17 + ((i * 37) % 1000) / 10000);
    // Both formerly produced pt_4abf6c7d.
    expect(idFor(13624), isNot(idFor(18693)));
    expect(idFor(13624), idFor(13624));
    expect(idFor(13624).length, lessThanOrEqualTo(120));
  });
  test('queue counts stay current across independent writers and acknowledgements', () async {
    final second = TrackingPointQueue(directory: () async => root);
    expect(await queue.count(), 0); expect(await second.count(), 0);
    await queue.append(point('a')); expect(await second.count(), 1);
    await second.append(point('b')); expect(await queue.count(), 2);
    await second.acknowledge([point('a')]); expect(await queue.count(), 1);
    await queue.acknowledge([point('b')]); expect(await second.count(), 0);
  });

}
