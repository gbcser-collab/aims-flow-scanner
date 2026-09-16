import 'package:aims_flow_scanner/models/freight_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('freight stages are ordered and monotonic', () {
    expect(FreightStage.assigned.next, FreightStage.accepted);
    expect(FreightStage.cmrReview.next, FreightStage.completed);
    expect(FreightStage.completed.canDriverAdvance, isFalse);
    expect(FreightStage.adminApproved.progress, 1);
  });

  test('operation state serializes without losing workflow data', () {
    final source = FreightOperationState.initial().copyWith(
      reference: 'AF-TEST-001',
      plate: 'ABC-123',
      pickup: 'Győr',
      delivery: 'Brno',
      stage: FreightStage.toDelivery,
      evidenceCount: 3,
      notes: const ['Tesztjegyzet'],
      checklist: const {
        'Jármű külső állapot': true,
        'Gumik és világítás': true,
      },
    );

    final restored = FreightOperationState.fromJson(source.toJson());
    expect(restored.reference, 'AF-TEST-001');
    expect(restored.plate, 'ABC-123');
    expect(restored.stage, FreightStage.toDelivery);
    expect(restored.evidenceCount, 3);
    expect(restored.notes.single, 'Tesztjegyzet');
    expect(restored.checklistComplete, isTrue);
  });

  test('waiting duration includes stored and live parts', () {
    final now = DateTime(2026, 9, 17, 1, 0, 30);
    final state = FreightOperationState.initial().copyWith(
      waitingStartedAt: DateTime(2026, 9, 17, 1, 0, 0),
      accumulatedWaitingSeconds: 90,
    );
    expect(state.waitingDuration(now), const Duration(seconds: 120));
  });

  test('critical incidents survive json roundtrip', () {
    final incident = FreightIncident(
      id: 'inc-1',
      kind: IncidentKind.vehicle,
      note: 'Motorhiba',
      createdAt: DateTime(2026, 9, 17),
      critical: true,
    );
    final restored = FreightIncident.fromJson(incident.toJson());
    expect(restored.kind, IncidentKind.vehicle);
    expect(restored.critical, isTrue);
    expect(restored.note, 'Motorhiba');
  });
}
