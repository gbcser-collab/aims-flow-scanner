import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'flow_account_service.dart';
import 'flow_queue_summary.dart';
import 'flow_operations_service.dart';
import 'flow_local_journal.dart';
import 'local_serial_executor.dart';
import 'vehicle_tracking_service.dart';

class FlowWorkdayState {
  const FlowWorkdayState({
    required this.active,
    this.workdayId = '',
    this.flowId = '',
    this.plate = '',
    this.startedAt,
    this.finishedAt,
    this.startKm,
    this.endKm,
    this.startJobId,
    this.syncPending = false,
  });

  final bool active;
  final String workdayId;
  final String flowId;
  final String plate;
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
        'flowId': flowId,
        'plate': plate,
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
      flowId: json['flowId']?.toString() ?? '',
      plate: json['plate']?.toString() ?? '',
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
  FlowWorkdayService({
    FlowOperationsService operations = const FlowOperationsService(),
    Future<void> Function(String)? beginTracking,
    Future<void> Function()? endTracking,
  })  : _ops = operations,
        _beginTracking = beginTracking ?? _beginDefault,
        _endTracking = endTracking ?? VehicleTrackingService.instance.endWorkday;

  static final instance = FlowWorkdayService();
  static const _key = 'aims_flow_workday_v2';
  final FlowOperationsService _ops;
  final Future<void> Function(String) _beginTracking;
  final Future<void> Function() _endTracking;
  final _syncSerial = LocalSerialExecutor();
  static final _trackingSerial = LocalSerialExecutor();

  void _scheduleTracking(Future<void> Function() action) {
    // Enqueue inside the durable transaction, so start/stop order cannot invert.
    unawaited(_trackingSerial.run(action).catchError((Object _) {}));
  }

  static Future<void> _beginDefault(String plate) async {
    await VehicleTrackingService.instance.beginWorkday(plate);
  }

  static String _ownerKey(String flowId, String plate) =>
      '$flowId:${flowJournalPlate(plate)}';

