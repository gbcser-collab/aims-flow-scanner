import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/network_recovery.dart';

void main() {
  testWidgets('validated reconnect starts once and offline cancels pending wake',
      (tester) async {
    final events = StreamController<bool>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async { calls++; });
    events.add(false);
    events.add(true);
    events.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 1);
    events.add(false);
    events.add(true);
    await tester.pump();
    events.add(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await recovery.dispose();
    await events.close();
  });

  testWidgets('reconnect during sync is queued once and disposal stops retries',
      (tester) async {
    final events = StreamController<bool>();
    final first = Completer<void>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async {
      calls++;
      if (calls == 1) await first.future;
    });
    events.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    events.add(false);
    events.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 1);
    first.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 2);
    events.add(false);
    events.add(true);
    await tester.pump();
    await recovery.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    await events.close();
  });

  testWidgets('transport errors leave later reconnect recovery usable',
      (tester) async {
    final events = StreamController<bool>();
    var calls = 0;
    final recovery = NetworkRecovery(events.stream, () async {
      calls++;
      if (calls == 1) throw StateError('FLOW endpoint unreachable');
    });
    events.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    events.addError(StateError('native monitor temporarily unavailable'));
    events.add(false);
    events.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 2);
    await recovery.dispose();
    await events.close();
  });
}
