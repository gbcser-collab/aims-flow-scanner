import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aims_locale.dart';

class NativeAuthResult {
  const NativeAuthResult({
    required this.role,
    required this.displayName,
    required this.plate,
    required this.forceCodeChange,
    required this.language,
  });

  final String role;
  final String displayName;
  final String plate;
  final bool forceCodeChange;
  final String language;
}

class NativeRegistrationResult {
  const NativeRegistrationResult({
    required this.message,
    required this.reactivated,
    required this.plate,
  });

  final String message;
  final bool reactivated;
  final String plate;
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
  static const _changeCodeUrl = String.fromEnvironment(
    'AIMS_NATIVE_CHANGE_CODE_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-change-code.php',
  );
  static const _forgotCodeUrl = String.fromEnvironment(
    'AIMS_NATIVE_FORGOT_CODE_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-forgot-code.php',
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
        plate: body['plate']?.toString() ?? '',
        forceCodeChange: body['forceCodeChange'] == true,
        language: body['language']?.toString() ?? 'hu',
      );
    }

    final error = body['error']?.toString() ?? 'login_failed';
    final t = AimsLocaleController.instance.t;
    if (response.statusCode == 429 || error == 'rate_limited') {
      throw StateError(t('too_many_attempts'));
    }
    if (error == 'temp_expired') {
      throw StateError(t('temp_expired'));
    }
    if (response.statusCode == 401 || error == 'invalid_credentials') {
      throw StateError(t('invalid_credentials'));
    }
    throw StateError(t('server_unavailable'));
  }

  Future<void> changeDriverCode({
    required String plate,
    required String currentCode,
    required String newCode,
  }) async {
    final response = await http
        .post(
          Uri.parse(_changeCodeUrl),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'plate': plate.trim().toUpperCase(),
            'currentCode': currentCode.trim().toUpperCase(),
            'newCode': newCode.trim().toUpperCase(),
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
      return;
    }

    final error = body['error']?.toString() ?? '';
    final t = AimsLocaleController.instance.t;
    if (error == 'temp_expired') throw StateError(t('temp_expired'));
    if (error == 'rate_limited') throw StateError(t('too_many_attempts'));
    if (error == 'invalid_credentials') throw StateError(t('invalid_credentials'));
    if (error == 'same_code' || error == 'invalid_payload') {
      throw StateError(t('code_invalid'));
    }
    throw StateError(t('server_unavailable'));
  }

  Future<void> requestForgotCode({required String plate}) async {
    final response = await http
        .post(
          Uri.parse(_forgotCodeUrl),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'plate': plate.trim().toUpperCase()}),
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
      return;
    }
    final t = AimsLocaleController.instance.t;
    if (response.statusCode == 429 || body['error'] == 'rate_limited') {
      throw StateError(t('too_many_attempts'));
    }
    throw StateError(t('server_unavailable'));
  }

  Future<NativeRegistrationResult> register({
    required String companyName,
    required String plate,
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
            'plate': plate.trim().toUpperCase(),
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
        plate: body['plate']?.toString() ?? plate.trim().toUpperCase(),
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
