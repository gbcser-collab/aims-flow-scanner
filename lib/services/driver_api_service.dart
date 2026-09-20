import 'dart:convert';

import 'package:http/http.dart' as http;

class DriverApiException implements Exception {
  const DriverApiException(this.statusCode, this.code);

  final int statusCode;
  final String code;

  bool get retryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() => code;
}

class DriverStop {
  const DriverStop({
    required this.id,
    required this.type,
    required this.order,
    required this.company,
    required this.address,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.arrived,
    required this.completed,
    this.arrivedAt,
    this.completedAt,
  });

  final int id;
  final String type;
  final int order;
  final String company;
  final String address;
  final String phone;
  final double latitude;
  final double longitude;
  final bool arrived;
  final bool completed;
  final String? arrivedAt;
  final String? completedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'order': order,
        'company': company,
        'address': address,
        'phone': phone,
        'latitude': latitude,
        'longitude': longitude,
        'arrived': arrived,
        'completed': completed,
        'arrivedAt': arrivedAt,
        'completedAt': completedAt,
      };

  factory DriverStop.fromJson(Map<String, dynamic> json) => DriverStop(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        company: json['company']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        arrived: json['arrived'] == true,
        completed: json['completed'] == true,
        arrivedAt: json['arrivedAt']?.toString(),
        completedAt: json['completedAt']?.toString(),
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
    this.orderData = const <String, dynamic>{},
  });

  final int id;
  final String reference;
  final String status;
  final List<DriverStop> stops;
  final String? seenAt;
  final String? acceptedAt;
  final Map<String, dynamic> orderData;

  DriverStop? get currentStop {
    for (final stop in stops) {
      if (!stop.completed) return stop;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'reference': reference,
        'status': status,
        'seenAt': seenAt,
        'acceptedAt': acceptedAt,
        'orderData': orderData,
        'stops': [for (final stop in stops) stop.toJson()],
      };

  factory DriverJob.fromJson(Map<String, dynamic> json) => DriverJob(
        id: (json['id'] as num?)?.toInt() ?? 0,
        reference: json['reference']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        seenAt: json['seenAt']?.toString(),
        acceptedAt: json['acceptedAt']?.toString(),
        orderData: json['orderData'] is Map
            ? Map<String, dynamic>.from(json['orderData'] as Map)
            : const <String, dynamic>{},
        stops: ((json['stops'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) => DriverStop.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
            ..sort((a, b) {
              final byOrder = a.order.compareTo(b.order);
              return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
            })),
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

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));
        final body = _decode(response);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return (body['jobs'] as List? ?? const [])
              .whereType<Map>()
              .map((item) =>
                  DriverJob.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }

        final transient = response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!transient || attempt == 2) {
          throw StateError(
            body['error']?.toString() ?? 'HTTP ${response.statusCode}',
          );
        }
        lastError = StateError('HTTP ${response.statusCode}');
      } catch (error) {
        lastError = error;
        if (attempt == 2 || error is StateError) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
    }
    throw StateError(lastError?.toString() ?? 'Hálózati hiba');
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

  Future<void> updateStop({
    required String plate,
    required int stopId,
    required String action,
    String source = 'manual',
    DateTime? occurredAt,
  }) async {
    _ensureConfigured();
    final response = await http
        .post(
          Uri.parse('${_base()}/driver_stop_action.php'),
          headers: _headers,
          body: jsonEncode({
            'plate': plate.trim().toUpperCase(),
            'stopId': stopId,
            'action': action,
            'source': source,
            'occurredAt': occurredAt?.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriverApiException(
        response.statusCode,
        body['error']?.toString() ?? 'HTTP ${response.statusCode}',
      );
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
    String? eventId,
    DateTime? occurredAt,
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
            'eventId': eventId,
            'occurredAt': occurredAt?.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriverApiException(
        response.statusCode,
        body['error']?.toString() ?? 'HTTP ${response.statusCode}',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    } catch (_) {}
    return <String, dynamic>{};
  }
}