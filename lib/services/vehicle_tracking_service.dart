import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'country_code_service.dart';
import 'roaming_resilience.dart';

class VehicleTrackingStatus {
  const VehicleTrackingStatus({
    required this.enabled,
    required this.running,
    required this.deviceId,
    required this.vehicleLabel,
    this.lastPosition,
    this.lastSentAt,
    this.lastError,
  });

  final bool enabled;
  final bool running;
  final String deviceId;
  final String vehicleLabel;
  final Position? lastPosition;
  final DateTime? lastSentAt;
  final String? lastError;
}

class VehicleTrackingService {
  VehicleTrackingService._();

  static final VehicleTrackingService instance = VehicleTrackingService._();

  static const _enabledKey = 'aims_tracking_enabled';
  static const _deviceIdKey = 'aims_tracking_device_id';
  static const _vehicleLabelKey = 'aims_tracking_vehicle_label';

  static const _endpoint = String.fromEnvironment(
    'AIMS_TRACKING_ENDPOINT',
    defaultValue: 'https://logistic-aims.hu/api/aims-tracking/ingest.php',
  );
  static const _token = String.fromEnvironment('AIMS_TRACKING_TOKEN', defaultValue: '');

  final _statusController = StreamController<VehicleTrackingStatus>.broadcast();
  StreamSubscription<Position>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Future<void> _queueIoTail = Future<void>.value();
  Future<void> _positionTail = Future<void>.value();
  bool _flushRunning = false;
  bool _flushAgain = false;
  int _flushFailures = 0;
  Position? _lastPosition;
  DateTime? _lastSentAt;
  String? _lastError;
  String _deviceId = '';
  String _vehicleLabel = '';
  bool _enabled = false;

  Stream<VehicleTrackingStatus> get statusStream => _statusController.stream;

  Future<VehicleTrackingStatus> currentStatus() async {
    await _loadIdentity();
    return _status;
  }

  Future<void> startIfEnabled() async {
    await _loadIdentity();
    if (_enabled) await _startLocationStream(requestPermission: false);
  }

  Future<bool> enableWithPermission() async {
    await _loadIdentity();
    if (!await Geolocator.isLocationServiceEnabled()) {
      _lastError = 'A helymeghatározás ki van kapcsolva a telefonon.';
      _emit();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _lastError = 'A helyhozzáférés nincs engedélyezve.';
      _emit();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    _enabled = true;
    _lastError = null;
    await _startLocationStream(requestPermission: false);
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    _enabled = false;
    await _subscription?.cancel();
    _subscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _emit();
  }

  Future<void> setVehicleLabel(String label) async {
    final cleaned = label.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    _vehicleLabel = cleaned;
    await prefs.setString(_vehicleLabelKey, _vehicleLabel);
    _emit();
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _vehicleLabel = prefs.getString(_vehicleLabelKey) ?? '';
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.trim().isEmpty) {
      final random = Random.secure();
      final suffix = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
      id = 'aims-${DateTime.now().millisecondsSinceEpoch}-$suffix';
      await prefs.setString(_deviceIdKey, id);
    }
    _deviceId = id;
  }

