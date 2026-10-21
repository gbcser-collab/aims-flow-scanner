import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';

class FlowAccountSession {
  const FlowAccountSession({
    required this.flowId,
    required this.sessionToken,
    required this.expiresAt,
    required this.onboardingComplete,
    this.email = '',
    this.driverName = '',
    this.plate = '',
    this.currentKm,
    this.baseLatitude,
    this.baseLongitude,
    this.baseRadiusMeters = 350,
  });

  final String flowId;
  final String sessionToken;
  final DateTime expiresAt;
  final bool onboardingComplete;
  final String email;
  final String driverName;
  final String plate;
  final int? currentKm;
  final double? baseLatitude;
  final double? baseLongitude;
  final double baseRadiusMeters;

  bool get isExpired =>
      DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  FlowAccountSession copyWith({
    String? sessionToken,
    DateTime? expiresAt,
    bool? onboardingComplete,
    String? email,
    String? driverName,
    String? plate,
    int? currentKm,
    double? baseLatitude,
    double? baseLongitude,
    double? baseRadiusMeters,
  }) =>
      FlowAccountSession(
        flowId: flowId,
        sessionToken: sessionToken ?? this.sessionToken,
        expiresAt: expiresAt ?? this.expiresAt,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        email: email ?? this.email,
        driverName: driverName ?? this.driverName,
        plate: plate ?? this.plate,
        currentKm: currentKm ?? this.currentKm,
        baseLatitude: baseLatitude ?? this.baseLatitude,
        baseLongitude: baseLongitude ?? this.baseLongitude,
        baseRadiusMeters: baseRadiusMeters ?? this.baseRadiusMeters,
      );

  Map<String, dynamic> toJson() => {
        'flowId': flowId,
        'sessionToken': sessionToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'onboardingComplete': onboardingComplete,
        'email': email,
        'driverName': driverName,
        'plate': plate,
        'currentKm': currentKm,
        'baseLatitude': baseLatitude,
        'baseLongitude': baseLongitude,
        'baseRadiusMeters': baseRadiusMeters,
      };

  static FlowAccountSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final flowId = json['flowId']?.toString().trim() ?? '';
    final token = json['sessionToken']?.toString().trim() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (!RegExp(r'^\d{6}$').hasMatch(flowId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        expiresAt == null) {
      return null;
    }
    return FlowAccountSession(
      flowId: flowId,
      sessionToken: token,
      expiresAt: expiresAt.toUtc(),
      onboardingComplete: json['onboardingComplete'] == true,
      email: json['email']?.toString().trim() ?? '',
      driverName: json['driverName']?.toString().trim() ?? '',
      plate: json['plate']?.toString().trim().toUpperCase() ?? '',
      currentKm: (json['currentKm'] as num?)?.toInt(),
      baseLatitude: (json['baseLatitude'] as num?)?.toDouble(),
      baseLongitude: (json['baseLongitude'] as num?)?.toDouble(),
      baseRadiusMeters:
          (json['baseRadiusMeters'] as num?)?.toDouble() ?? 350,
    );
  }
}

class FlowSessionStore {
  FlowSessionStore._();

