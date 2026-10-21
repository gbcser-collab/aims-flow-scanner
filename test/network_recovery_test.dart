import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/network_recovery.dart';

void main() {
  test('validated reconnect starts once and offline cancels pending wake',
      () async {
    final events = StreamController<bool>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async { calls++; },
      debounce: const Duration(milliseconds: 1));
    events.add(false);
    events.add(true);
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    events.add(false);
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    events.add(false);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    await recovery.dispose();
    await events.close();
  });

  test('reconnect during sync is queued once and disposal stops retries',
      () async {
    final events = StreamController<bool>();
    final first = Completer<void>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async {
      calls++;
      if (calls == 1) await first.future;
    }, debounce: const Duration(milliseconds: 1));
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.add(false);
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
    events.add(false);
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await recovery.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
    await events.close();
  });

  test('transport errors leave later reconnect recovery usable',
      () async {
    final events = StreamController<bool>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async {
      calls++;
      if (calls == 1) throw StateError('FLOW endpoint unreachable');
    }, debounce: const Duration(milliseconds: 1));
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.addError(StateError('native monitor temporarily unavailable'));
    events.add(false);
    events.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
    await recovery.dispose();
    await events.close();
  });
}