  Future<void> _startLocationStream({required bool requestPermission}) async {
    if (_subscription != null) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      _lastError = 'A helymeghatározás ki van kapcsolva.';
      _emit();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (requestPermission && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _lastError = 'A helyhozzáférés nincs engedélyezve.';
      _emit();
      return;
    }

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 15),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'AIMS Flow nyomkövetés aktív',
        notificationText: 'A jármű helyzete a munkavégzés alatt frissül.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _enqueuePosition,
      onError: (Object error) {
        _lastError = error.toString();
        _emit();
      },
      cancelOnError: false,
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_sendHeartbeat());
    });
    unawaited(_requestFlush());
    _emit();
  }

  void _enqueuePosition(Position position) {
    _lastPosition = position;
    _lastError = null;
    _emit();
    _positionTail = _positionTail.then(
      (_) => _queueAndFlush(position, source: 'stream'),
    ).catchError((Object error) {
      _lastError = 'GPS feldolgozási hiba: $error';
      _emit();
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!_enabled || _subscription == null) return;
    if (_lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) < const Duration(seconds: 40)) {
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) return;
    _lastPosition = position;
    await _queueAndFlush(position, source: 'heartbeat');
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/aims_tracking_queue.jsonl');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  Future<File> _quarantineFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aims_tracking_queue_corrupt.jsonl');
  }

  Future<T> _withQueueLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queueIoTail = _queueIoTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<String>> _queueSnapshot({int maxLines = 25}) {
    return _withQueueLock(() async {
      final file = await _queueFile();
      final lines = (await file.readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .toList();
      return lines.take(maxLines).toList();
    });
  }

  Future<bool> _removeQueuePrefix(List<String> consumed) {
    return _withQueueLock(() async {
      if (consumed.isEmpty) return true;
      final file = await _queueFile();
      final current = (await file.readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (current.length < consumed.length) return false;
      for (var i = 0; i < consumed.length; i++) {
        if (current[i] != consumed[i]) return false;
      }
      final remaining = current.sublist(consumed.length);
      await file.writeAsString(
        remaining.isEmpty ? '' : '${remaining.join('\n')}\n',
        flush: true,
      );
      return true;
    });
  }

  Future<void> _quarantineLine(String line, String reason) {
    return _withQueueLock(() async {
      final file = await _quarantineFile();
      final record = jsonEncode({
        'quarantinedAt': DateTime.now().toUtc().toIso8601String(),
        'reason': reason,
        'raw': line,
      });
      await file.writeAsString(
        '$record\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  Future<void> _queueAndFlush(Position position, {required String source}) async {
    if (!RoamingResilience.validCoordinates(
      position.latitude,
      position.longitude,
    )) {
      _lastError = 'Érvénytelen GPS pozíciót nem küldtem el.';
      _emit();
      return;
    }

    final countryCode = await CountryCodeService.instance.resolve(position);

    final point = <String, dynamic>{
      'pointId': RoamingResilience.pointId(
        deviceId: _deviceId,
        timestamp: position.timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      'deviceId': _deviceId,
      'vehicleLabel': _vehicleLabel,
      'countryCode': countryCode,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': RoamingResilience.finiteOrZero(position.accuracy),
      'speedMps': max(0, RoamingResilience.finiteOrZero(position.speed)),
      'heading': RoamingResilience.finiteOrZero(position.heading),
      'altitude': RoamingResilience.finiteOrZero(position.altitude),
      'source': source,
    };

    await _withQueueLock(() async {
      final file = await _queueFile();
      await file.writeAsString(
        '${jsonEncode(point)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    unawaited(_requestFlush());
  }

  Future<void> _requestFlush() async {
    if (_flushRunning) {
      _flushAgain = true;
      return;
    }
    _flushRunning = true;
    try {
      do {
        _flushAgain = false;
        await _flushQueuePass();
      } while (_flushAgain);
    } finally {
      _flushRunning = false;
    }
  }

  void _scheduleRetry(String message) {
    _flushFailures++;
    _lastError = message;
    _retryTimer?.cancel();
    final delay = RoamingResilience.retryDelay(_flushFailures);
    _retryTimer = Timer(delay, () => unawaited(_requestFlush()));
    _emit();
  }

  Future<void> _flushQueuePass() async {
    if (_endpoint.trim().isEmpty || _token.trim().isEmpty) {
      _lastError = 'A nyomkövető szerver kulcsa még nincs beállítva.';
      _emit();
      return;
    }

    final lines = await _queueSnapshot();
    if (lines.isEmpty) {
      _flushFailures = 0;
      return;
    }

    final consumed = <String>[];
    var networkFailed = false;

    for (final line in lines) {
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}

      if (payload == null) {
        await _quarantineLine(line, 'invalid_json');
        consumed.add(line);
        continue;
      }

      final captured =
          DateTime.tryParse(payload['timestamp']?.toString() ?? '');
      final now = DateTime.now().toUtc();
      payload['sentAt'] = now.toIso8601String();
      payload['delayed'] =
          captured != null && RoamingResilience.isDelayed(captured, now);

      try {
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_token',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          consumed.add(line);
          _lastSentAt = DateTime.now();
          _lastError = null;
          continue;
        }

        if (response.statusCode == 400 || response.statusCode == 422) {
          await _quarantineLine(
            line,
            'server_rejected_${response.statusCode}',
          );
          consumed.add(line);
          continue;
        }

        networkFailed = true;
        _scheduleRetry('Szerverhiba: HTTP ${response.statusCode}');
        break;
      } catch (_) {
        networkFailed = true;
        _scheduleRetry(
          'Nincs kapcsolat, a pozíció biztonságosan helyben sorban áll.',
        );
        break;
      }
    }

    if (consumed.isNotEmpty) {
      final removed = await _removeQueuePrefix(consumed);
      if (!removed) {
        _flushAgain = true;
      }
    }

    if (!networkFailed) {
      _flushFailures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      if (lines.length >= 25) {
        _flushAgain = true;
      }
      _emit();
    }
  }

  VehicleTrackingStatus get _status => VehicleTrackingStatus(
        enabled: _enabled,
        running: _subscription != null,
        deviceId: _deviceId,
        vehicleLabel: _vehicleLabel,
        lastPosition: _lastPosition,
        lastSentAt: _lastSentAt,
        lastError: _lastError,
      );

  void _emit() {
    if (!_statusController.isClosed) _statusController.add(_status);
  }
}