import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_account_service.dart';
import 'flow_operations_service.dart';
import 'flow_local_journal.dart';
import 'flow_workday_service.dart';

class FlowSafetyCheckRecord {
  const FlowSafetyCheckRecord({
    required this.id,
    required this.plate,
    required this.km,
    required this.createdAt,
    required this.statuses,
    required this.photoPaths,
    this.synced = false,
    this.flowId = '',
  });

  final String id;
  final String flowId;
  final String plate;
  final int km;
  final DateTime createdAt;
  final Map<String, String> statuses;
  final Map<String, String> photoPaths;
  final bool synced;

  bool get hasProblem =>
      statuses.values.any((value) => value.trim().toLowerCase() != 'ok');

  Map<String, dynamic> toJson() => {
        'id': id,
        'flowId': flowId,
        'plate': plate,
        'km': km,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'statuses': statuses,
        'photoPaths': photoPaths,
        'synced': synced,
      };

  factory FlowSafetyCheckRecord.fromJson(Map<String, dynamic> json) =>
      FlowSafetyCheckRecord(
        id: json['id']?.toString() ?? '',
        flowId: json['flowId']?.toString() ?? '',
        plate: json['plate']?.toString() ?? '',
        km: (json['km'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        statuses: Map<String, String>.unmodifiable(json['statuses'] as Map? ?? const {}),
        photoPaths: Map<String, String>.unmodifiable(json['photoPaths'] as Map? ?? const {}),
        synced: json['synced'] == true,
      );
}

class FlowSafetyCheckService {
  FlowSafetyCheckService({FlowOperationsService operations = const FlowOperationsService()})
      : _ops = operations;
  static final instance = FlowSafetyCheckService();
  static const _recordsKey = 'aims_flow_safety_records_v1';
  final FlowOperationsService _ops;
  Future<void> _syncTail = Future<void>.value();

  String _scheduleKey(FlowAccountSession session) =>
      'aims_flow_safety_next_due_v2:${session.flowId}:${flowJournalPlate(session.plate)}';

  Future<DateTime> _ensureNextDue(FlowAccountSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scheduleKey(session);
    final existing = DateTime.tryParse(prefs.getString(key) ?? '');
    if (existing != null) return existing;
    final due = DateTime.now().toUtc().add(Duration(minutes: 120 + Random.secure().nextInt(181)));
    if (!await prefs.setString(key, due.toIso8601String())) {
      throw StateError('Az ellenőrzés időzítése nem menthető.');
    }
    return due;
  }

  Future<bool> shouldPrompt({
    required FlowAccountSession session,
    required FlowWorkdayState workday,
    required bool hasActiveJob,
    required Position? position,
  }) async {
    if (!workday.active || hasActiveJob || position == null ||
        workday.flowId != session.flowId ||
        flowJournalPlate(workday.plate) != flowJournalPlate(session.plate)) return false;
    final now = DateTime.now().toUtc();
    final age = now.difference(position.timestamp.toUtc());
    if (!position.speed.isFinite || position.speed < 0 || position.speed > 1.2 ||
        !position.accuracy.isFinite || position.accuracy < 0 || position.accuracy > 50 ||
        !position.latitude.isFinite || position.latitude.abs() > 90 ||
        !position.longitude.isFinite || position.longitude.abs() > 180 ||
        age.isNegative || age > const Duration(minutes: 2)) return false;
    if (workday.startedAt == null ||
        now.difference(workday.startedAt!) < const Duration(minutes: 45)) return false;
    final due = await FlowLocalJournal.run(() => _ensureNextDue(session));
    if (now.isBefore(due.toUtc())) return false;
    if (session.baseLatitude != null && session.baseLongitude != null) {
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude,
        session.baseLatitude!, session.baseLongitude!);
      if (distance <= session.baseRadiusMeters) return false;
    }
    return true;
  }

  Future<void> snooze({required FlowAccountSession session}) =>
      FlowLocalJournal.run(() async {
        final prefs = await SharedPreferences.getInstance();
        final due = DateTime.now().toUtc().add(const Duration(minutes: 15));
        if (!await prefs.setString(_scheduleKey(session), due.toIso8601String())) {
          throw StateError('Az ellenőrzés időzítése nem menthető.');
        }
      });

  Future<void> _completeSchedule(FlowAccountSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scheduleKey(session));
    await _ensureNextDue(session);
  }

