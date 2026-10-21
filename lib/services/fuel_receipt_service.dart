import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'flow_account_service.dart';
import 'fuel_receipt_parser.dart';

class FuelReceiptService {
  const FuelReceiptService();

  static const _endpoint = String.fromEnvironment(
    'AIMS_FUEL_RECEIPT_ENDPOINT',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/session/fuel_receipt.php',
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

  Future<int> send({
    required String imagePath,
    required String deviceId,
    required String plate,
    required FuelReceiptData data,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw StateError('A bizonylat képe nem található.');
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
            'station': data.station,
            'totalAmount': data.totalAmount,
            'currency': data.currency,
            'liters': data.liters,
            'pricePerLiter': data.pricePerLiter,
            'receiptNumber': data.receiptNumber,
            'ocrText': data.rawText,
            'image': {
              'mimeType': 'image/jpeg',
              'base64': base64Encode(bytes),
            },
          }),
        )
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      final code = body['error']?.toString() ?? 'HTTP ${response.statusCode}';
      throw StateError('Tankolási bizonylat feltöltési hiba: $code');
    }
    return (body['fuelReceiptId'] as num?)?.toInt() ?? 0;
  }
}
