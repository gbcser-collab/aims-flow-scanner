import 'flow_account_service.dart';
import 'flow_local_journal.dart';

/// Counts only; no other driver's identity or payload leaves the journal.
class FlowQueueSummary {
  const FlowQueueSummary({this.pending = 0, this.unidentified = 0,
    this.other = 0, this.damaged = 0, this.oldest});

  final int pending;
  final int unidentified;
  final int other;
  final int damaged;
  final DateTime? oldest;

  factory FlowQueueSummary.fromRecords(Iterable<Map?> records,
      FlowAccountSession session, {required String timeKey, int archived = 0}) {
    var pending = 0;
    var unidentified = 0;
    var other = 0;
    var damaged = archived;
    DateTime? oldest;
    for (final record in records) {
      if (record == null) { damaged++; continue; }
      final owner = record['flowId']?.toString() ?? '';
      final plate = flowJournalPlate(record['plate']?.toString() ?? '');
      if (!RegExp(r'^\d{6}$').hasMatch(owner) || plate.isEmpty) {
        unidentified++;
      } else if (owner != session.flowId || plate != flowJournalPlate(session.plate)) {
        other++;
      } else {
        pending++;
        final at = DateTime.tryParse(record[timeKey]?.toString() ?? '')?.toUtc();
        if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
      }
    }
    return FlowQueueSummary(pending: pending, unidentified: unidentified,
      other: other, damaged: damaged, oldest: oldest);
  }
}
