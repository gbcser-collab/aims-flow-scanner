import 'dart:convert';
import 'flow_http_client.dart';
import 'flow_auth_service.dart';
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
        'https://logistic-aims.hu/api/aims-tracking/driver_ops_v2.php',
  );

  bool get configured =>
      driverOpsUrl.trim().isNotEmpty && FlowAuthService.instance.authenticated;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',

      };

  void _ensureConfigured() {
    if (!configured) {
      throw StateError(
        'FLOW Driver műveleti szerver nincs beállítva. Az adat offline mentve marad.',
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
    throw StateError(
      body['error']?.toString() ??
          body['message']?.toString() ??
          'A FLOW szerver nem elérhető.',
    );
  }

  Future<Map<String, dynamic>> _postJson(Map<String, dynamic> payload) async {
    _ensureConfigured();
    final response = await FlowHttpClient.instance.post(
          Uri.parse(driverOpsUrl),
          headers: _headers,
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
    await _postJson({
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
    await _postJson({
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
    await _postJson({
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
    final body = await _postJson({
      'action': 'service_alerts',
      'plate': plate,
      if (currentKm != null) 'currentKm': currentKm,
    });
    final raw = body['alerts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => FlowServiceAlert.fromJson(
              Map<String, dynamic>.from(item),
            ))
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
    _ensureConfigured();
    final request = http.MultipartRequest('POST', Uri.parse(driverOpsUrl));
    request.headers.addAll({
      'Accept': 'application/json',

    });
    request.fields.addAll({
      'action': 'safety_check',
      'plate': plate,
      'id': id,
      'km': km.toString(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'statuses': jsonEncode(statuses),
    });

    for (final kind in const ['oil', 'coolant', 'tires', 'odometer']) {
      final path = photoPaths[kind]?.trim() ?? '';
      if (path.isEmpty) throw StateError('Hiányzó Safety Check fotó: $kind');
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('A Safety Check fotó nem található: $kind');
      }
      request.files.add(
        await http.MultipartFile.fromPath('photo_$kind', file.path),
      );
    }

    final streamed =
        await FlowHttpClient.instance.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    await _decode(response);
  }
}
