import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminResetRequest {
  const AdminResetRequest({
    required this.plate,
    required this.email,
    required this.language,
    required this.requestedAt,
  });

  final String plate;
  final String email;
  final String language;
  final String requestedAt;

  factory AdminResetRequest.fromJson(Map<String, dynamic> json) {
    return AdminResetRequest(
      plate: json['plate']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      language: json['language']?.toString() ?? 'hu',
      requestedAt: json['requestedAt']?.toString() ?? '',
    );
  }
}

class AdminResetService {
  const AdminResetService();

  static const _url = String.fromEnvironment(
    'AIMS_ADMIN_RESETS_URL',
    defaultValue:
        'https://logistic-aims.hu/api/aims-flow-admin-driver-resets.php',
  );

  Future<List<AdminResetRequest>> fetchPending({
    required String sessionToken,
  }) async {
    final token = sessionToken.trim();
    if (token.isEmpty) {
      throw StateError('Az admin munkamenet lejárt. Jelentkezz be újra.');
    }

    final response = await http.get(
      Uri.parse(_url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 15));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode == 401) {
      throw StateError('Az admin munkamenet lejárt. Jelentkezz be újra.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw StateError('A kód-visszaállítási kérelmek nem tölthetők be.');
    }

    final rows = body['requests'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => AdminResetRequest.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .where((row) => row.plate.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> approve({
    required String sessionToken,
    required String plate,
  }) async {
    final token = sessionToken.trim();
    if (token.isEmpty) {
      throw StateError('Az admin munkamenet lejárt. Jelentkezz be újra.');
    }

    final response = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'action': 'approve_reset',
            'plate': plate.trim().toUpperCase(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode == 401) {
      throw StateError('Az admin munkamenet lejárt. Jelentkezz be újra.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      final message = body['message']?.toString().trim() ?? '';
      throw StateError(
        message.isEmpty ? 'A kód-visszaállítás nem hagyható jóvá.' : message,
      );
    }
  }
}
