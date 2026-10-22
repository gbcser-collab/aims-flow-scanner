import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/scan_models.dart';
import '../models/tracking_models.dart';
import 'device_identity_service.dart';
import 'flow_multipart_transport.dart';

class AimsApiException implements Exception {
  const AimsApiException(this.code, this.statusCode, [this.detail]);
  final String code;
  final int statusCode;
  final String? detail;

  bool get retryable => statusCode >= 500 || statusCode == 408 ||
      statusCode == 429 || code == 'invalid_response' || code == 'invalid_cmr_ack';

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

class AimsApiService {
  const AimsApiService({this.baseUrl = 'https://logistic-aims.hu/api',
    this.clientFactory, this.requestTimeout});

  final String baseUrl;
  final http.Client Function()? clientFactory;
  final Duration? requestTimeout;

  Future<http.Response> _send(String method, String path, {
    required Map<String, String> headers, Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final request = http.Request(method, Uri.parse('$baseUrl/$path'));
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return sendFlowMultipart(request, client: clientFactory?.call(),
      timeout: requestTimeout ?? timeout);
  }

  static void validateCmrAcknowledgement(Map<String, dynamic> response, String localId) {
    final id = response['documentId'] ?? response['serverDocumentId'];
    final validId = (id is String && id.trim().isNotEmpty) || (id is num && id > 0);
    if (!validId || !const {'uploaded', 'emailed', 'approved', 'failed'}.contains(response['state']) ||
        response['ok'] == false || response['success'] == false ||
        response['error'] != null ||
        (response['localId'] != null && response['localId'].toString() != localId)) {
      throw const AimsApiException('invalid_cmr_ack', 200,
        'A szerver nem igazolta a dokumentum átvételét. A helyi példány megmaradt.');
    }
  }

  Map<String, String> _authHeaders(DeviceIdentity identity) => {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        'X-AIMS-Device-ID': identity.deviceId,
        'Authorization': 'Bearer ${identity.secret}',
      };

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(response.body);
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AimsApiException(decoded?['error']?.toString() ?? 'http_${response.statusCode}',
        response.statusCode, decoded?['detail']?.toString());
    }
    if (decoded == null || decoded.isEmpty) {
      throw AimsApiException('invalid_response', response.statusCode,
        'A szerver válasza hiányos vagy nem olvasható.');
    }
    if (decoded['ok'] == false || decoded['success'] == false || decoded['error'] != null) {
      throw AimsApiException(decoded['error']?.toString() ?? 'request_rejected',
        response.statusCode, decoded['detail']?.toString());
    }
    return decoded;
  }

  Map<String, dynamic> _deviceResponse(http.Response response) {
    final decoded = _decode(response);
    if (!const {'pending', 'approved', 'revoked'}.contains(decoded['state'])) {
      throw AimsApiException('invalid_response', response.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> enroll(DeviceIdentity identity, {required String label}) async =>
      _deviceResponse(await _send('POST', 'device/enroll',
        headers: const {'content-type': 'application/json; charset=utf-8', 'accept': 'application/json'},
        body: {'deviceId': identity.deviceId, 'secret': identity.secret, 'label': label}));

  Future<Map<String, dynamic>> deviceStatus(DeviceIdentity identity) async =>
      _deviceResponse(await _send('GET', 'device/status', headers: _authHeaders(identity)));

  Future<Map<String, dynamic>> syncCmr(DeviceIdentity identity, ScannedDocument document) async {
    final image = File(document.imagePath);
    if (!await image.exists()) throw const FileSystemException('A mentett CMR-kép nem található.');
    final bytes = await image.readAsBytes();

    Map<String, dynamic>? encodeOptionalFile(String? path, String mimeType) {
      if (path == null || path.trim().isEmpty) return null;
      final file = File(path);
      if (!file.existsSync()) return null;
      return {
        'mimeType': mimeType,
        'base64': base64Encode(file.readAsBytesSync()),
      };
    }

    final payload = <String, dynamic>{
      'localId': document.id,
      'deviceId': identity.deviceId,
      'createdAt': document.createdAt.toUtc().toIso8601String(),
      'cmr': document.cmr.toJson(),
      'qualityScore': document.quality.score,
      'location': document.location?.toJson(),
      // Backwards-compatible full-page JPEG.
      'image': {'mimeType': 'image/jpeg', 'base64': base64Encode(bytes)},
      'pdf': encodeOptionalFile(document.pdfPath, 'application/pdf'),
      'signatureImage': encodeOptionalFile(
        document.signatureImagePath,
        'image/jpeg',
      ),
      'signatureConfidence': document.signatureConfidence,
    };
    final response = _decode(await _send('POST', 'cmr/sync',
      headers: _authHeaders(identity), body: payload,
      timeout: const Duration(seconds: 45)));
    validateCmrAcknowledgement(response, document.id);
    return response;
  }

  Future<Map<String, dynamic>> startTracking(DeviceIdentity identity, TrackingSession session) async =>
      _decode(await _send('POST', 'tracking/start', headers: _authHeaders(identity), body: {
        'tripId': session.id, 'plate': session.plate, 'reference': session.reference,
        'startedAt': session.startedAt.toUtc().toIso8601String(),
      }));

  Future<Map<String, dynamic>> syncTrackingPoints(DeviceIdentity identity,
      TrackingSession session, List<TrackingPoint> points) async =>
      _decode(await _send('POST', 'tracking/points', headers: _authHeaders(identity),
        timeout: const Duration(seconds: 25), body: {
          'tripId': session.id, 'plate': session.plate, 'reference': session.reference,
          'points': points.map((point) => point.toJson()).toList(),
        }));

  Future<Map<String, dynamic>> stopTracking(DeviceIdentity identity, TrackingSession session) async =>
      _decode(await _send('POST', 'tracking/stop', headers: _authHeaders(identity), body: {
        'tripId': session.id,
        'stoppedAt': (session.stoppedAt ?? DateTime.now()).toUtc().toIso8601String(),
      }));
}
