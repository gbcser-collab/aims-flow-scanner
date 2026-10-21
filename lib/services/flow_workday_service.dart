import 'dart:async';
import 'dart:convert';

import 'flow_preferences.dart';

import 'flow_account_service.dart';
import 'flow_operations_service.dart';

class FlowWorkdayState {
  const FlowWorkdayState({
    required this.active,
    this.workdayId = '',
    this.startedAt,
    this.finishedAt,
    this.startKm,
    this.endKm,
    this.startJobId,
    this.syncPending = false,
  });

  final bool active;
  final String workdayId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? startKm;
  final int? endKm;
  final int? startJobId;
  final bool syncPending;

  Duration get elapsed => active && startedAt != null
      ? DateTime.now().difference(startedAt!)
      : startedAt != null && finishedAt != null
          ? finishedAt!.difference(startedAt!)
          : Duration.zero;

  Map<String, dynamic> toJson() => {
        'active': active,
        'workdayId': workdayId,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'startKm': startKm,
        'endKm': endKm,
        'startJobId': startJobId,
        'syncPending': syncPending,
      };

  factory FlowWorkdayState.fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '');
    final storedId = json['workdayId']?.toString().trim() ?? '';
    return FlowWorkdayState(
      active: json['active'] == true,
      workdayId: storedId.isNotEmpty
          ? storedId
          : startedAt == null
              ? ''
              : 'legacy-${startedAt.toUtc().microsecondsSinceEpoch}',
      startedAt: startedAt,
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      startKm: (json['startKm'] as num?)?.toInt(),
      endKm: (json['endKm'] as num?)?.toInt(),
      startJobId: (json['startJobId'] as num?)?.toInt(),
      syncPending: json['syncPending'] == true,
    );
  }
}

class FlowWorkdayService {
  FlowWorkdayService._();
  static final instance = FlowWorkdayService._();
  static const _key = 'aims_flow_workday_v2';
  static const _legacyKey = 'aims_flow_workday_v1';
  final _ops = const FlowOperationsService();

  Future<FlowWorkdayState> load() async {
    final prefs = await FlowPreferences.getInstance();
    var raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      raw = prefs.getString(_legacyKey);
    }
    if (raw == null || raw.isEmpty) return const FlowWorkdayState(active: false);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final state = FlowWorkdayState.fromJson(Map<String, dynamic>.from(decoded));
        if (prefs.getString(_key) == null) await _save(state);
        return state;
      }
    } catch (_) {}
    return const FlowWorkdayState(active: false);
  }

  Future<void> _save(FlowWorkdayState state) async {
    final prefs = await FlowPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<FlowWorkdayState> startIfNeeded({
    required FlowAccountSession session,
    required String plate,
    required int startKm,
    int? jobId,
    DateTime? startedAt,
  }) async {
    final current = await load();
    if (current.active) return current;
    final effectiveStart = (startedAt ?? DateTime.now()).toUtc();
    final workdayId = '${session.flowId}-${effectiveStart.microsecondsSinceEpoch}-${jobId ?? 0}';
    var state = FlowWorkdayState(
      active: true,
      workdayId: workdayId,
      startedAt: effectiveStart,
      startKm: startKm,
      startJobId: jobId,
      syncPending: true,
    );
    await _save(state);
    try {
      await _ops.startWorkday(
        session: session,
        workdayId: workdayId,
        plate: plate,
        startedAt: effectiveStart,
        startKm: startKm,
        jobId: jobId,
      );
      state = FlowWorkdayState(
        active: true,
        workdayId: workdayId,
        startedAt: effectiveStart,
        startKm: startKm,
        startJobId: jobId,
      );
      await _save(state);
    } catch (_) {}
    return state;
  }

  Future<FlowWorkdayState> finish({
    required FlowAccountSession session,
    required String plate,
    required int endKm,
  }) async {
    final current = await load();
    if (!current.active || current.startedAt == null) return current;
    if (current.startKm != null && endKm < current.startKm!) {
      throw StateError('A záró kilométer nem lehet kisebb a kezdő értéknél.');
    }
    final finishedAt = DateTime.now().toUtc();
    final workdayId = current.workdayId.isNotEmpty
        ? current.workdayId
        : '${session.flowId}-${current.startedAt!.toUtc().microsecondsSinceEpoch}-${current.startJobId ?? 0}';
    var state = FlowWorkdayState(
      active: false,
      workdayId: workdayId,
      startedAt: current.startedAt,
      finishedAt: finishedAt,
      startKm: current.startKm,
      endKm: endKm,
      startJobId: current.startJobId,
      syncPending: true,
    );
    await _save(state);
    try {
      await _ops.finishWorkday(
        session: session,
        workdayId: workdayId,
        plate: plate,
        finishedAt: finishedAt,
        endKm: endKm,
        startedAt: current.startedAt,
        startKm: current.startKm,
        startJobId: current.startJobId,
      );
      state = FlowWorkdayState(
        active: false,
        workdayId: workdayId,
        startedAt: current.startedAt,
        finishedAt: finishedAt,
        startKm: current.startKm,
        endKm: endKm,
        startJobId: current.startJobId,
      );
      await _save(state);
    } catch (_) {}
    return state;
  }

  Future<FlowWorkdayState> flushPending({
    required FlowAccountSession session,
    required String plate,
  }) async {
    final state = await load();
    if (!state.syncPending || state.startedAt == null || state.workdayId.isEmpty) {
      return state;
    }
    try {
      if (state.active) {
        if (state.startKm == null) return state;
        await _ops.startWorkday(
          session: session,
          workdayId: state.workdayId,
          plate: plate,
          startedAt: state.startedAt!,
          startKm: state.startKm!,
          jobId: state.startJobId,
        );
      } else {
        if (state.finishedAt == null || state.endKm == null) return state;
        await _ops.finishWorkday(
          session: session,
          workdayId: state.workdayId,
          plate: plate,
          finishedAt: state.finishedAt!,
          endKm: state.endKm!,
          startedAt: state.startedAt,
          startKm: state.startKm,
          startJobId: state.startJobId,
        );
      }
      final synced = FlowWorkdayState(
        active: state.active,
        workdayId: state.workdayId,
        startedAt: state.startedAt,
        finishedAt: state.finishedAt,
        startKm: state.startKm,
        endKm: state.endKm,
        startJobId: state.startJobId,
      );
      await _save(synced);
      return synced;
    } catch (_) {
      return state;
    }
  }
}
