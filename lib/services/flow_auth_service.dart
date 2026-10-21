import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'device_identity_service.dart';

abstract class FlowTokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureFlowTokenStore implements FlowTokenStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _key = 'flow_session_v2';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class FlowAuthException implements Exception {
  const FlowAuthException(this.code, this.status);
  final String code;
  final int status;
  @override
  String toString() => switch (code) {
    'invalid_credentials' => 'Hibás FLOW ID vagy PIN.',
    'rate_limited' => 'Túl sok próbálkozás. Próbáld később.',
    'assignment_required' =>
      'Nincs hozzád rendelt aktív jármű. Keresd az irodát.',
    'session_expired' ||
    'session_revoked' => 'Lépj be újra a FLOW ID és PIN megadásával.',
    'permission_denied' => 'Ehhez a művelethez nincs hozzáférésed.',
    'restart_required' =>
      'Sofőrváltáshoz zárd be teljesen, majd nyisd meg újra az alkalmazást.',
    _ =>
      'A bejelentkezési szolgáltatás nem érhető el. Az adataid helyben megmaradnak.',
  };
}

class FlowAuthSession {
  const FlowAuthSession({
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.subjectId,
    required this.tenantId,
    required this.flowId,
    required this.assignmentId,
    required this.plate,
    required this.displayName,
    required this.language,
    required this.deviceId,
  });
  final String refreshToken,
      subjectId,
      tenantId,
      flowId,
      assignmentId,
      plate,
      displayName,
      language,
      deviceId;
  final DateTime refreshExpiresAt;
  String get scope => sha256.convert(
    utf8.encode(jsonEncode([tenantId, subjectId, assignmentId, plate])),
  ).toString();
  Map<String, dynamic> toJson() => {
    'refreshToken': refreshToken,
    'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
    'subjectId': subjectId,
    'tenantId': tenantId,
    'flowId': flowId,
    'assignmentId': assignmentId,
    'plate': plate,
    'displayName': displayName,
    'language': language,
    'deviceId': deviceId,
  };
  factory FlowAuthSession.fromJson(Map<String, dynamic> j) => FlowAuthSession(
    refreshToken: j['refreshToken'] as String,
    refreshExpiresAt: DateTime.parse(j['refreshExpiresAt'] as String),
    subjectId: j['subjectId'] as String,
    tenantId: j['tenantId'] as String,
    flowId: j['flowId'] as String,
    assignmentId: j['assignmentId'] as String,
    plate: j['plate'] as String,
    displayName: j['displayName'] as String,
    language: j['language'] as String,
    deviceId: j['deviceId'] as String,
  );
}

class FlowAuthService {
  FlowAuthService({
    http.Client? client,
    FlowTokenStore? store,
    Uri? endpoint,
    Future<String> Function()? deviceId,
  }) : _client = client ?? http.Client(),
       _store = store ?? SecureFlowTokenStore(),
       endpoint =
           endpoint ??
           Uri.parse(
             const String.fromEnvironment(
               'AIMS_FLOW_AUTH_URL',
               defaultValue:
                   'https://logistic-aims.hu/api/aims-tracking/driver_auth.php',
             ),
           ),
       _deviceId =
           deviceId ??
           (() async =>
               (await const DeviceIdentityService().loadOrCreate()).deviceId);
  static final instance = FlowAuthService();
  final http.Client _client;
  final FlowTokenStore _store;
  final Uri endpoint;
  final Future<String> Function() _deviceId;
  final invalidated = ValueNotifier<int>(0);
  FlowAuthSession? session;
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<void>? _refreshing;
  String? _processScope;
  Future<void> _storageTail = Future<void>.value();
  int _generation = 0;
  bool get authenticated => session != null;
  String get storageScope => _processScope ?? session?.scope ?? 'unassigned';
  Future<bool> hasStoredSession() async => await _store.read() != null;
  Future<void> _storeSerial(Future<void> Function() action) {
    final next = _storageTail.then((_) => action());
    _storageTail = next.catchError((_) {});
    return next;
  }

