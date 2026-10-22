import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';
import 'flow_local_journal.dart';

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

class FlowSessionRejected extends StateError {
  FlowSessionRejected() : super('A munkamenet lejárt. Lépj be újra.');
}

class FlowSessionChanged implements Exception {
  const FlowSessionChanged();

  @override
  String toString() => 'A munkamenet megváltozott. Nyisd meg újra a belépést.';
}

class FlowSessionStore {
  FlowSessionStore({
    this.readSecure,
    this.writeSecure,
    this.deleteSecure,
    bool? preferencesOnly,
  }) : _preferencesOnly = preferencesOnly ?? _runningUnderFlutterTest;

  static final instance = FlowSessionStore();
  static const _key = 'aims_flow_driver_session_v2';
  static const _revokedKey = 'aims_flow_session_revoked_v1';
  static final _secure = FlutterSecureStorage(aOptions: AndroidOptions());
  final Future<String?> Function()? readSecure;
  final Future<void> Function(String)? writeSecure;
  final Future<void> Function()? deleteSecure;
  final bool _preferencesOnly;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;

  static bool get _runningUnderFlutterTest {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    try {
      return WidgetsBinding.instance.runtimeType.toString()
          .contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  void _checked(bool success) {
    if (!success) throw StateError('A munkamenet helyi mentése nem sikerült.');
  }

  Future<String?> _readRaw(SharedPreferences prefs) async {
    // A failed secure-storage delete must never revive a logged-out token.
    if (prefs.getBool(_revokedKey) == true) return null;
    if (_preferencesOnly) return prefs.getString(_key);
    final secured = await (readSecure?.call() ?? _secure.read(key: _key));
    if (secured != null && secured.trim().isNotEmpty) return secured;
    final legacy = prefs.getString(_key);
    if (legacy != null && legacy.trim().isNotEmpty) {
      await (writeSecure?.call(legacy) ?? _secure.write(key: _key, value: legacy));
      _checked(await prefs.remove(_key));
    }
    // Secure storage failures propagate; production never writes plaintext.
    return legacy;
  }

  Future<FlowAccountSession?> _loadUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readRaw(prefs);
    if (raw == null || raw.trim().isEmpty) return null;
    FlowAccountSession? session;
    try {
      session = FlowAccountSession.fromJson(jsonDecode(raw));
    } catch (_) {
      // Malformed local sessions are revoked, not guessed.
    }
    if (session == null || session.isExpired) {
      await _clearUnlocked();
      return null;
    }
    return session;
  }

  Future<FlowAccountSession?> load() => _locked(_loadUnlocked);

  Future<void> _saveUnlocked(FlowAccountSession value) async {
    if (value.isExpired) throw StateError('A munkamenet lejárt. Lépj be újra.');
    final prefs = await SharedPreferences.getInstance();
    await FlowLocalJournal.preserveWorkdayIdentity(prefs);
    _revision++;
    _checked(await prefs.setBool(_revokedKey, true));
    final raw = jsonEncode(value.toJson());
    if (_preferencesOnly) {
      _checked(await prefs.setString(_key, raw));
    } else {
      await (writeSecure?.call(raw) ?? _secure.write(key: _key, value: raw));
      _checked(await prefs.remove(_key));
    }
    _checked(await prefs.setString('aims_flow_id', value.flowId));
    _checked(await prefs.setString('aims_driver_name', value.driverName));
    _checked(await prefs.setString('aims_driver_plate', value.plate));
    _checked(await prefs.setString('aims_user_role', 'driver'));
    if (value.currentKm != null) {
      _checked(await prefs.setInt('aims_driver_last_odometer_km', value.currentKm!));
    } else {
      _checked(await prefs.remove('aims_driver_last_odometer_km'));
    }
    _checked(await prefs.setBool(_revokedKey, false));
  }

  Future<void> save(FlowAccountSession value) => _locked(() => _saveUnlocked(value));

  bool _same(FlowAccountSession? a, FlowAccountSession? b) =>
      a?.flowId == b?.flowId && a?.sessionToken == b?.sessionToken;

  Future<int> revisionFor(FlowAccountSession session) => _locked(() async {
    if (!_same(await _loadUnlocked(), session)) throw const FlowSessionChanged();
    return _revision;
  });

  Future<int> beginLogin() => _locked(() async => ++_revision);

  Future<void> saveLogin(FlowAccountSession value, int revision) => _locked(() async {
    if (_revision != revision) throw const FlowSessionChanged();
    await _saveUnlocked(value);
  });

  Future<void> replaceCurrent(FlowAccountSession expected,
      FlowAccountSession value, int revision) => _locked(() async {
    if (!_same(await _loadUnlocked(), expected) || _revision != revision ||
        value.flowId != expected.flowId) throw const FlowSessionChanged();
    await _saveUnlocked(value);
  });

  Future<void> _clearUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await FlowLocalJournal.preserveWorkdayIdentity(prefs);
    _revision++;
    _checked(await prefs.setBool(_revokedKey, true));
    if (!_preferencesOnly) {
      try {
        await (deleteSecure?.call() ?? _secure.delete(key: _key));
      } catch (_) {
        // The durable revocation marker already prevents token reuse.
      }
    }
    for (final key in [_key, 'aims_flow_id', 'aims_driver_name',
      'aims_driver_plate', 'aims_driver_last_odometer_km',
      'aims_driver_local_unlock', 'aims_user_role']) {
      _checked(await prefs.remove(key));
    }
  }