  static final instance = FlowSessionStore._();
  static const _key = 'aims_flow_driver_session_v2';
  static final _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static bool get _runningUnderFlutterTest {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    try {
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      return bindingName.contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readRaw() async {
    final prefs = await SharedPreferences.getInstance();
    if (_runningUnderFlutterTest) return prefs.getString(_key);

    try {
      final secured = await _secure.read(key: _key);
      if (secured != null && secured.trim().isNotEmpty) return secured;

      // One-time migration from development builds that used ordinary
      // SharedPreferences. Production writes are secure-storage only.
      final legacy = prefs.getString(_key);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _secure.write(key: _key, value: legacy);
        await prefs.remove(_key);
        return legacy;
      }
      return null;
    } catch (_) {
      // Unsupported non-Android development targets can still open the app,
      // while supported Android builds use Keystore-backed secure storage.
      return prefs.getString(_key);
    }
  }

  Future<FlowAccountSession?> load() async {
    final raw = await _readRaw();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final session = FlowAccountSession.fromJson(jsonDecode(raw));
      if (session == null || session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(FlowAccountSession value) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(value.toJson());

    if (_runningUnderFlutterTest) {
      await prefs.setString(_key, raw);
    } else {
      try {
        await _secure.write(key: _key, value: raw);
        await prefs.remove(_key);
      } catch (_) {
        // Unsupported development targets use a compatibility fallback.
        // Production Android builds have the secure-storage plugin available.
        await prefs.setString(_key, raw);
      }
    }

    // Non-secret identity hints remain in preferences for the existing FLOW
    // screens and offline queues. The PIN is never persisted anywhere.
    await prefs.setString('aims_flow_id', value.flowId);
    await prefs.setString('aims_driver_name', value.driverName);
    await prefs.setString('aims_driver_plate', value.plate);
    await prefs.setString('aims_user_role', 'driver');
    if (value.currentKm != null) {
      await prefs.setInt(
        'aims_driver_last_odometer_km',
        value.currentKm!,
      );
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_runningUnderFlutterTest) {
      try {
        await _secure.delete(key: _key);
      } catch (_) {}
    }
    await prefs.remove(_key);
    await prefs.remove('aims_flow_id');
    await prefs.remove('aims_driver_name');
    await prefs.remove('aims_driver_plate');
    await prefs.remove('aims_driver_last_odometer_km');
    await prefs.remove('aims_driver_local_unlock');
    await prefs.remove('aims_user_role');
  }
}

class FlowAccountService {
  const FlowAccountService();

  static const _url = String.fromEnvironment(
    'AIMS_FLOW_AUTH_V2_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-auth-v2.php',
  );

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    String sessionToken = '',
  }) async {
    final response = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (sessionToken.isNotEmpty)
              'Authorization': 'Bearer $sessionToken',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 18));

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['ok'] == true) {
      return body;
    }

    final error = body['error']?.toString() ?? 'server_unavailable';
    if (response.statusCode == 401 || error == 'invalid_credentials') {
      throw StateError('Hibás FLOW ID vagy PIN.');
    }
    if (error == 'invalid_session') {
      throw StateError('A munkamenet lejárt. Lépj be újra.');
    }
    if (error == 'rate_limited') {
      throw StateError('Túl sok próbálkozás. Próbáld meg később.');
    }
    if (error == 'vehicle_assigned_to_other_driver') {
      throw StateError('Ez a jármű már másik aktív sofőrhöz van rendelve.');
    }
    if (error == 'vehicle_already_assigned') {
      throw StateError('A hozzáféréshez már másik jármű van rendelve.');
    }
    if (error == 'vehicle_disabled') {
      throw StateError('A jármű hozzáférése le van tiltva.');
    }
    throw StateError('A FLOW szerver nem érhető el.');
  }

  FlowAccountSession _sessionFromResponse(
    Map<String, dynamic> body, {
    String existingToken = '',
    DateTime? existingExpiry,
  }) {
    final rawProfile = body['profile'];
    if (rawProfile is! Map) throw StateError('Hibás FLOW profilválasz.');
    final profile = Map<String, dynamic>.from(rawProfile);
    final token = body['sessionToken']?.toString().trim().isNotEmpty == true
        ? body['sessionToken'].toString().trim()
        : existingToken;
    final expiresAt = DateTime.tryParse(
          body['sessionExpiresAt']?.toString() ?? '',
        )?.toUtc() ??
        existingExpiry;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        expiresAt == null) {
      throw StateError('Hibás FLOW munkamenet.');
    }
    final flowId = profile['flowId']?.toString().trim() ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(flowId)) {
      throw StateError('Hibás FLOW profil.');
    }
    return FlowAccountSession(
      flowId: flowId,
      sessionToken: token,
      expiresAt: expiresAt,
      onboardingComplete: profile['onboardingComplete'] == true,
      email: profile['email']?.toString().trim() ?? '',
      driverName: profile['driverName']?.toString().trim() ?? '',
      plate: profile['plate']?.toString().trim().toUpperCase() ?? '',
      currentKm: (profile['currentKm'] as num?)?.toInt(),
    );
  }

  Future<FlowAccountSession> login({
    required String flowId,
    required String pin,
  }) async {
    final identity = await const DeviceIdentityService().loadOrCreate();
    final body = await _post({
      'action': 'login',
      'flowId': flowId.trim(),
      'pin': pin.trim(),
      'deviceId': identity.deviceId,
    });
    final session = _sessionFromResponse(body);
    await FlowSessionStore.instance.save(session);
    return session;
  }

  Future<FlowAccountSession> validateSession(
    FlowAccountSession session,
  ) async {
    final body = await _post(
      const {'action': 'validate'},
      sessionToken: session.sessionToken,
    );
    final updated = _sessionFromResponse(
      body,
      existingToken: session.sessionToken,
      existingExpiry: session.expiresAt,
    );
    await FlowSessionStore.instance.save(updated);
    return updated;
  }

  Future<FlowAccountSession> completeOnboarding({
    required FlowAccountSession session,
    required String driverName,
    required int odometerKm,
    required String plate,
  }) async {
    final body = await _post(
      {
        'action': 'onboarding',
        'driverName': driverName.trim(),
        'currentKm': odometerKm,
        'plate': plate.trim().toUpperCase(),
      },
      sessionToken: session.sessionToken,
    );
    final updated = _sessionFromResponse(
      body,
      existingToken: session.sessionToken,
      existingExpiry: session.expiresAt,
    );
    await FlowSessionStore.instance.save(updated);
    return updated;
  }

  Future<void> logout(FlowAccountSession? session) async {
    if (session != null) {
      try {
        await _post(
          const {'action': 'logout'},
          sessionToken: session.sessionToken,
        );
      } catch (_) {}
    }
    await FlowSessionStore.instance.clear();
  }
}
