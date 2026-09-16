import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VehicleTrackingStatus {
  const VehicleTrackingStatus({
    required this.enabled,
    required this.running,
    required this.deviceId,
    this.lastPosition,
    this.lastSentAt,
    this.lastError,
  });

  final bool enabled;
  final bool running;
  final String deviceId;
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

  // Production builds should inject the write endpoint and token at build time.
  static const _endpoint = String.fromEnvironment(
    'AIMS_TRACKING_ENDPOINT',
    defaultValue: 'https://logistic-aims.hu/api/aims-tracking/ingest.php',
  );
  static const _token = String.fromEnvironment('AIMS_TRACKING_TOKEN', defaultValue: '');

  final _statusController = StreamController<VehicleTrackingStatus>.broadcast();
  StreamSubscription<Position>? _subscription;
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
    if (_enabled) {
      await _startLocationStream(requestPermission: false);
    }
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
    _emit();
  }

  Future<void> setVehicleLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    _vehicleLabel = label.trim();
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

    const settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      intervalDuration: Duration(seconds: 15),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'AIMS Flow nyomkövetés aktív',
        notificationText: 'A jármű helyzete a munkavégzés alatt frissül.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) async {
        _lastPosition = position;
        _lastError = null;
        _emit();
        await _queueAndFlush(position);
      },
      onError: (Object error) {
        _lastError = error.toString();
        _emit();
      },
      cancelOnError: false,
    );
    _emit();
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/aims_tracking_queue.jsonl');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  Future<void> _queueAndFlush(Position position) async {
    final point = <String, dynamic>{
      'deviceId': _deviceId,
      'vehicleLabel': _vehicleLabel,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'speedMps': position.speed,
      'heading': position.heading,
      'altitude': position.altitude,
    };

    final file = await _queueFile();
    await file.writeAsString('${jsonEncode(point)}\n', mode: FileMode.append, flush: true);
    await _flushQueue();
  }

  Future<void> _flushQueue() async {
    if (_endpoint.trim().isEmpty || _token.trim().isEmpty) {
      _lastError = 'A nyomkövető szerver kulcsa még nincs beállítva.';
      _emit();
      return;
    }

    final file = await _queueFile();
    final lines = (await file.readAsLines()).where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      try {
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_token',
              },
              body: line,
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          remaining.addAll(lines.sublist(i));
          _lastError = 'Szerverhiba: HTTP ${response.statusCode}';
          break;
        }
        _lastSentAt = DateTime.now();
        _lastError = null;
      } catch (error) {
        remaining.addAll(lines.sublist(i));
        _lastError = 'Nincs kapcsolat, a pozíció helyben sorban áll.';
        break;
      }
    }

    await file.writeAsString(
      remaining.isEmpty ? '' : '${remaining.join('\n')}\n',
      flush: true,
    );
    _emit();
  }

  VehicleTrackingStatus get _status => VehicleTrackingStatus(
        enabled: _enabled,
        running: _subscription != null,
        deviceId: _deviceId,
        lastPosition: _lastPosition,
        lastSentAt: _lastSentAt,
        lastError: _lastError,
      );

  void _emit() {
    if (!_statusController.isClosed) _statusController.add(_status);
  }
}
