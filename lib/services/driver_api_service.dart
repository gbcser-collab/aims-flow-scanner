import 'dart:convert';

import 'package:http/http.dart' as http;

class DriverStop {
  const DriverStop({
    required this.id,
    required this.type,
    required this.order,
    required this.company,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.arrived,
  });

  final int id;
  final String type;
  final int order;
  final String company;
  final String address;
  final double latitude;
  final double longitude;
  final bool arrived;

  factory DriverStop.fromJson(Map<String, dynamic> json) => DriverStop(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        company: json['company']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        arrived: json['arrived'] == true,
      );
}

class DriverJob {
  const DriverJob({
    required this.id,
    required this.reference,
    required this.status,
    required this.stops,
    this.seenAt,
    this.acceptedAt,
  });

  final int id;
  final String reference;
  final String status;
  final List<DriverStop> stops;
  final String? seenAt;
  final String? acceptedAt;

  DriverStop? get currentStop {
    for (final stop in stops) {
      if (!stop.arrived) return stop;
    }
    return stops.isEmpty ? null : stops.last;
  }

  factory DriverJob.fromJson(Map<String, dynamic> json) => DriverJob(
        id: (json['id'] as num?)?.toInt() ?? 0,
        reference: json['reference']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        seenAt: json['seenAt']?.toString(),
        acceptedAt: json['acceptedAt']?.toString(),
        stops: (json['stops'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => DriverStop.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class DriverApiService {
  const DriverApiService();

  static const _baseUrl = String.fromEnvironment(
    'AIMS_TRACKING_BASE_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-tracking',
  );
  static const _token =
      String.fromEnvironment('AIMS_TRACKING_TOKEN', defaultValue: '');

  String _base() => _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  void _ensureConfigured() {
    if (_token.trim().isEmpty) {
      throw StateError('Az AIMS Flow szerverkulcs nincs beállítva.');
    }
  }

  Future<List<DriverJob>> fetchJobs(String plate) async {
    _ensureConfigured();
    final normalized = plate.trim().toUpperCase();
    final uri = Uri.parse(
      '${_base()}/driver_jobs.php?plate=${Uri.encodeQueryComponent(normalized)}',
    );
    final response =
        await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error']?.toString() ?? 'HTTP ${response.statusCode}');
    }
    return (body['jobs'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => DriverJob.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> acknowledge({
    required String plate,
    required int jobId,
    required String action,
  }) async {
    _ensureConfigured();
    final response = await http
        .post(
          Uri.parse('${_base()}/driver_job_ack.php'),
          headers: _headers,
          body: jsonEncode({
            'plate': plate.trim().toUpperCase(),
            'jobId': jobId,
            'action': action,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error']?.toString() ?? 'HTTP ${response.statusCode}');
    }
  }

  Future<void> registerPush({
    required String plate,
    required String deviceId,
    required String fcmToken,
  }) async {
    _ensureConfigured();
    final response = await http
        .post(
          Uri.parse('${_base()}/driver_push_device.php'),
          headers: _headers,
          body: jsonEncode({
            'plate': plate.trim().toUpperCase(),
            'deviceId': deviceId,
            'fcmToken': fcmToken,
            'platform': 'android',
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error']?.toString() ?? 'HTTP ${response.statusCode}');
    }
  }

  Future<void> sendSignal({
    required String plate,
    required String type,
    String? message,
    double? latitude,
    double? longitude,
    bool urgent = false,
  }) async {
    _ensureConfigured();
    final response = await http
        .post(
          Uri.parse('${_base()}/driver_event.php'),
          headers: _headers,
          body: jsonEncode({
            'plate': plate.trim().toUpperCase(),
            'type': type,
            'message': message?.trim(),
            'urgent': urgent,
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error']?.toString() ?? 'HTTP ${response.statusCode}');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final parsed = jsonDecode(response.body);
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return <String, dynamic>{};
  }
}
