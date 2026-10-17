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

class FlowOperationsService {
  const FlowOperationsService();

  Future<void> startWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime startedAt,
    required int startKm,
    int? jobId,
  }) async {}

  Future<void> finishWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime finishedAt,
    required int endKm,
  }) async {}

  Future<void> recordOdometer({
    required FlowAccountSession session,
    required String plate,
    required int km,
    required String source,
  }) async {}

  Future<List<FlowServiceAlert>> fetchServiceAlerts({
    required FlowAccountSession session,
    required String plate,
    int? currentKm,
  }) async =>
      const [];

  Future<void> submitSafetyCheck({
    required FlowAccountSession session,
    required String id,
    required String plate,
    required int km,
    required Map<String, String> statuses,
    required Map<String, String> photoPaths,
    required DateTime createdAt,
  }) async {}
}
