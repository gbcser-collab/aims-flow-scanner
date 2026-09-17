import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/scan_models.dart';
import '../models/tracking_models.dart';
import 'device_identity_service.dart';

class AimsApiException implements Exception {
  const AimsApiException(this.code, this.statusCode, [this.detail]);
  final String code;
  final int statusCode;
  final String? detail;

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

class AimsApiService {
  const AimsApiService({this.baseUrl = 'https://logistic-aims.hu/api'});

  static final http.Client _client = http.Client();

  final String baseUrl;

  Map<String, String> _authHeaders(DeviceIdentity identity) => {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        'X-AIMS-Device-ID': identity.deviceId,
        'Authorization': 'Bearer ${identity.secret}',
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
      throw AimsApiException(
        decoded['error'] as String? ?? 'http_${response.statusCode}',
        response.statusCode,
        decoded['detail']?.toString(),
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> enroll(DeviceIdentity identity, {required String label}) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/device/enroll'),
          headers: const {'content-type': 'application/json; charset=utf-8', 'accept': 'application/json'},
          body: jsonEncode({'deviceId': identity.deviceId, 'secret': identity.secret, 'label': label}),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> deviceStatus(DeviceIdentity identity) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/device/status'), headers: _authHeaders(identity))
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<Map<String, dynamic>> syncCmr(DeviceIdentity identity, ScannedDocument document) async {
    final image = File(document.imagePath);
    if (!await image.exists()) throw const FileSystemException('A mentett CMR-kép nem található.');
    final bytes = await image.readAsBytes();
    final payload = <String, dynamic>{
      'localId': document.id,
      'deviceId': identity.deviceId,
      'createdAt': document.createdAt.toUtc().toIso8601String(),
      'cmr': document.cmr.toJson(),
      'qualityScore': document.quality.score,
      'location': document.location?.toJson(),
      'image': {'mimeType': 'image/jpeg', 'base64': base64Encode(bytes)},
    };
    final response = await _client
        .post(
          Uri.parse('$baseUrl/cmr/sync'),
          headers: _authHeaders(identity),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 45));
    return _decode(response);
  }

  Future<Map<String, dynamic>> startTracking(
    DeviceIdentity identity,
    TrackingSession session,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/tracking/start'),
          headers: _authHeaders(identity),
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

  Future<Map<String, dynamic>> syncTrackingPoints(
    DeviceIdentity identity,
    TrackingSession session,
    List<TrackingPoint> points,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/tracking/points'),
          headers: _authHeaders(identity),
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

  Future<Map<String, dynamic>> stopTracking(
    DeviceIdentity identity,
    TrackingSession session,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/tracking/stop'),
          headers: _authHeaders(identity),
          body: jsonEncode({
            'tripId': session.id,
            'stoppedAt': (session.stoppedAt ?? DateTime.now()).toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }
}
