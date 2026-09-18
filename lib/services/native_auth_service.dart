import 'dart:convert';

import 'package:http/http.dart' as http;

class NativeAuthResult {
  const NativeAuthResult({
    required this.role,
    required this.displayName,
  });

  final String role;
  final String displayName;
}

class NativeRegistrationResult {
  const NativeRegistrationResult({
    required this.message,
    required this.reactivated,
    required this.username,
  });

  final String message;
  final bool reactivated;
  final String username;
}

class NativeAuthService {
  const NativeAuthService();

  static const _url = String.fromEnvironment(
    'AIMS_NATIVE_AUTH_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-login.php',
  );
  static const _registerUrl = String.fromEnvironment(
    'AIMS_NATIVE_REGISTER_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-register.php',
  );

  Future<NativeAuthResult> login({
    required String login,
    required String password,
    String code = '',
  }) async {
    final response = await http
        .post(
          Uri.parse(_url),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'login': login.trim(),
            'password': password,
            'code': code.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['ok'] == true) {
      return NativeAuthResult(
        role: body['role']?.toString() ?? 'driver',
        displayName: body['displayName']?.toString() ?? login.trim(),
      );
    }

    final error = body['error']?.toString() ?? 'login_failed';
    if (response.statusCode == 429 || error == 'rate_limited') {
      throw StateError('Túl sok sikertelen próbálkozás. Próbáld meg később.');
    }
    if (response.statusCode == 401 || error == 'invalid_credentials') {
      throw StateError('Hibás belépési adatok vagy 2FA kód.');
    }
    throw StateError('A Logistic-AIMS belépési szerver nem érhető el.');
  }

  Future<NativeRegistrationResult> register({
    required String companyName,
    required String country,
    required String contactName,
    required String phone,
    required String email,
    String address = '',
    String taxNumber = '',
    String euVat = '',
    String registryNumber = '',
    String whatsapp = '',
    String viber = '',
    String preferredContact = 'email',
    String language = 'hu',
    bool terms = false,
    bool privacy = false,
  }) async {
    final response = await http
        .post(
          Uri.parse(_registerUrl),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'companyName': companyName.trim(),
            'country': country.trim(),
            'contactName': contactName.trim(),
            'phone': phone.trim(),
            'email': email.trim(),
            'address': address.trim(),
            'taxNumber': taxNumber.trim(),
            'euVat': euVat.trim(),
            'registryNumber': registryNumber.trim(),
            'whatsapp': whatsapp.trim(),
            'viber': viber.trim(),
            'preferredContact': preferredContact,
            'language': language,
            'terms': terms,
            'privacy': privacy,
          }),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['ok'] == true) {
      return NativeRegistrationResult(
        message: body['message']?.toString() ?? 'A regisztráció beérkezett.',
        reactivated: body['reactivated'] == true,
        username: body['username']?.toString() ?? '',
      );
    }

    final message = body['message']?.toString();
    if (message != null && message.isNotEmpty) {
      throw StateError(message);
    }
    if (response.statusCode == 429) {
      throw StateError('Túl sok regisztrációs próbálkozás. Próbáld meg később.');
    }
    throw StateError('A regisztrációs szerver nem érhető el.');
  }
}
