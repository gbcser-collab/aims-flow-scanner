import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tracking_models.dart';
import 'device_identity_service.dart';

class TrackingApiException implements Exception {
  const TrackingApiException(this.code, this.statusCode, [this.detail]);
  final String code;
  final int statusCode;
  final String? detail;

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

class TrackingApiService {
  const TrackingApiService({this.baseUrl = const String.fromEnvironment('AIMS_API_BASE_URL', defaultValue: 'https://logistic-aims.hu/api')});

  final String baseUrl;

  Map<String, String> _headers(DeviceCredentials credentials) => {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        'X-AIMS-Device-ID': credentials.id,
        'Authorization': 'Bearer ${credentials.secret}',
      };

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackingApiException(
        decoded['error'] as String? ?? 'http_${response.statusCode}',
        response.statusCode,
        decoded['detail']?.toString(),
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> enroll(DeviceCredentials credentials, {required String label}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/device/enroll'),
          headers: const {'content-type': 'application/json; charset=utf-8', 'accept': 'application/json'},
          body: jsonEncode({'deviceId': credentials.id, 'secret': credentials.secret, 'label': label}),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> deviceStatus(DeviceCredentials credentials) async {
    final response = await http.get(Uri.parse('$baseUrl/device/status'), headers: _headers(credentials)).timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> startTracking(DeviceCredentials credentials, TrackingSession session) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/tracking/start'),
          headers: _headers(credentials),
          body: jsonEncode({
            'tripId': session.id,
            'plate': session.plate,
            'reference': session.reference,
            'startedAt': session.startedAt.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> syncPoints(DeviceCredentials credentials, TrackingSession session, List<TrackingPoint> points) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/tracking/points'),
          headers: _headers(credentials),
          body: jsonEncode({
            'tripId': session.id,
            'plate': session.plate,
            'reference': session.reference,
            'points': points.map((point) => point.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 25));
    return _decode(response);
  }

  Future<Map<String, dynamic>> stopTracking(DeviceCredentials credentials, TrackingSession session) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/tracking/stop'),
          headers: _headers(credentials),
          body: jsonEncode({
            'tripId': session.id,
            'stoppedAt': (session.stoppedAt ?? DateTime.now()).toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }
}
