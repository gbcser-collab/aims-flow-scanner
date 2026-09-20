[Reading 368 lines from start (total: 368 lines, 0 remaining)]

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'driver_api_service.dart';
import 'runtime_firebase_options.dart';
import 'vehicle_tracking_service.dart';

const _jobChannelId = 'aims_jobs';
const _jobChannelName = 'AIMS Flow fuvarok';
const _adminChannelId = 'aims_admin_alerts';
const _adminChannelName = 'AIMS Flow admin értesítések';

class DriverPushEvent {
  const DriverPushEvent({
    required this.data,
    required this.actionId,
    required this.openedFromNotification,
  });

  final Map<String, dynamic> data;
  final String actionId;
  final bool openedFromNotification;

  int get jobId => int.tryParse(data['jobId']?.toString() ?? '') ?? 0;
  String get plate => data['plate']?.toString() ?? '';
}

@pragma('vm:entry-point')
Future<void> aimsDriverMessagingBackgroundHandler(RemoteMessage message) async {
  final options = RuntimeFirebaseOptions.current;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
  await DriverPushService.showJobNotification(message);
}

class DriverPushService {
  DriverPushService._();

  static final DriverPushService instance = DriverPushService._();
  static const _api = DriverApiService();
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final _events = StreamController<DriverPushEvent>.broadcast();
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openSub;
  StreamSubscription<String>? _tokenSub;
  DriverPushEvent? _pendingLaunch;
  String _registeredPlate = '';
  bool _initialized = false;

  Stream<DriverPushEvent> get events => _events.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationResponse(response);
      },
    );

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _jobChannelId,
        _jobChannelName,
        description: 'Új fuvar és részrakomány értesítések',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('aims_new_job'),
        enableVibration: true,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _adminChannelId,
        _adminChannelName,
        description: 'Járműállás, érkezés és sofőr műveleti értesítések',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    final launch = await _notifications.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      _pendingLaunch = _eventFromPayload(
        response.payload,
        actionId: response.actionId ?? '',
        opened: true,
      );
    }

    final options = RuntimeFirebaseOptions.current;
    if (options == null) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    FirebaseMessaging.onBackgroundMessage(
      aimsDriverMessagingBackgroundHandler,
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    _messageSub = FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type']?.toString() == 'driver_job') {
        await showJobNotification(message);
      } else {
        await showAdminNotification(message);
      }
      _events.add(DriverPushEvent(
        data: Map<String, dynamic>.from(message.data),
        actionId: '',
        openedFromNotification: false,
      ));
    });

    _openSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _events.add(DriverPushEvent(
        data: Map<String, dynamic>.from(message.data),
        actionId: 'open_job',
        openedFromNotification: true,
      ));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _pendingLaunch = DriverPushEvent(
        data: Map<String, dynamic>.from(initial.data),
        actionId: 'open_job',
        openedFromNotification: true,
      );
    }

    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      if (_registeredPlate.isNotEmpty) {
        unawaited(registerForPlate(_registeredPlate));
      }
    });
  }

  DriverPushEvent? takePendingLaunch() {
    final event = _pendingLaunch;
    _pendingLaunch = null;
    return event;
  }

  Future<void> cancelJobNotification(int jobId) async {
    if (jobId <= 0) return;
    await _notifications.cancel(jobId);
  }

  Future<Map<String, String>> adminRegistrationPayload() async {
    if (Firebase.apps.isEmpty) {
      await initialize();
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('A Firebase push szolgáltatás nem inicializálódott.');
    }
    final fcm = await FirebaseMessaging.instance.getToken();
    if (fcm == null || fcm.isEmpty) {
      throw StateError('A telefon nem kapott Firebase push tokent.');
    }
    final tracking = await VehicleTrackingService.instance.currentStatus();
    return <String, String>{
      'fcmToken': fcm,
      'deviceId': tracking.deviceId,
      'platform': 'android',
    };
  }

  Future<void> registerForPlate(String plate) async {
    final cleanPlate = plate.trim().toUpperCase();
    if (cleanPlate.isEmpty) {
      throw StateError('Nincs beállítva rendszám.');
    }
    if (Firebase.apps.isEmpty) {
      await initialize();
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('A Firebase push szolgáltatás nem inicializálódott.');
    }
    final fcm = await FirebaseMessaging.instance.getToken();
    if (fcm == null || fcm.isEmpty) {
      throw StateError('A telefon nem kapott Firebase push tokent.');
    }
    final tracking = await VehicleTrackingService.instance.currentStatus();
    await _api.registerPush(
      plate: cleanPlate,
      deviceId: tracking.deviceId,
      fcmToken: fcm,
    );
    _registeredPlate = cleanPlate;
  }

  static Future<void> showAdminNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title?.trim() ?? '';
    final body = notification?.body?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
    );
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _adminChannelId,
        _adminChannelName,
        description: 'Járműállás, érkezés és sofőr műveleti értesítések',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    final notificationId =
        int.tryParse(message.data['notificationId']?.toString() ?? '') ??
            (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    const details = AndroidNotificationDetails(
      _adminChannelId,
      _adminChannelName,
      channelDescription: 'Járműállás, érkezés és sofőr műveleti értesítések',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
    );

    await _notifications.show(
      notificationId,
      title.isEmpty ? 'AIMS Flow' : title,
      body,
      const NotificationDetails(android: details),
      payload: jsonEncode(Map<String, dynamic>.from(message.data)),
    );
  }

  static Future<void> showJobNotification(RemoteMessage message) async {
    if (message.data['type']?.toString() != 'driver_job') return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
    );
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _jobChannelId,
        _jobChannelName,
        description: 'Új fuvar és részrakomány értesítések',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('aims_new_job'),
        enableVibration: true,
      ),
    );

    final data = Map<String, dynamic>.from(message.data);
    final jobId = int.tryParse(data['jobId']?.toString() ?? '') ?? 0;
    final partial = data['partial']?.toString() == '1';
    final company = data['company']?.toString().trim() ?? '';
    final route = data['route']?.toString().trim() ?? '';
    final title = partial ? 'Új részrakomány érkezett' : 'Új fuvar érkezett';
    final body = [
      if (company.isNotEmpty) company,
      if (route.isNotEmpty) route,
    ].join(' • ');

    final details = AndroidNotificationDetails(
      _jobChannelId,
      _jobChannelName,
      channelDescription: 'Új fuvar és részrakomány értesítések',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('aims_new_job'),
      enableVibration: true,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      actions: const [
        AndroidNotificationAction(
          'seen_job',
          'LÁTTAM',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'open_job',
          'MEGNYITÁS',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'navigate_pickup',
          'NAVIGÁCIÓ',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    await _notifications.show(
      jobId == 0 ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : jobId,
      title,
      body,
      NotificationDetails(android: details),
      payload: jsonEncode(data),
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final event = _eventFromPayload(
      response.payload,
      actionId: response.actionId ?? '',
      opened: true,
    );
    if (event != null) _events.add(event);
  }

  DriverPushEvent? _eventFromPayload(
    String? payload, {
    required String actionId,
    required bool opened,
  }) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return DriverPushEvent(
        data: Map<String, dynamic>.from(decoded),
        actionId: actionId,
        openedFromNotification: opened,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _openSub?.cancel();
    await _tokenSub?.cancel();
    await _events.close();
  }
}

[executed on device: GABOR-PC (4f5060cc-3a10-4200-947d-55b7a0fc1e22)]