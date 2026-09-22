import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'smart_document_classifier.dart';
import 'smart_document_repository.dart';

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

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + _token,
          },
          body: jsonEncode({
            'plate': document.plate.trim().toUpperCase(),
            'localId': document.id,
            'type': document.type.wire,
            'capturedAt': document.createdAt.toUtc().toIso8601String(),
            'ocrText': document.rawText,
            'confidence': document.confidence,
            'image': {
              'mimeType': 'image/jpeg',
              'base64': base64Encode(await file.readAsBytes()),
            },
          }),
        )
        .timeout(const Duration(seconds: 45));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw StateError(
        body['error']?.toString() ?? 'HTTP ${response.statusCode}',
      );
    }

    final documentId = body['documentId']?.toString().trim() ?? '';
    final state = body['state']?.toString().trim() ?? '';
    if (documentId.isEmpty || state != 'uploaded') {
      throw StateError('invalid_smart_document_success_response');
    }

    return SmartDocumentUploadResult(
      documentId: documentId,
      state: state,
    );
  }
}