  Future<List<FlowSafetyCheckRecord>> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.any((item) => item is! Map)) {
        throw const FormatException('Invalid Safety journal');
      }
      return decoded.map((item) => FlowSafetyCheckRecord.fromJson(
        Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      throw StateError('A helyi ellenőrzési napló nem olvasható. Az adatokat megőriztük.');
    }
  }

  bool _belongs(FlowSafetyCheckRecord record, FlowAccountSession session, {bool vehicle = true}) =>
      record.flowId == session.flowId && (!vehicle ||
        flowJournalPlate(record.plate) == flowJournalPlate(session.plate));

  Future<List<FlowSafetyCheckRecord>> recentRecords({int limit = 5, FlowAccountSession? session}) =>
      FlowLocalJournal.run(() async {
        if (limit <= 0) return <FlowSafetyCheckRecord>[];
        final records = await _loadRecords();
        return records.where((r) => session == null || _belongs(r, session))
            .take(limit).toList(growable: false);
      });

  Future<FlowSafetyCheckRecord?> latestRecord({FlowAccountSession? session}) async {
    final records = await recentRecords(limit: 1, session: session);
    return records.isEmpty ? null : records.first;
  }

  Future<int> pendingCount({FlowAccountSession? session}) => FlowLocalJournal.run(() async {
    final records = await _loadRecords();
    return records.where((r) => !r.synced &&
      (session == null || _belongs(r, session, vehicle: false))).length;
  });

  Future<int> unidentifiedPendingCount() => FlowLocalJournal.run(() async {
    final records = await _loadRecords();
    return records.where((r) => !r.synced && r.flowId.isEmpty).length;
  });

  Future<void> _saveRecords(List<FlowSafetyCheckRecord> records) async {
    // Only acknowledged history may be trimmed. Pending and legacy records
    // survive any number of later checks until their own upload is confirmed.
    var history = 0;
    final retained = records.where((r) => !r.synced || history++ < 30).toList();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_recordsKey,
        jsonEncode(retained.map((r) => r.toJson()).toList()))) {
      throw StateError('Az ellenőrzés helyi mentése nem sikerült.');
    }
  }

  Future<void> saveAndSubmit({
    required FlowAccountSession session,
    required String plate,
    required int km,
    required Map<String, String> statuses,
    required Map<String, String> photoPaths,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(session.flowId) ||
        flowJournalPlate(plate).isEmpty ||
        flowJournalPlate(plate) != flowJournalPlate(session.plate)) {
      throw StateError('Az ellenőrzéshez a bejelentkezett sofőr járműve szükséges.');
    }
    if (km < 0 || km > 5000000) throw StateError('Ellenőrizd a kilométeróra-állást.');
    const checks = {'oil', 'coolant', 'tires', 'steering'};
    if (statuses.length != checks.length || !checks.every((key) =>
        statuses[key] == 'ok' || statuses[key] == 'problem')) {
      throw StateError('Mind a négy ellenőrzés eredményét add meg.');
    }
    const photos = {'oil', 'coolant', 'tires', 'odometer'};
    if (!photos.every((key) => (photoPaths[key] ?? '').trim().isNotEmpty)) {
      throw StateError('Az olaj, víz, kerék és kilométeróra fotója kötelező.');
    }
    final now = DateTime.now().toUtc();
    final record = FlowSafetyCheckRecord(
      id: '${session.flowId}-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 20)}',
      flowId: session.flowId, plate: plate.trim().toUpperCase(), km: km, createdAt: now,
      statuses: Map<String, String>.unmodifiable(statuses),
      photoPaths: Map<String, String>.unmodifiable(photoPaths));
    await FlowLocalJournal.run(() async {
      final records = await _loadRecords();
      records.insert(0, record);
      await _saveRecords(records);
      try { await _completeSchedule(session); } catch (_) {
        // The saved check remains valid; retry scheduling on the next prompt.
      }
    });
    try { await flushPending(session: session); } catch (_) {
      // The durable record remains pending if an acknowledgement cannot be saved.
    }
  }

  Future<void> flushPending({required FlowAccountSession session}) {
    final result = _syncTail.then((_) => _flush(session));
    _syncTail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _flush(FlowAccountSession session) async {
    final snapshot = await FlowLocalJournal.run(() => _loadRecords());
    for (final record in snapshot.reversed) {
      // Old records contain no reliable owner: retain them without guessing.
      if (record.synced || !_belongs(record, session)) continue;
      try {
        await _ops.submitSafetyCheck(session: session, id: record.id,
          plate: record.plate, km: record.km, statuses: record.statuses,
          photoPaths: record.photoPaths, createdAt: record.createdAt);
      } catch (_) {
        break;
      }
      await FlowLocalJournal.run(() async {
        // Merge the acknowledgement into the latest journal, never replace a
        // new record that was saved while this HTTP request was in flight.
        final current = await _loadRecords();
        final index = current.indexWhere((r) => r.id == record.id && r.flowId == record.flowId);
        if (index < 0 || current[index].synced) return;
        current[index] = FlowSafetyCheckRecord.fromJson({...current[index].toJson(), 'synced': true});
        await _saveRecords(current);
      });
    }
  }
}
