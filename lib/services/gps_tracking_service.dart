import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService._();

  static final GpsTrackingService instance = GpsTrackingService._();

  StreamSubscription<Position>? _subscription;
  bool _initialized = false;
  bool _active = false;
  bool _busy = false;
  String _plate = '';
  String _reference = '';
  DateTime? _startedAt;
  DateTime? _stoppedAt;
  Position? _latest;
  String? _error;

  bool get active => _active;
  bool get busy => _busy;
  String get plate => _plate;
  String get reference => _reference;
  DateTime? get startedAt => _startedAt;
  DateTime? get stoppedAt => _stoppedAt;
  Position? get latest => _latest;
  String? get error => _error;

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    return File('${root.path}/aims_gps_trip.json');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _active = decoded['active'] == true;
          _plate = decoded['plate']?.toString() ?? '';
          _reference = decoded['reference']?.toString() ?? '';
          _startedAt = DateTime.tryParse(decoded['startedAt']?.toString() ?? '')?.toLocal();
          _stoppedAt = DateTime.tryParse(decoded['stoppedAt']?.toString() ?? '')?.toLocal();
        }
      }
    } catch (_) {}
    if (_active) {
      try {
        await _ensurePermission();
        await _startStream();
      } catch (e) {
        _error = e.toString();
      }
    }
    notifyListeners();
  }

  Future<void> start({required String plate, required String reference}) async {
    if (_busy || _active) return;
    final cleanPlate = plate.trim().toUpperCase();
    if (cleanPlate.isEmpty) throw const FormatException('Add meg a jármű rendszámát.');
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _ensurePermission();
      _plate = cleanPlate;
      _reference = reference.trim();
      _startedAt = DateTime.now();
      _stoppedAt = null;
      _active = true;
      await _save();
      await _startStream();
      try {
        _latest = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
      } catch (_) {}
      await _save();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_busy || !_active) return;
    _busy = true;
    notifyListeners();
    try {
      await _subscription?.cancel();
      _subscription = null;
      _active = false;
      _stoppedAt = DateTime.now();
      await _save();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const FormatException('A telefon helymeghatározása ki van kapcsolva.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const FormatException('A helyengedély végleg tiltva van. Nyisd meg az Android alkalmazásbeállításait.');
    }
    if (permission == LocationPermission.denied) throw const FormatException('A GPS használatához helyengedély szükséges.');
  }

  Future<void> _startStream() async {
    await _subscription?.cancel();
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
            intervalDuration: const Duration(seconds: 30),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'AIMS Flow GPS aktív',
              notificationText: 'Az aktív fuvar helyadatai rögzítés alatt állnak.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) async {
        _latest = position;
        _error = null;
        await _save();
        notifyListeners();
      },
      onError: (Object e) {
        _error = 'GPS hiba: $e';
        notifyListeners();
      },
    );
  }

  Future<void> _save() async {
    final file = await _file();
    await file.writeAsString(jsonEncode({
      'active': _active,
      'plate': _plate,
      'reference': _reference,
      'startedAt': _startedAt?.toUtc().toIso8601String(),
      'stoppedAt': _stoppedAt?.toUtc().toIso8601String(),
      'latest': _latest == null
          ? null
          : {
              'latitude': _latest!.latitude,
              'longitude': _latest!.longitude,
              'accuracy': _latest!.accuracy,
              'speed': _latest!.speed,
              'timestamp': _latest!.timestamp.toUtc().toIso8601String(),
            },
    }), flush: true);
  }
}