  Future<void> clear() => _locked(_clearUnlocked);

  Future<void> clearIfCurrent(FlowAccountSession? expected) => _locked(() async {
    if (_same(await _loadUnlocked(), expected)) await _clearUnlocked();
  });
}

class FlowAccountService {
  const FlowAccountService({this.client, this.store, this.loadDeviceId});

  final http.Client? client;
  final FlowSessionStore? store;
  final Future<String> Function()? loadDeviceId;
  FlowSessionStore get _store => store ?? FlowSessionStore.instance;

  static const _url = String.fromEnvironment(
    'AIMS_FLOW_AUTH_V2_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-flow-auth-v2.php',
  );

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    String sessionToken = '',
  }) async {
    final response = await (client?.post ?? http.post)(
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
    if (error == 'invalid_credentials' ||
        (response.statusCode == 401 && sessionToken.isEmpty)) {
      throw StateError('Hibás FLOW ID vagy PIN.');
    }
    if (error == 'invalid_session' || response.statusCode == 401) {
      throw FlowSessionRejected();
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
    final revision = await _store.beginLogin();
    final deviceId = await (loadDeviceId?.call() ??
        const DeviceIdentityService().loadOrCreate().then((value) => value.deviceId));
    final body = await _post({
      'action': 'login',
      'flowId': flowId.trim(),
      'pin': pin.trim(),
      'deviceId': deviceId,
    });
    final session = _sessionFromResponse(body);
    await _store.saveLogin(session, revision);
    return session;
  }

  Future<FlowAccountSession> validateSession(
    FlowAccountSession session,
  ) async {
    final revision = await _store.revisionFor(session);
    final body = await _post(
      const {'action': 'validate'},
      sessionToken: session.sessionToken,
    );
    final updated = _sessionFromResponse(
      body,
      existingToken: session.sessionToken,
      existingExpiry: session.expiresAt,
    );
    await _store.replaceCurrent(session, updated, revision);
    return updated;
  }

  Future<FlowAccountSession> completeOnboarding({
    required FlowAccountSession session,
    required String driverName,
    required int odometerKm,
    required String plate,
  }) async {
    final revision = await _store.revisionFor(session);
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
    await _store.replaceCurrent(session, updated, revision);
    return updated;
  }

  Future<void> logout(FlowAccountSession? session) async {
    await _store.clearIfCurrent(session);
    if (session != null) {
      try {
        await _post(
          const {'action': 'logout'},
          sessionToken: session.sessionToken,
        );
      } catch (_) {}
    }
  }
}

