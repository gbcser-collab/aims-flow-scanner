import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/scan_models.dart';
import 'device_identity_service.dart';
import 'scan_repository.dart';

enum AimsDeviceState { unknown, pending, approved, revoked, unreachable }

AimsDeviceState _deviceStateFromText(Object? value) {
  switch (value?.toString().toLowerCase()) {
    case 'pending':
      return AimsDeviceState.pending;
    case 'approved':
      return AimsDeviceState.approved;
    case 'revoked':
      return AimsDeviceState.revoked;
    default:
      return AimsDeviceState.unknown;
  }
}

class CmrSyncReport {
  const CmrSyncReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    this.notConfigured = false,
    this.deviceState = AimsDeviceState.unknown,
    this.deviceId,
  });

  final int attempted;
  final int succeeded;
  final int failed;
  final bool notConfigured;
  final AimsDeviceState deviceState;
  final String? deviceId;
}

class _AimsApiException implements Exception {
  const _AimsApiException(this.statusCode, this.code);
  final int statusCode;
  final String code;

  @override
  String toString() => 'AIMS API HTTP $statusCode: $code';
}

class CmrSyncService {
  const CmrSyncService({
    this.repository = const ScanRepository(),
    this.deviceIdentity = const DeviceIdentityService(),
  });

  final ScanRepository repository;
  final DeviceIdentityService deviceIdentity;

  static const String _baseUrl = String.fromEnvironment('AIMS_API_BASE_URL', defaultValue: '');
  static const bool _e2eTestMode = bool.fromEnvironment('AIMS_E2E_TEST_MODE', defaultValue: false);

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<CmrSyncReport> syncPending() async {
    final credentials = await deviceIdentity.getOrCreateCredentials();
    if (_e2eTestMode) {
      return CmrSyncReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        deviceState: AimsDeviceState.approved,
        deviceId: credentials.id,
      );
    }
    if (!isConfigured) {
      return CmrSyncReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        notConfigured: true,
        deviceState: AimsDeviceState.unknown,
        deviceId: credentials.id,
      );
    }

    final deviceState = await _ensureEnrollment(credentials);
    if (deviceState != AimsDeviceState.approved) {
      await repository.purgeExpiredApproved();
      return CmrSyncReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        deviceState: deviceState,
        deviceId: credentials.id,
      );
    }

    final documents = await repository.documentsNeedingServerSync();
    if (documents.isEmpty) {
      await repository.purgeExpiredApproved();
      return CmrSyncReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        deviceState: deviceState,
        deviceId: credentials.id,
      );
    }

    var success = 0;
    var failed = 0;
    for (final document in documents) {
      try {
        if (document.serverDocumentId == null || document.serverDocumentId!.isEmpty) {
          await _upload(document, credentials);
        } else {
          await _refreshStatus(document, credentials);
        }
        success++;
      } catch (error) {
        failed++;
        try {
          await repository.markSyncError(document.id, error);
        } catch (_) {}
      }
    }
    await repository.purgeExpiredApproved();
    return CmrSyncReport(
      attempted: documents.length,
      succeeded: success,
      failed: failed,
      deviceState: deviceState,
      deviceId: credentials.id,
    );
  }

  Future<AimsDeviceState> _ensureEnrollment(DeviceCredentials credentials) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/device/enroll',
        body: {
          'deviceId': credentials.id,
          'secret': credentials.secret,
          'label': 'AIMS Flow • ${Platform.operatingSystem}',
        },
      );
      return _deviceStateFromText(response['state']);
    } on SocketException {
      return AimsDeviceState.unreachable;
    } on TimeoutException {
      return AimsDeviceState.unreachable;
    } on HttpException {
      return AimsDeviceState.unreachable;
    } on _AimsApiException catch (error) {
      if (error.code == 'device_revoked') return AimsDeviceState.revoked;
      if (error.code == 'device_pending') return AimsDeviceState.pending;
      return AimsDeviceState.unreachable;
    } catch (_) {
      return AimsDeviceState.unreachable;
    }
  }

  Future<void> _upload(ScannedDocument document, DeviceCredentials credentials) async {
    final file = File(document.imagePath);
    if (!await file.exists()) throw StateError('A CMR-kép nem található a privát app-tárhelyen.');

    final bytes = await file.readAsBytes();
    final response = await _requestJson(
      method: 'POST',
      path: '/cmr/sync',
      credentials: credentials,
      body: {
        'localId': document.id,
        'deviceId': credentials.id,
        'createdAt': document.createdAt.toUtc().toIso8601String(),
        'cmr': document.cmr.toJson(),
        'qualityScore': document.quality.score,
        'image': {
          'fileName': 'cmr_${document.id}.jpg',
          'mimeType': 'image/jpeg',
          'base64': base64Encode(bytes),
        },
      },
    );
    await _applyServerState(document.id, response);
  }

  Future<void> _refreshStatus(ScannedDocument document, DeviceCredentials credentials) async {
    final serverId = Uri.encodeQueryComponent(document.serverDocumentId!);
    final localId = Uri.encodeQueryComponent(document.id);
    final response = await _requestJson(
      method: 'GET',
      path: '/cmr/status?serverDocumentId=$serverId&localId=$localId',
      credentials: credentials,
    );
    await _applyServerState(document.id, response);
  }

  Future<void> _applyServerState(String localId, Map<String, dynamic> response) async {
    final serverDocumentId = response['serverDocumentId']?.toString();
    final state = response['state']?.toString().toLowerCase() ?? 'uploaded';

    DateTime? parseDate(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text)?.toLocal();
    }

    if (serverDocumentId != null && serverDocumentId.isNotEmpty) {
      await repository.markUploaded(
        localId,
        serverDocumentId: serverDocumentId,
        uploadedAt: parseDate(response['uploadedAt']),
      );
    }

    if (state == 'emailed' || state == 'approved') {
      await repository.markEmailed(localId, emailedAt: parseDate(response['emailedAt']));
    }
    if (state == 'approved') {
      await repository.markApproved(localId, approvedAt: parseDate(response['approvedAt']));
    }
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    DeviceCredentials? credentials,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
      final request = method == 'POST' ? await client.postUrl(uri) : await client.getUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (credentials != null) {
        request.headers.set('X-AIMS-Device-ID', credentials.id);
        request.headers.set('X-AIMS-Device-Secret', credentials.secret);
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 24));
      final payload = await utf8.decoder.bind(response).join();
      Map<String, dynamic> json = const {};
      if (payload.trim().isNotEmpty) {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _AimsApiException(response.statusCode, json['error']?.toString() ?? 'request_failed');
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }
}
