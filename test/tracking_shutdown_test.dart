import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/tracking_shutdown.dart';

void main() {
  test('local stop completes before a stalled sync and does not await the network', () async {
    final stopped = Completer<void>();
    final network = Completer<void>();
    final events = <String>[];
    final shutdown = stopTrackingBeforeSync(
      stop: () async { events.add('stopping'); await stopped.future; events.add('stopped'); },
      sync: () async { events.add('sync'); await network.future; });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['stopping']);
    stopped.complete();
    await shutdown.timeout(const Duration(seconds: 1));
    expect(events, ['stopping', 'stopped', 'sync']);
    expect(network.isCompleted, isFalse);
    network.complete();
  });

  test('synchronous or asynchronous network failures do not undo local stop', () async {
    var stops = 0;
    await stopTrackingBeforeSync(stop: () async { stops++; }, sync: () => throw StateError('offline'));
    await stopTrackingBeforeSync(stop: () async { stops++; }, sync: () async { throw StateError('offline'); });
    await Future<void>.delayed(Duration.zero);
    expect(stops, 2);
  });

  test('a failed local stop is reported and never starts network work', () async {
    var synced = false;
    await expectLater(stopTrackingBeforeSync(stop: () async { throw StateError('stop'); },
      sync: () async { synced = true; }), throwsStateError);
    expect(synced, isFalse);
  });
}
