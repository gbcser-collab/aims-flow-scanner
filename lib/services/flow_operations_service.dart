import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'flow_account_service.dart';

class FlowServiceAlert {
  const FlowServiceAlert({
    required this.id,
    required this.title,
    required this.severity,
    this.remainingKm,
    this.dueDate,
    this.detail = '',
  });

  final String id;
  final String title;
  final String severity;
  final int? remainingKm;
  final DateTime? dueDate;
  final String detail;

  bool get urgent =>
      severity == 'overdue' ||
      severity == 'critical' ||
      id == 'hold';

  factory FlowServiceAlert.fromJson(Map<String, dynamic> json) =>
      FlowServiceAlert(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Karbantartás',
        severity: json['severity']?.toString() ?? 'info',
        remainingKm: (json['remainingKm'] as num?)?.toInt(),
        dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
        detail: json['detail']?.toString() ?? '',
      );
}

class FlowOperationsService {
  const FlowOperationsService();

  static const driverOpsUrl = String.fromEnvironment(
    'AIMS_FLOW_DRIVER_OPS_URL',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/session/driver_ops_v2.php',
  );

  bool get configured => driverOpsUrl.trim().isNotEmpty;

  Map<String, String> _headers(
    FlowAccountSession session, {
    bool json = true,
  }) =>
      {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.sessionToken}',
      };

  void _ensureConfigured(FlowAccountSession session) {
    if (!configured ||
        session.isExpired ||
        session.sessionToken.trim().isEmpty) {
      throw StateError(
        'A FLOW munkamenet nem érvényes. Lépj be újra.',
      );
    }
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['ok'] == true) {
      return body;
    }
    final error = body['error']?.toString() ?? '';
    if (response.statusCode == 401 || error == 'invalid_session') {
      throw StateError('A FLOW munkamenet lejárt. Lépj be újra.');
    }
    if (response.statusCode == 403 || error == 'plate_forbidden') {
      throw StateError('Ehhez a járműhöz nincs hozzáférésed.');
    }
    throw StateError(
      error.isNotEmpty
          ? error
          : body['message']?.toString() ?? 'A FLOW szerver nem érhető el.',
    );
  }

  Future<Map<String, dynamic>> _postJson(
    FlowAccountSession session,
    Map<String, dynamic> payload,
  ) async {
    _ensureConfigured(session);
    final response = await http
        .post(
          Uri.parse(driverOpsUrl),
          headers: _headers(session),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 18));
    return _decode(response);
  }

  Future<void> startWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime startedAt,
    required int startKm,
    int? jobId,
  }) async {
    await _postJson(session, {
      'action': 'workday_start',
      'plate': plate,
      'workdayId': workdayId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'startKm': startKm,
      if (jobId != null) 'jobId': jobId,
    });
  }

  Future<void> finishWorkday({
    required FlowAccountSession session,
    required String workdayId,
    required String plate,
    required DateTime finishedAt,
    required int endKm,
    DateTime? startedAt,
    int? startKm,
    int? startJobId,
  }) async {
    await _postJson(session, {
      'action': 'workday_finish',
      'plate': plate,
      'workdayId': workdayId,
      'finishedAt': finishedAt.toUtc().toIso8601String(),
      'endKm': endKm,
      if (startedAt != null)
        'startedAt': startedAt.toUtc().toIso8601String(),
      if (startKm != null) 'startKm': startKm,
      if (startJobId != null) 'jobId': startJobId,
    });
  }

  Future<void> recordOdometer({
    required FlowAccountSession session,
    required String plate,
    required int km,
    required String source,
  }) async {
    await _postJson(session, {
      'action': 'odometer',
      'plate': plate,
      'km': km,
      'source': source,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<FlowServiceAlert>> fetchServiceAlerts({
    required FlowAccountSession session,
    required String plate,
    int? currentKm,
  }) async {
    final body = await _postJson(session, {
      'action': 'service_alerts',
      'plate': plate,
      if (currentKm != null) 'currentKm': currentKm,
    });
    final raw = body['alerts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => FlowServiceAlert.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
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
    _ensureConfigured(session);
    final request = http.MultipartRequest('POST', Uri.parse(driverOpsUrl));
    request.headers.addAll(_headers(session, json: false));
    request.fields.addAll({
      'action': 'safety_check',
      'flowId': session.flowId,
      'plate': plate,
      'id': id,
      'km': km.toString(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'statuses': jsonEncode(statuses),
    });

    for (final kind in const ['oil', 'coolant', 'tires', 'odometer']) {
      final path = photoPaths[kind]?.trim() ?? '';
      if (path.isEmpty) {
        throw StateError('Hiányzó Safety Check fotó: $kind');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('A Safety Check fotó nem található: $kind');
      }
      request.files.add(
        await http.MultipartFile.fromPath('photo_$kind', file.path),
      );
    }

    final streamed =
        await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    await _decode(response);
  }
}

