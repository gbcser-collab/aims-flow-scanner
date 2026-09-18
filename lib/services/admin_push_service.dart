import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'device_identity_service.dart';
import 'runtime_firebase_options.dart';

class AdminPushEvent {
  const AdminPushEvent({
    required this.title,
    required this.body,
    required this.data,
    required this.openedFromNotification,
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool openedFromNotification;
}

class AdminPushStatus {
  const AdminPushStatus({
    required this.firebaseConfigured,
    required this.adminConfigured,
    required this.permissionGranted,
    this.lastError,
  });

  final bool firebaseConfigured;
  final bool adminConfigured;
  final bool permissionGranted;
  final String? lastError;
}

@pragma('vm:entry-point')
Future<void> aimsFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = RuntimeFirebaseOptions.current;
  if (options == null) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}

class AdminPushService {
  AdminPushService._();

  static final AdminPushService instance = AdminPushService._();

  static const _storage = FlutterSecureStorage();
  static const _adminTokenKey = 'aims_admin_push_token';
  static const _baseUrl = String.fromEnvironment(
    'AIMS_TRACKING_BASE_URL',
    defaultValue: 'https://logistic-aims.hu/api/aims-tracking',
  );
  static const _e2eTest =
      bool.fromEnvironment('AIMS_E2E_TEST', defaultValue: false);

  final _events = StreamController<AdminPushEvent>.broadcast();
  final _status = StreamController<AdminPushStatus>.broadcast();
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openSub;
  StreamSubscription<String>? _tokenSub;

  bool _initialized = false;
  bool _firebaseConfigured = false;
  bool _permissionGranted = false;
  String? _lastError;
  AdminPushEvent? _pendingInitial;

  Stream<AdminPushEvent> get events => _events.stream;
  Stream<AdminPushStatus> get statusStream => _status.stream;

