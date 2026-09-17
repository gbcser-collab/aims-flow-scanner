import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LocalAuthService extends ChangeNotifier {
  LocalAuthService._();

  static final LocalAuthService instance = LocalAuthService._();
  static const bool _e2eBypass = bool.fromEnvironment('AIMS_E2E_BYPASS_AUTH', defaultValue: false);

  bool _authenticated = _e2eBypass;
  bool get authenticated => _authenticated;

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    return File('${root.path}/aims_local_auth.json');
  }

  Future<Map<String, dynamic>?> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<bool> isConfigured() async => (await _read())?['enabled'] == true;

  Future<String> beginSetup({required String username, required String password}) async {
    final cleanUser = username.trim();
    if (cleanUser.length < 3) throw const FormatException('A felhasználónév legalább 3 karakter legyen.');
    if (password.length < 8) throw const FormatException('A jelszó legalább 8 karakter legyen.');

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final secret = List<int>.generate(20, (_) => random.nextInt(256));
    final passwordHash = _pbkdf2(password, salt, 60000);
    final secretText = _base32Encode(secret);
    final file = await _file();
    await file.writeAsString(jsonEncode({
      'username': cleanUser,
      'salt': base64Encode(salt),
      'passwordHash': base64Encode(passwordHash),
      'totpSecret': secretText,
      'enabled': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }), flush: true);
    return secretText;
  }

  Future<void> confirmSetup(String code) async {
    final data = await _read();
    if (data == null) throw const FormatException('Nincs folyamatban lévő beállítás.');
    final secret = data['totpSecret']?.toString() ?? '';
    if (!_verifyTotp(secret, code)) throw const FormatException('A 2FA kód nem megfelelő.');
    data['enabled'] = true;
    final file = await _file();
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<bool> login({required String username, required String password, required String code}) async {
    if (_e2eBypass) {
      _authenticated = true;
      notifyListeners();
      return true;
    }
    final data = await _read();
    if (data == null || data['enabled'] != true) return false;
    if (data['username']?.toString().trim().toLowerCase() != username.trim().toLowerCase()) return false;
    final salt = base64Decode(data['salt']?.toString() ?? '');
    final expected = base64Decode(data['passwordHash']?.toString() ?? '');
    final actual = _pbkdf2(password, salt, 60000);
    if (!_constantEquals(expected, actual)) return false;
    if (!_verifyTotp(data['totpSecret']?.toString() ?? '', code)) return false;
    _authenticated = true;
    notifyListeners();
    return true;
  }

  void logout() {
    _authenticated = _e2eBypass;
    notifyListeners();
  }

  String otpauthUri(String username, String secret) {
    final label = Uri.encodeComponent('AIMS Flow:$username');
    return 'otpauth://totp/$label?secret=$secret&issuer=AIMS%20Flow&digits=6&period=30';
  }

  bool _verifyTotp(String secret, String input) {
    final normalized = input.replaceAll(RegExp(r'\D'), '');
    if (normalized.length != 6) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;
    for (var drift = -1; drift <= 1; drift++) {
      if (_totp(secret, now + drift) == normalized) return true;
    }
    return false;
  }

  String _totp(String secret, int counter) {
    final key = _base32Decode(secret);
    final bytes = List<int>.filled(8, 0);
    var value = counter;
    for (var i = 7; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    final digest = Hmac(sha1, key).convert(bytes).bytes;
    final offset = digest.last & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    return (binary % 1000000).toString().padLeft(6, '0');
  }

  List<int> _pbkdf2(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final result = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  bool _constantEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff == 0;
  }

  String _base32Encode(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0;
    var bitsLeft = 0;
    final out = StringBuffer();
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        out.write(alphabet[(buffer >> (bitsLeft - 5)) & 31]);
        bitsLeft -= 5;
      }
    }
    if (bitsLeft > 0) out.write(alphabet[(buffer << (5 - bitsLeft)) & 31]);
    return out.toString();
  }

  List<int> _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0;
    var bitsLeft = 0;
    final out = <int>[];
    for (final rune in input.toUpperCase().replaceAll('=', '').runes) {
      final index = alphabet.indexOf(String.fromCharCode(rune));
      if (index < 0) continue;
      buffer = (buffer << 5) | index;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        out.add((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }
    return out;
  }
}
