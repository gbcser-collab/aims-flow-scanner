import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_account_service.dart';
import 'flow_operations_service.dart';
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
  });

  final String id;
  final String plate;
  final int km;
  final DateTime createdAt;
  final Map<String, String> statuses;
  final Map<String, String> photoPaths;
  final bool synced;

  Map<String, dynamic> toJson() => {
        'id': id,
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
        plate: json['plate']?.toString() ?? '',
        km: (json['km'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        statuses: Map<String, String>.from(json['statuses'] as Map? ?? const {}),
        photoPaths: Map<String, String>.from(json['photoPaths'] as Map? ?? const {}),
        synced: json['synced'] == true,
      );
}

class FlowSafetyCheckService {
  FlowSafetyCheckService._();
  static final instance = FlowSafetyCheckService._();
  static const _nextDueKey = 'aims_flow_safety_next_due_v1';
  static const _recordsKey = 'aims_flow_safety_records_v1';
  static const _lastCompleteKey = 'aims_flow_safety_last_complete_v1';
  final _ops = const FlowOperationsService();

  Future<DateTime> _ensureNextDue() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = DateTime.tryParse(prefs.getString(_nextDueKey) ?? '');
    if (existing != null) return existing;
    final minutes = 120 + Random.secure().nextInt(181);
    final due = DateTime.now().add(Duration(minutes: minutes));
    await prefs.setString(_nextDueKey, due.toUtc().toIso8601String());
    return due;
  }

  Future<bool> shouldPrompt({
    required FlowAccountSession session,
    required FlowWorkdayState workday,
    required bool hasActiveJob,
    required Position? position,
  }) async {
    if (!workday.active || hasActiveJob || position == null) return false;
    if (position.speed > 1.2) return false;
    if (workday.startedAt == null ||
        DateTime.now().difference(workday.startedAt!) < const Duration(minutes: 45)) {
      return false;
    }
    final due = await _ensureNextDue();
    if (DateTime.now().toUtc().isBefore(due.toUtc())) return false;
    if (session.baseLatitude != null && session.baseLongitude != null) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        session.baseLatitude!,
        session.baseLongitude!,
      );
      if (distance <= session.baseRadiusMeters) return false;
    }
    return true;
  }

  Future<void> snooze() async {
    final prefs = await SharedPreferences.getInstance();
    final due = DateTime.now().add(const Duration(minutes: 15));
    await prefs.setString(_nextDueKey, due.toUtc().toIso8601String());
  }

  Future<void> completeSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastCompleteKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    await prefs.remove(_nextDueKey);
    await _ensureNextDue();
  }

  Future<List<FlowSafetyCheckRecord>> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => FlowSafetyCheckRecord.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveRecords(List<FlowSafetyCheckRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> saveAndSubmit({
    required FlowAccountSession session,
    required String plate,
    required int km,
    required Map<String, String> statuses,
    required Map<String, String> photoPaths,
  }) async {
    const requiredPhotos = {'oil', 'coolant', 'tires', 'odometer'};
    if (!requiredPhotos.every((key) => (photoPaths[key] ?? '').isNotEmpty)) {
      throw StateError('Az olaj, víz, kerék és kilométeróra fotója kötelező.');
    }
    final now = DateTime.now().toUtc();
    final id = '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 20)}';
    var records = await _loadRecords();
    records.insert(
      0,
      FlowSafetyCheckRecord(
        id: id,
        plate: plate,
        km: km,
        createdAt: now,
        statuses: statuses,
        photoPaths: photoPaths,
      ),
    );
    records = records.take(30).toList();
    await _saveRecords(records);
    await completeSchedule();
    await flushPending(session: session);
  }

  Future<void> flushPending({required FlowAccountSession session}) async {
    final records = await _loadRecords();
    var changed = false;
    final updated = <FlowSafetyCheckRecord>[];
    for (final record in records) {
      if (record.synced) {
        updated.add(record);
        continue;
      }
      try {
        await _ops.submitSafetyCheck(
          session: session,
          id: record.id,
          plate: record.plate,
          km: record.km,
          statuses: record.statuses,
          photoPaths: record.photoPaths,
          createdAt: record.createdAt,
        );
        updated.add(
          FlowSafetyCheckRecord(
            id: record.id,
            plate: record.plate,
            km: record.km,
            createdAt: record.createdAt,
            statuses: record.statuses,
            photoPaths: record.photoPaths,
            synced: true,
          ),
        );
        changed = true;
      } catch (_) {
        updated.add(record);
      }
    }
    if (changed) await _saveRecords(updated);
  }
}
