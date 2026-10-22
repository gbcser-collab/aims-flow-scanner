import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'flow_account_service.dart';
import 'flow_local_journal.dart';
import 'flow_multipart_transport.dart';
import 'smart_document_classifier.dart';
import 'smart_document_repository.dart';

class SmartDocumentUploadException implements Exception {
  const SmartDocumentUploadException(
    this.code, {
    this.statusCode,
    this.retryable = false,
  });

  final String code;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => statusCode == null ? code : '$code ($statusCode)';
}

class SmartDocumentUploadResult {
  const SmartDocumentUploadResult({
    required this.documentId,
    required this.state,
  });

  final String documentId;
  final String state;
}

class SmartDocumentService {
  const SmartDocumentService({this.loadSession, this.clientFactory,
    this.requestTimeout = const Duration(seconds: 35)});
  final Future<FlowAccountSession?> Function()? loadSession;
  final http.Client Function()? clientFactory;
  final Duration requestTimeout;

  Future<FlowAccountSession> _sessionFor(PendingSmartDocument document, {String? token}) async {
    if (!RegExp(r'^\d{6}$').hasMatch(document.flowId) || flowJournalPlate(document.plate).isEmpty) {
      throw const SmartDocumentUploadException('owner_unidentified');
    }
    final session = await (loadSession ?? FlowSessionStore.instance.load)();
    if (session == null || session.isExpired) {
      throw const SmartDocumentUploadException('invalid_session');
    }
    if (session.flowId != document.flowId ||
        flowJournalPlate(session.plate) != flowJournalPlate(document.plate)) {
      throw const SmartDocumentUploadException('owner_mismatch');
    }
    if (token != null && session.sessionToken != token) {
      throw const SmartDocumentUploadException('session_changed');
    }
    return session;
  }

  static const _endpoint = String.fromEnvironment(
    'AIMS_SMART_DOCUMENT_ENDPOINT',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/session/smart_document.php',
  );

  Future<SmartDocumentUploadResult> send(PendingSmartDocument document) async {
    final original = await _sessionFor(document);
    final file = File(document.imagePath);
    if (!await file.exists()) {
      throw const SmartDocumentUploadException('image_missing');
    }

    final size = await file.length();
    if (size < 1024 || size > 12 * 1024 * 1024) {
      throw const SmartDocumentUploadException('invalid_image_size');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != size) throw const SmartDocumentUploadException('image_changed');

    final payload = jsonEncode({
      'plate': document.plate.trim().toUpperCase(),
      'localId': document.id,
      'flowId': document.flowId,
      'type': document.type.wire,
      'capturedAt': document.createdAt.toUtc().toIso8601String(),
      'ocrText': document.rawText,
      'confidence': document.confidence,
      'image': {
        'mimeType': 'image/jpeg',
        'base64': base64Encode(bytes),
      },
    });

    try {
      // Freeze credentials for this attempt. Never reuse a retry under a new login.
      final session = await _sessionFor(document, token: original.sessionToken);
      final request = http.Request('POST', Uri.parse(_endpoint))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.sessionToken}',
          'X-AIMS-Idempotency-Key': document.id,
        })
        ..body = payload;
      final response = await sendFlowMultipart(request,
        client: clientFactory?.call(), timeout: requestTimeout);
      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      final retryableStatus = response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500;
      if (response.statusCode < 200 || response.statusCode >= 300 || body['ok'] != true) {
        throw SmartDocumentUploadException(body['error']?.toString() ?? 'invalid_response',
          statusCode: response.statusCode,
          retryable: retryableStatus || (response.statusCode >= 200 && response.statusCode < 300));
      }
      final documentId = body['documentId']?.toString().trim() ?? '';
      final state = body['state']?.toString().trim() ?? '';
      final rawId = body['documentId'];
      final validId = rawId is String || (rawId is int && rawId > 0);
      if (documentId.isEmpty || state != 'uploaded' || !validId ||
          (body['localId'] != null && body['localId'].toString() != document.id)) {
        throw const SmartDocumentUploadException('invalid_smart_document_success_response', retryable: true);
      }
      await _sessionFor(document, token: original.sessionToken);
      return SmartDocumentUploadResult(documentId: documentId, state: state);
    } on SmartDocumentUploadException {
      rethrow;
    } on TimeoutException {
      throw const SmartDocumentUploadException('upload_timeout', retryable: true);
    } on SocketException {
      throw const SmartDocumentUploadException('network_unavailable', retryable: true);
    } on http.ClientException {
      throw const SmartDocumentUploadException('network_unavailable', retryable: true);
    }
  }
}
