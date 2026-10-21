import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

String flowJournalPlate(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Serialize local read/modify/write operations; network calls stay outside.
class FlowLocalJournal {
  static Future<void> _tail = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Capture pre-upgrade identity before login/logout replaces the old hints.
  /// A mismatched driver hint must never attribute a legacy day to a new car.
  static Future<void> preserveWorkdayIdentity(SharedPreferences prefs) =>
      run(() async {
        final raw = prefs.getString('aims_flow_workday_v2') ??
            prefs.getString('aims_flow_workday_v1');
        if (raw == null || raw.isEmpty) return;
        Map<String, dynamic> data;
        try {
          data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          return; // Preserve unparseable data for recovery, never overwrite it.
        }
        if (data['journalVersion'] != null || data['startedAt'] == null) return;
        if (data['identityCaptured'] == true) return;
        final id = data['workdayId']?.toString() ?? '';
        final hint = prefs.getString('aims_flow_id') ?? '';
        final owner = RegExp(r'^(\d{6})-').firstMatch(id)?.group(1) ??
            (RegExp(r'^\d{6}$').hasMatch(hint) ? hint : '');
        data['flowId'] = data['flowId'] ?? owner;
        data['plate'] = data['plate'] ??
            (owner.isNotEmpty && owner == hint
                ? prefs.getString('aims_driver_plate') ?? ''
                : '');
        data['identityCaptured'] = true;
        if (!await prefs.setString('aims_flow_workday_v2', jsonEncode(data))) {
          throw StateError('A munkanap helyi mentése nem sikerült.');
        }
      });
}
