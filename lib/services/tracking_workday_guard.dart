import 'dart:convert';

import 'flow_account_service.dart';
import 'flow_local_journal.dart';

/// Unknown storage state is not evidence that a workday has ended.
/// Callers must not capture/acknowledge a point until this check succeeds.
class TrackingWorkdayGuard {
  TrackingWorkdayGuard({required this.readJournal, required this.loadSession});
  final Future<String?> Function() readJournal;
  final Future<FlowAccountSession?> Function() loadSession;
  bool retryRequired = false;

  Future<bool> isActive({FlowAccountSession? session, DateTime? capturedAt}) async {
    try {
      final active = await _read(session, capturedAt);
      retryRequired = false;
      return active;
    } catch (_) {
      retryRequired = true;
      rethrow;
    }
  }

  Future<bool> _read(FlowAccountSession? session, DateTime? capturedAt) async {
    final raw = await readJournal();
    if (raw == null || raw.trim().isEmpty) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid workday journal');
    session ??= await loadSession();
    if (session == null || session.isExpired) return false;
    final key = '${session.flowId}:${flowJournalPlate(session.plate)}';
    Object? state = decoded;
    if (decoded['journalVersion'] != null) {
      if (decoded['journalVersion'] != 3 || decoded['states'] is! Map) {
        throw const FormatException('Invalid workday states');
      }
      state = (decoded['states'] as Map)[key];
      if (state == null) return false;
    }
    if (state is! Map || state['active'] is! bool) {
      throw const FormatException('Invalid workday state');
    }
    if (state['active'] != true) return false;
    final owner = state['flowId']?.toString() ??
        RegExp(r'^(\d{6})-').firstMatch(state['workdayId']?.toString() ?? '')?.group(1);
    final plate = state['plate']?.toString() ?? '';
    final started = DateTime.tryParse(state['startedAt']?.toString() ?? '');
    if (capturedAt != null && (started == null || capturedAt.isBefore(started))) return false;
    return owner == session.flowId && flowJournalPlate(plate).isNotEmpty &&
        flowJournalPlate(plate) == flowJournalPlate(session.plate);
  }
}
