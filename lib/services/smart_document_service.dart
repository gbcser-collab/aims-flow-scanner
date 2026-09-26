import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
  const SmartDocumentService();

  static const _endpoint = String.fromEnvironment(
    'AIMS_SMART_DOCUMENT_ENDPOINT',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/smart_document.php',
  );
  static const _token =
      String.fromEnvironment('AIMS_TRACKING_TOKEN', defaultValue: '');

  Future<SmartDocumentUploadResult> send(
    PendingSmartDocument document,
  ) async {
    if (_token.trim().isEmpty) {
      throw StateError('Az AIMS Flow szerverkulcs nincs beállítva.');
    }
    if (document.plate.trim().isEmpty) {
      throw StateError('A dokumentumhoz nincs rendszám rendelve.');
    }

    final file = File(document.imagePath);
    if (!await file.exists()) {
      throw StateError('A dokumentum képe nem található.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 1024) {
      throw StateError('A dokumentum képfájlja sérült vagy üres.');
    }

    final payload = jsonEncode({
      'plate': document.plate.trim().toUpperCase(),
      'localId': document.id,
      'type': document.type.wire,
      'capturedAt': document.createdAt.toUtc().toIso8601String(),
      'ocrText': document.rawText,
      'confidence': document.confidence,
      'image': {
        'mimeType': 'image/jpeg',
        'base64': base64Encode(bytes),
      },
    });

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_token',
                'X-AIMS-Idempotency-Key': document.id,
              },
              body: payload,
            )
            .timeout(const Duration(seconds: 35));

        Map<String, dynamic> body = const {};
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {}

        final retryableStatus =
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;

        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            body['ok'] != true) {
          final error = SmartDocumentUploadException(
            body['error']?.toString() ?? 'HTTP_${response.statusCode}',
            statusCode: response.statusCode,
            retryable: retryableStatus,
          );
          lastError = error;
          if (!error.retryable || attempt == 1) throw error;
        } else {
          final documentId = body['documentId']?.toString().trim() ?? '';
          final state = body['state']?.toString().trim() ?? '';
          if (documentId.isEmpty || state != 'uploaded') {
            throw const SmartDocumentUploadException(
              'invalid_smart_document_success_response',
            );
          }
          return SmartDocumentUploadResult(
            documentId: documentId,
            state: state,
          );
        }
      } on SmartDocumentUploadException {
        rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == 1) {
          throw const SmartDocumentUploadException(
            'upload_timeout',
            retryable: true,
          );
        }
      } on SocketException catch (error) {
        lastError = error;
        if (attempt == 1) {
          throw const SmartDocumentUploadException(
            'network_unavailable',
            retryable: true,
          );
        }
      } catch (error) {
        lastError = error;
        if (attempt == 1) {
          throw SmartDocumentUploadException(
            'upload_failed: $error',
            retryable: true,
          );
        }
      }

      await Future<void>.delayed(
        Duration(milliseconds: 600 * (attempt + 1)),
      );
    }

    throw SmartDocumentUploadException(
      'upload_failed: ${lastError ?? 'unknown'}',
      retryable: true,
    );
  }
}
