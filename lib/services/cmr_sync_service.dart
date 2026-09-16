import 'dart:convert';
import 'dart:io';

import '../models/scan_models.dart';
import 'device_identity_service.dart';
import 'scan_repository.dart';

class CmrSyncReport {
  const CmrSyncReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    this.notConfigured = false,
  });

  final int attempted;
  final int succeeded;
  final int failed;
  final bool notConfigured;
}

class CmrSyncService {
  const CmrSyncService({
    this.repository = const ScanRepository(),
    this.deviceIdentity = const DeviceIdentityService(),
  });

  final ScanRepository repository;
  final DeviceIdentityService deviceIdentity;

  static const String _baseUrl = String.fromEnvironment('AIMS_API_BASE_URL', defaultValue: '');
  static const String _deviceToken = String.fromEnvironment('AIMS_DEVICE_TOKEN', defaultValue: '');

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Future<CmrSyncReport> syncPending() async {
    if (!isConfigured) {
      return const CmrSyncReport(attempted: 0, succeeded: 0, failed: 0, notConfigured: true);
    }

    final documents = await repository.documentsNeedingServerSync();
    if (documents.isEmpty) {
      await repository.purgeExpiredApproved();
      return const CmrSyncReport(attempted: 0, succeeded: 0, failed: 0);
    }

    var success = 0;
    var failed = 0;
    for (final document in documents) {
      try {
        if (document.serverDocumentId == null || document.serverDocumentId!.isEmpty) {
          await _upload(document);
        } else {
          await _refreshStatus(document);
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
    return CmrSyncReport(attempted: documents.length, succeeded: success, failed: failed);
  }

  Future<void> _upload(ScannedDocument document) async {
    final file = File(document.imagePath);
    if (!await file.exists()) throw StateError('A CMR-kép nem található a privát app-tárhelyen.');

    final deviceId = await deviceIdentity.getOrCreateId();
    final bytes = await file.readAsBytes();
    final response = await _requestJson(
      method: 'POST',
      path: '/cmr/sync',
      body: {
        'localId': document.id,
        'deviceId': deviceId,
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

  Future<void> _refreshStatus(ScannedDocument document) async {
    final serverId = Uri.encodeQueryComponent(document.serverDocumentId!);
    final localId = Uri.encodeQueryComponent(document.id);
    final response = await _requestJson(
      method: 'GET',
      path: '/cmr/status?serverDocumentId=$serverId&localId=$localId',
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
  }) async {
    final base = _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = method == 'POST' ? await client.postUrl(uri) : await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set('X-AIMS-App', 'AIMS-Flow');
      if (_deviceToken.isNotEmpty) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_deviceToken');
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('AIMS API HTTP ${response.statusCode}: ${text.length > 300 ? text.substring(0, 300) : text}');
      }
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Az AIMS API válasza nem objektum.');
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}
