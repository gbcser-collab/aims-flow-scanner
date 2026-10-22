import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/flow_queue_summary.dart';
import 'package:aims_flow_scanner/screens/flow_sync_details_screen.dart';

void main() {
  test('summary separates current, unknown, foreign and damaged records', () {
    final session = FlowAccountSession(flowId: '123456', sessionToken: 'a' * 64,
      expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: 'ABC-123');
    final summary = FlowQueueSummary.fromRecords([
      {'flowId': '123456', 'plate': 'abc123', 'at': '2026-10-02T12:00:00Z'},
      {'flowId': '123456', 'plate': 'ABC-123', 'at': '2026-10-01T12:00:00Z'},
      {'flowId': '', 'plate': 'ABC-123'},
      {'flowId': '123456', 'plate': ''},
      {'flowId': '654321', 'plate': 'ABC-123'},
      {'flowId': '123456', 'plate': 'XYZ-987'}, null,
    ], session, timeKey: 'at', archived: 2);
    expect(summary.pending, 2);
    expect(summary.unidentified, 2);
    expect(summary.other, 2);
    expect(summary.damaged, 3);
    expect(summary.oldest, DateTime.utc(2026, 10, 1, 12));
  });

  testWidgets('unreadable queue is not rendered as zero', (tester) async {
    await tester.pumpWidget(MaterialApp(home: FlowSyncDetailsScreen(
      load: () async => [const FlowSyncRow(title: 'GPS', detail: 'Nem olvasható')],
      retry: () async {}, translate: (hu, en, de) => hu)));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('retry is single-flight and reloads counts even after a send failure', (tester) async {
    var sends = 0;
    var reads = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: FlowSyncDetailsScreen(
      load: () async { reads++; return [const FlowSyncRow(title: 'GPS', pending: 3, detail: 'Vár')]; },
      retry: () async { sends++; await gate.future; throw StateError('offline'); },
      translate: (hu, en, de) => hu)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Küldés újrapróbálása'));
    await tester.pump();
    await tester.tap(find.text('Küldés újrapróbálása'));
    expect(sends, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.textContaining('Néhány küldés nem sikerült'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