  Future<void> initialize() async {
    if (_initialized || _e2eTest) {
      _initialized = true;
      return;
    }
    _initialized = true;

    final options = RuntimeFirebaseOptions.current;
    if (options == null) {
      _firebaseConfigured = false;
      _emitStatus();
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      FirebaseMessaging.onBackgroundMessage(
        aimsFirebaseMessagingBackgroundHandler,
      );
      _firebaseConfigured = true;

      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      _permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        _events.add(_eventFromMessage(message, opened: false));
      });
      _openSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _events.add(_eventFromMessage(message, opened: true));
      });
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        unawaited(_registerTokenIfAdminExists(token));
      });

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _pendingInitial = _eventFromMessage(initial, opened: true);
      }

      final adminToken = await _storage.read(key: _adminTokenKey);
      if (adminToken != null && adminToken.trim().isNotEmpty) {
        final fcm = await FirebaseMessaging.instance.getToken();
        if (fcm != null && fcm.isNotEmpty) {
          await _registerToken(adminToken.trim(), fcm);
        }
      }
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
    _emitStatus();
  }

  Future<AdminPushStatus> currentStatus() async {
    final adminToken = await _storage.read(key: _adminTokenKey);
    return AdminPushStatus(
      firebaseConfigured: _firebaseConfigured,
      adminConfigured: adminToken != null && adminToken.trim().isNotEmpty,
      permissionGranted: _permissionGranted,
      lastError: _lastError,
    );
  }

  AdminPushEvent? takePendingInitialEvent() {
    final event = _pendingInitial;
    _pendingInitial = null;
    return event;
  }

  Future<void> enableForAdmin(String adminToken) async {
    final token = adminToken.trim();
    if (token.isEmpty) throw StateError('Az admin token nem lehet üres.');
    if (!_firebaseConfigured) {
      throw StateError(
        'A Firebase push még nincs konfigurálva ehhez az APK-hoz.',
      );
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _permissionGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!_permissionGranted) {
      _emitStatus();
      throw StateError('Az értesítési engedély nincs megadva.');
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null || fcmToken.isEmpty) {
      throw StateError('Nem sikerült FCM tokent kérni a telefontól.');
    }

    await _registerToken(token, fcmToken);
    await _storage.write(key: _adminTokenKey, value: token);
    _lastError = null;
    _emitStatus();
  }

  Future<void> disableAdminPush() async {
    final adminToken = await _storage.read(key: _adminTokenKey);
    String? fcmToken;
    if (_firebaseConfigured) {
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }

    if (adminToken != null &&
        adminToken.trim().isNotEmpty &&
        fcmToken != null &&
        fcmToken.isNotEmpty) {
      try {
        await _requestJson(
          method: 'DELETE',
          path: '/push_device.php',
          adminToken: adminToken.trim(),
          body: {'fcmToken': fcmToken},
        );
      } catch (_) {}
    }
    await _storage.delete(key: _adminTokenKey);
    _emitStatus();
  }

  Future<String?> storedAdminToken() =>
      _storage.read(key: _adminTokenKey);

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final token = await _requireAdminToken();
    final body = await _requestJson(
      method: 'GET',
      path: '/notifications.php',
      adminToken: token,
    );
    return _mapList(body['notifications']);
  }

  Future<void> markAllRead() async {
    final token = await _requireAdminToken();
    await _requestJson(
      method: 'POST',
      path: '/notifications.php',
      adminToken: token,
      body: {'readAll': true},
    );
  }

  Future<List<Map<String, dynamic>>> fetchFuelReceipts() async {
    final token = await _requireAdminToken();
    final body = await _requestJson(
      method: 'GET',
      path: '/fuel_receipt.php',
      adminToken: token,
    );
    return _mapList(body['receipts']);
  }

  Future<Uint8List> fetchFuelReceiptImage(int receiptId) async {
    final token = await _requireAdminToken();
    final uri = Uri.parse(
      '${_normalizedBase()}/fuel_receipt.php?id=$receiptId&image=1',
    );
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Bizonylatkép HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<void> _registerTokenIfAdminExists(String fcmToken) async {
    final adminToken = await _storage.read(key: _adminTokenKey);
    if (adminToken == null || adminToken.trim().isEmpty) return;
    try {
      await _registerToken(adminToken.trim(), fcmToken);
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
    _emitStatus();
  }

  Future<void> _registerToken(String adminToken, String fcmToken) async {
    final credentials =
        await const DeviceIdentityService().getOrCreateCredentials();
    final package = await PackageInfo.fromPlatform();
    await _requestJson(
      method: 'POST',
      path: '/push_device.php',
      adminToken: adminToken,
      body: {
        'fcmToken': fcmToken,
        'deviceId': credentials.id,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'appVersion': '${package.version}+${package.buildNumber}',
      },
    );
  }

  Future<String> _requireAdminToken() async {
    final token = await _storage.read(key: _adminTokenKey);
    if (token == null || token.trim().isEmpty) {
      throw StateError('Nincs beállítva főnökségi admin token.');
    }
    return token.trim();
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    required String adminToken,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${_normalizedBase()}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $adminToken',
    };
    if (body != null) headers['Content-Type'] = 'application/json';

    late http.Response response;
    if (method == 'POST') {
      response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } else if (method == 'DELETE') {
      response = await http
          .delete(uri, headers: headers, body: jsonEncode(body ?? const {}))
          .timeout(const Duration(seconds: 15));
    } else {
      response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final parsed = jsonDecode(response.body);
      if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code =
          decoded['error']?.toString() ?? 'HTTP ${response.statusCode}';
      throw StateError(code);
    }
    return decoded;
  }

  String _normalizedBase() =>
      _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  AdminPushEvent _eventFromMessage(
    RemoteMessage message, {
    required bool opened,
  }) {
    final notification = message.notification;
    return AdminPushEvent(
      title: notification?.title ?? 'AIMS Flow értesítés',
      body: notification?.body ?? '',
      data: Map<String, dynamic>.from(message.data),
      openedFromNotification: opened,
    );
  }

  Future<void> _emitStatus() async {
    if (_status.isClosed) return;
    _status.add(await currentStatus());
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _openSub?.cancel();
    await _tokenSub?.cancel();
    await _events.close();
    await _status.close();
  }
}