  static bool credentialsValid(String id, String pin) =>
      id.length == 6 &&
      pin.length == 5 &&
      RegExp(r'^[0-9]{6}$').hasMatch(id) &&
      RegExp(r'^[0-9]{5}$').hasMatch(pin);

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> data, {
    String? access,
    String? device,
  }) async {
    if (endpoint.scheme != 'https')
      throw const FlowAuthException('identity_unavailable', 503);
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (access != null) 'Authorization': 'Bearer $access',
        if (device != null) 'X-Flow-Device': device,
      })
      ..body = jsonEncode(data);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {}
    if (response.statusCode != 200 || body['ok'] != true) {
      throw FlowAuthException(
        body['error']?.toString() ?? 'identity_unavailable',
        response.statusCode,
      );
    }
    return body;
  }

  Future<void> _accept(
    Map<String, dynamic> body,
    String device,
    int generation,
  ) async {
    try {
      final p = Map<String, dynamic>.from(body['principal'] as Map);
      final a = Map<String, dynamic>.from(body['assignment'] as Map);
      final token = body['accessToken'] as String;
      final refresh = body['refreshToken'] as String;
      final expires = DateTime.parse(body['accessExpiresAt'] as String);
      final refreshExpires = DateTime.parse(body['refreshExpiresAt'] as String);
      if (p['role'] != 'driver' ||
          !RegExp(r'^[0-9]{6}$').hasMatch(p['flowId'] as String) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(refresh) ||
          !expires.isAfter(DateTime.now()) ||
          refreshExpires.isBefore(expires) ||
          (a['plate'] as String).isEmpty ||
          (a['assignmentId'] as String).isEmpty ||
          (p['subjectId'] as String).isEmpty ||
          (p['tenantId'] as String).isEmpty) {
        throw const FormatException();
      }
      final next = FlowAuthSession(
        refreshToken: refresh,
        refreshExpiresAt: refreshExpires,
        subjectId: p['subjectId'] as String,
        tenantId: p['tenantId'] as String,
        flowId: p['flowId'] as String,
        assignmentId: a['assignmentId'] as String,
        plate: a['plate'] as String,
        displayName: p['displayName']?.toString() ?? '',
        language: p['language']?.toString() ?? 'hu',
        deviceId: device,
      );
      if (generation != _generation)
        throw const FlowAuthException('session_revoked', 401);
      if (session != null && session!.scope != next.scope)
        throw const FlowAuthException('session_revoked', 401);
      // Until every legacy singleton can drain its pending work, switching owner
      // requires a process restart. This prevents old callbacks writing under a new owner.
      if (_processScope != null && _processScope != next.scope)
        throw const FlowAuthException('restart_required', 409);
      await _storeSerial(() async {
        if (generation != _generation)
          throw const FlowAuthException('session_revoked', 401);
        await _store.write(jsonEncode(next.toJson()));
      });
      if (generation != _generation)
        throw const FlowAuthException('session_revoked', 401);
      _processScope = next.scope;
      session = next;
      _accessToken = token;
      _accessExpiresAt = expires;
    } on FlowAuthException {
      rethrow;
    } catch (_) {
      throw const FlowAuthException('identity_unavailable', 503);
    }
  }

  Future<FlowAuthSession> login(String flowId, String pin) async {
    if (!credentialsValid(flowId, pin))
      throw const FlowAuthException('invalid_payload', 422);
    await clear();
    final generation = _generation;
    final device = await _deviceId();
    final body = await _call({
      'action': 'login',
      'flowId': flowId,
      'pin': pin,
      'deviceId': device,
    });
    await _accept(body, device, generation);
    return session!;
  }

  /// Cold start always validates online. Unauthenticated local prefs never unlock a session.
  Future<bool> restore() async {
    try {
      final raw = await _store.read();
      if (raw == null) return false;
      session = FlowAuthSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      _processScope = session!.scope;
      if (!session!.refreshExpiresAt.isAfter(DateTime.now())) {
        await clear();
        return false;
      }
      await refresh();
      return true;
    } on FlowAuthException catch (e) {
      if (e.status == 401 || e.status == 403) await clear();
      session = null;
      _accessToken = null;
      return false;
    } catch (_) {
      session = null;
      _accessToken = null;
      return false;
    }
  }

  Future<void> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final task = _refresh();
    _refreshing = task;
    return task.whenComplete(() {
      if (identical(_refreshing, task)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final current = session;
    final generation = _generation;
    if (current == null) throw const FlowAuthException('session_expired', 401);
    try {
      final body = await _call({
        'action': 'refresh',
        'refreshToken': current.refreshToken,
      }, device: current.deviceId);
      await _accept(body, current.deviceId, generation);
    } on FlowAuthException catch (e) {
      if (e.status == 401 || e.status == 403) await clear();
      rethrow;
    }
  }

  Future<String> accessToken() async {
    if (session == null) throw const FlowAuthException('session_expired', 401);
    if (_accessToken == null ||
        _accessExpiresAt == null ||
        !_accessExpiresAt!.isAfter(
          DateTime.now().add(const Duration(seconds: 30)),
        ))
      await refresh();
    return _accessToken!;
  }

  Future<void> validate() async {
    final token = await accessToken();
    try {
      await _call(
        {'action': 'session'},
        access: token,
        device: session!.deviceId,
      );
    } on FlowAuthException catch (e) {
      if (e.status == 401 || e.status == 403) await clear();
      rethrow;
    }
  }

  Future<void> logout() async {
    final current = session;
    try {
      if (current != null)
        await _call({
          'action': 'logout',
          'refreshToken': current.refreshToken,
        }, device: current.deviceId);
    } finally {
      await clear();
    }
  }

  Future<void> clear() async {
    _generation++;
    session = null;
    _accessToken = null;
    _accessExpiresAt = null;
    invalidated.value++;
    await _storeSerial(_store.clear);
  }

  Future<void> rejectAccessToken(String token) async {
    if (token == _accessToken) await clear();
  }
}
