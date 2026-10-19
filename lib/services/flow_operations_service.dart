import 'flow_account_service.dart';

class FlowServiceAlert {
  const FlowServiceAlert({
    required this.id,
    required this.title,
    required this.severity,
    this.remainingKm,
    this.dueDate,
  });

  final String id;
  final String title;
  final String severity;
  final int? remainingKm;
  final DateTime? dueDate;

  bool get urgent => severity == 'overdue' || severity == 'critical';
}

/// Bridge for the new FLOW Driver operations backend.
///
/// Until AIMS_FLOW_DRIVER_OPS_URL is supplied by the production build, write
/// operations deliberately fail so the caller keeps its local offline queue.
/// This is safer than reporting a successful sync when no backend exists.
class FlowOperationsService {
  const FlowOperationsService();

  static const driverOpsUrl = String.fromEnvironment(
    'AIMS_FLOW_DRIVER_OPS_URL',
    defaultValue: '',
  );

  bool get configured => driverOpsUrl.trim().isNotEmpty;

  Never _notConfigured() => throw StateError(
        'FLOW Driver műveleti szerver nincs beállítva. Az adat offline mentve marad.',
      );

  Future<void> startWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime startedAt,
    required int startKm,
    int? jobId,
  }) async {
    if (!configured) _notConfigured();
    // Network adapter is intentionally activated only after the authenticated
    // v2 server contract is deployed. Until then the workday remains pending.
    _notConfigured();
  }

  Future<void> finishWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime finishedAt,
    required int endKm,
  }) async {
    if (!configured) _notConfigured();
    _notConfigured();
  }

  Future<void> recordOdometer({
    required FlowAccountSession session,
    required String plate,
    required int km,
    required String source,
  }) async {
    if (!configured) _notConfigured();
    _notConfigured();
  }

  Future<List<FlowServiceAlert>> fetchServiceAlerts({
    required FlowAccountSession session,
    required String plate,
    int? currentKm,
  }) async {
    if (!configured) return const [];
    return const [];
  }

  Future<void> submitSafetyCheck({
    required FlowAccountSession session,
    required String id,
    required String plate,
    required int km,
    required Map<String, String> statuses,
    required Map<String, String> photoPaths,
    required DateTime createdAt,
  }) async {
    if (!configured) _notConfigured();
    _notConfigured();
  }
}