  Future<void> _prepare() async {
    final prefs = await SharedPreferences.getInstance();
    await FlowLocalJournal.preserveWorkdayIdentity(prefs);
  }

  Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? prefs.getString('aims_flow_workday_v1');
    if (raw == null || raw.isEmpty) {
      return {'active': false, 'journalVersion': 3, 'states': <String, dynamic>{},
        'pending': <dynamic>[]};
    }
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (data['journalVersion'] == 3) {
        if (data['states'] is! Map || data['pending'] is! List) {
          throw const FormatException('Invalid workday journal');
        }
        return data;
      }
      final state = FlowWorkdayState.fromJson(data);
      return {...state.toJson(), 'journalVersion': 3,
        'states': <String, dynamic>{
          if (state.startedAt != null)
            _ownerKey(state.flowId, state.plate): state.toJson(),
        },
        'pending': <dynamic>[
          if (state.syncPending && state.startedAt != null) state.toJson(),
        ],
      };
    } catch (_) {
      throw StateError('A helyi munkanapnapló nem olvasható. Az adatokat megőriztük.');
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(data))) {
      throw StateError('A munkanap helyi mentése nem sikerült.');
    }
  }

  FlowWorkdayState _current(Map<String, dynamic> data,
      FlowAccountSession? session, String? plate) {
    if (session == null) return FlowWorkdayState.fromJson(data);
    final states = data['states'] as Map;
    final state = states[_ownerKey(session.flowId, plate ?? session.plate)];
    return state is Map
        ? FlowWorkdayState.fromJson(Map<String, dynamic>.from(state))
        : const FlowWorkdayState(active: false);
  }

  Future<FlowWorkdayState> load({FlowAccountSession? session, String? plate}) async {
    await _prepare();
    return FlowLocalJournal.run(() async => _current(await _read(), session, plate));
  }

  Future<int> pendingCount({required FlowAccountSession session}) async {
    await _prepare();
    return FlowLocalJournal.run(() async {
      final data = await _read();
      return (data['pending'] as List).where((item) =>
          item is Map && item['flowId'] == session.flowId).length;
    });
  }

  Future<FlowQueueSummary> queueSummary(FlowAccountSession session) async {
    await _prepare();
    return FlowLocalJournal.run(() async {
      final data = await _read();
      return FlowQueueSummary.fromRecords((data['pending'] as List)
        .map((item) => item is Map ? item : null), session, timeKey: 'startedAt');
    });
  }

  void _validateIdentity(FlowAccountSession session, String plate) {
    if (!RegExp(r'^\d{6}$').hasMatch(session.flowId) ||
        flowJournalPlate(plate).isEmpty ||
        flowJournalPlate(plate) != flowJournalPlate(session.plate)) {
      throw StateError('A munkanaphoz a bejelentkezett sofőr járműve szükséges.');
    }
  }

  Future<void> _record(Map<String, dynamic> data, FlowWorkdayState state) async {
    final value = state.toJson();
    (data['states'] as Map)[_ownerKey(state.flowId, state.plate)] = value;
    final pending = data['pending'] as List;
    pending.removeWhere((item) => (item as Map)['workdayId'] == state.workdayId);
    pending.add(value);
    data.addAll(value); // Compatibility mirror used by the GPS workday gate.
    await _write(data); // Current state and retry queue are one durable write.
  }

  Future<FlowWorkdayState> startIfNeeded({
    required FlowAccountSession session,
    required String plate,
    required int startKm,
    int? jobId,
    DateTime? startedAt,
  }) async {
    _validateIdentity(session, plate);
    if (startKm < 0 || startKm > 5000000) {
      throw StateError('Ellenőrizd a kezdő kilométerértéket.');
    }
    await _prepare();
    await FlowLocalJournal.run(() async {
      final data = await _read();
      final current = _current(data, session, plate);
      if (current.active) {
        data.addAll(current.toJson());
        await _write(data);
        _scheduleTracking(() => _beginTracking(plate));
        return;
      }
      final effectiveStart = (startedAt ?? DateTime.now()).toUtc();
      await _record(data, FlowWorkdayState(
        active: true,
        flowId: session.flowId,
        plate: plate.trim().toUpperCase(),
        workdayId: '${session.flowId}-${DateTime.now().toUtc().microsecondsSinceEpoch}-${jobId ?? 0}',
        startedAt: effectiveStart,
        startKm: startKm,
        startJobId: jobId,
        syncPending: true,
      ));
      _scheduleTracking(() => _beginTracking(plate));
    });
    return flushPending(session: session, plate: plate);
  }

  Future<FlowWorkdayState> finish({
    required FlowAccountSession session,
    required String plate,
    required int endKm,
  }) async {
    _validateIdentity(session, plate);
    await _prepare();
    await FlowLocalJournal.run(() async {
      final data = await _read();
      final current = _current(data, session, plate);
      if (!current.active || current.startedAt == null) return;
      if (endKm < (current.startKm ?? 0) || endKm > 5000000) {
        throw StateError('A záró kilométer nem lehet kisebb a kezdő értéknél.');
      }
      final now = DateTime.now().toUtc();
      if (now.isBefore(current.startedAt!)) {
        throw StateError('A zárás ideje megelőzi a kezdést. Ellenőrizd a telefon óráját.');
      }
      await _record(data, FlowWorkdayState.fromJson({
        ...current.toJson(), 'active': false, 'syncPending': true,
        'finishedAt': now.toIso8601String(), 'endKm': endKm,
      }));
      _scheduleTracking(_endTracking);
    });
    return flushPending(session: session, plate: plate);
  }

  Future<FlowWorkdayState> flushPending({
    required FlowAccountSession session,
    required String plate,
  }) async {
    _validateIdentity(session, plate);
    await _prepare();
    await _syncSerial.run(() => _flush(session, plate));
    return load(session: session, plate: plate);
  }

  Future<void> _flush(FlowAccountSession session, String plate) async {
    final pending = await FlowLocalJournal.run(() async {
      final data = await _read();
      return (data['pending'] as List)
          .map((item) => FlowWorkdayState.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((state) => state.flowId == session.flowId &&
              flowJournalPlate(state.plate).isNotEmpty &&
              flowJournalPlate(state.plate) == flowJournalPlate(plate))
          .toList();
    });
    for (final state in pending) {
      if (state.startedAt == null || state.startKm == null ||
          state.workdayId.isEmpty) continue;
      try {
        if (state.active) {
          await _ops.startWorkday(session: session, workdayId: state.workdayId,
            plate: state.plate, startedAt: state.startedAt!,
            startKm: state.startKm!, jobId: state.startJobId);
        } else {
          if (state.finishedAt == null || state.endKm == null) continue;
          await _ops.finishWorkday(session: session, workdayId: state.workdayId,
            plate: state.plate, finishedAt: state.finishedAt!, endKm: state.endKm!,
            startedAt: state.startedAt, startKm: state.startKm,
            startJobId: state.startJobId);
        }
      } catch (_) {
        break; // Preserve order and retry the original snapshot on reconnection.
      }
      await FlowLocalJournal.run(() async {
        final data = await _read();
        final fingerprint = jsonEncode(state.toJson());
        bool unchanged(dynamic value) => value is Map &&
            jsonEncode(FlowWorkdayState.fromJson(Map<String, dynamic>.from(value)).toJson()) == fingerprint;
        final queue = data['pending'] as List;
        queue.removeWhere(unchanged);
        final states = data['states'] as Map;
        final key = _ownerKey(state.flowId, state.plate);
        final synced = {...state.toJson(), 'syncPending': false};
        if (unchanged(states[key])) states[key] = synced;
        if (unchanged(data)) data.addAll(synced);
        await _write(data);
      });
    }
  }
}
