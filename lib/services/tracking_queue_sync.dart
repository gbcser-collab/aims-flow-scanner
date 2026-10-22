import 'dart:convert';

import 'package:http/http.dart' as http;

import 'flow_account_service.dart';
import 'roaming_resilience.dart';
import 'tracking_point_queue.dart';

class TrackingSyncResult {
  const TrackingSyncResult({this.sent = 0, this.more = false,
    this.error, this.retryAfter});
  final int sent;
  final bool more;
  final String? error;
  final Duration? retryAfter;
}

/// Sends only the original owner's points, retaining other accounts and
/// unidentified legacy records without blocking the current driver's queue.
class TrackingQueueSync {
  const TrackingQueueSync({required this.queue, required this.loadSession,
    required this.send, this.batchSize = 40});

  final TrackingPointQueue queue;
  final Future<FlowAccountSession?> Function() loadSession;
  final Future<http.Response> Function(FlowAccountSession, Map<String, dynamic>) send;
  final int batchSize;

  static Map<String, dynamic>? decode(String line) {
    try {
      final value = jsonDecode(line);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static bool belongsTo(Map<String, dynamic> point, FlowAccountSession session) =>
      point['flowId'] == session.flowId &&
      RoamingResilience.queueBelongsToVehicle(point, session.plate);

  Future<TrackingSyncResult> run() async {
    final lines = await queue.snapshot();
    if (lines.isEmpty) return const TrackingSyncResult();
    final session = await loadSession();
    if (session == null || session.isExpired) {
      return const TrackingSyncResult(
        error: 'A GPS-pontok helyben várakoznak. Jelentkezz be újra.',
        retryAfter: Duration(minutes: 5));
    }
    var sent = 0;
    var attempted = 0;
    var held = false;
    var archived = 0;
    final consumed = <String>[];
    try {
    for (final line in lines) {
      final payload = decode(line);
      if (payload == null) {
        await queue.quarantine(line, 'invalid_json');
        archived++;
        consumed.add(line);
        continue;
      }
      if (!belongsTo(payload, session)) {
        held = true;
        continue;
      }
      if (attempted >= batchSize) return TrackingSyncResult(sent: sent, more: true);
      // Never continue using a captured token after logout/account switch.
      final current = await loadSession();
      if (current == null || current.isExpired ||
          current.sessionToken != session.sessionToken ||
          current.flowId != session.flowId ||
          !belongsTo(payload, current)) {
        return TrackingSyncResult(sent: sent, more: true);
      }
      attempted++;
      final captured = DateTime.tryParse(payload['timestamp']?.toString() ?? '');
      final now = DateTime.now().toUtc();
      payload['sentAt'] = now.toIso8601String();
      payload['delayed'] = captured != null && RoamingResilience.isDelayed(captured, now);
      // Preserve plate, device and owner from the durable record verbatim.
      http.Response response;
      try {
        response = await send(current, payload);
      } catch (_) {
        return TrackingSyncResult(sent: sent,
          error: 'Nincs kapcsolat. A GPS-pontok biztonságosan helyben maradnak.',
          retryAfter: Duration.zero);
      }
      final body = decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 &&
          body?['ok'] == true && body?['registeredVehicle'] == true) {
        consumed.add(line);
        sent++;
        continue;
      }
      if (response.statusCode == 400 || response.statusCode == 422 ||
          (response.statusCode == 409 && body?['error'] == 'point_identity_conflict')) {
        await queue.quarantine(line, 'server_rejected_${response.statusCode}');
        archived++;
        consumed.add(line);
        continue;
      }
      final denied = response.statusCode == 401 || response.statusCode == 403;
      return TrackingSyncResult(sent: sent,
        error: denied
          ? 'A FLOW hozzáférés ellenőrzése szükséges. A GPS-pontok helyben maradnak.'
          : 'A szerver nem igazolta vissza a GPS-pontot. Újrapróbálásra vár.',
        retryAfter: denied ? const Duration(minutes: 5) : Duration.zero);
    }
    return TrackingSyncResult(sent: sent, error: archived > 0
      ? 'Hibás GPS-bejegyzés külön megőrzésre került; irodai ellenőrzés szükséges.'
      : held
      ? 'Másik sofőr vagy azonosításra váró korábbi GPS-adat maradt a telefonon.'
      : null);
    } finally {
      // One durable rewrite per batch, merging with points saved during HTTP.
      await queue.acknowledge(consumed);
    }
  }
}
