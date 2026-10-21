import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'flow_account_service.dart';
import 'invoice_parser.dart';

class InvoiceUploadResult {
  const InvoiceUploadResult({required this.invoiceId, this.vignetteId});

  final String invoiceId;
  final String? vignetteId;
}

class InvoiceService {
  const InvoiceService();

  static const _endpoint = String.fromEnvironment(
    'AIMS_INVOICE_ENDPOINT',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/session/vehicle_invoice.php',
  );

  Future<Map<String, String>> _headers() async {
    final session = await FlowSessionStore.instance.load();
    if (session == null || session.isExpired) {
      throw StateError('A FLOW munkamenet lejárt. Lépj be újra.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.sessionToken}',
    };
  }

  Future<InvoiceUploadResult> send({
    required String imagePath,
    required String deviceId,
    required String plate,
    required InvoiceData data,
    String note = '',
    bool createVignette = false,
    String vignetteCountry = '',
    String vignetteType = 'electronic',
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw StateError('A számla képe nem található.');
    }
    final bytes = await file.readAsBytes();
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: await _headers(),
          body: jsonEncode({
            'deviceId': deviceId,
            'plate': plate.trim().toUpperCase(),
            'capturedAt': DateTime.now().toUtc().toIso8601String(),
            'category': data.category.wire,
            'vendor': data.vendor,
            'invoiceDate': data.date,
            'totalAmount': data.totalAmount,
            'currency': data.currency,
            'documentNumber': data.documentNumber,
            'note': note.trim(),
            'ocrText': data.rawText,
            'liters': data.liters,
            'pricePerLiter': data.pricePerLiter,
            'confidence': data.confidence,
            'createVignette': createVignette,
            'vignetteCountry': vignetteCountry.trim().toUpperCase(),
            'vignetteType': vignetteType,
            'validFrom': validFrom?.toUtc().toIso8601String(),
            'validUntil': validUntil?.toUtc().toIso8601String(),
            'image': {
              'mimeType': 'image/jpeg',
              'base64': base64Encode(bytes),
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
        'Számlafeltöltési hiba: '
        '${body['error']?.toString() ?? 'HTTP ${response.statusCode}'}',
      );
    }
    return InvoiceUploadResult(
      invoiceId: body['invoiceId']?.toString() ?? '',
      vignetteId: body['vignetteId']?.toString(),
    );
  }
}
