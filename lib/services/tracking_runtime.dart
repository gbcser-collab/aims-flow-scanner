import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/tracking_models.dart';
import 'device_identity_service.dart';
import 'tracking_api_service.dart';
import 'tracking_repository.dart';

class TrackingRuntime extends ChangeNotifier {
  TrackingRuntime._();

  static final TrackingRuntime instance = TrackingRuntime._();

  final TrackingRepository _repository = const TrackingRepository();
  final DeviceIdentityService _identity = const DeviceIdentityService();
  final TrackingApiService _api = const TrackingApiService();

  TrackingSession? _session;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _syncTimer;
  bool _initialized = false;
  bool _busy = false;
  String _deviceState = 'unknown';
  String? _statusMessage;

  TrackingSession? get session => _session;
  bool get active => _session?.active == true;
  bool get busy => _busy;
  String get deviceState => _deviceState;
  String? get statusMessage => _statusMessage;
  TrackingPoint? get latestPoint => _session?.latestPoint;
  int get queuedPointCount => _session?.queuedPointCount ?? 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _session = await _repository.load();
    notifyListeners();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(syncNow()));
    unawaited(syncNow());
    if (_session?.active == true) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        await _startPositionStream();
      }
    }
  }

  Future<void> start({required String plate, required String reference}) async {
    if (_busy || active) return;
    final cleanPlate = plate.trim().toUpperCase();
    if (cleanPlate.isEmpty) throw const FormatException('Add meg a jármű rendszámát.');
    _busy = true;
    _statusMessage = null;
    notifyListeners();
    try {
      await _ensureLocationPermission();
      final now = DateTime.now();
      _session = TrackingSession(
        id: 'trip_${now.microsecondsSinceEpoch}',
        plate: cleanPlate,
        reference: reference.trim(),
        startedAt: now,
        active: true,
      );
      await _repository.save(_session!);
      await _startPositionStream();
      try {
        final current = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
        await _handlePosition(current);
      } catch (_) {}
      unawaited(syncNow());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_busy || _session == null || !active) return;
    _busy = true;
    notifyListeners();
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _session = _session!.copyWith(active: false, stoppedAt: DateTime.now());
      await _repository.save(_session!);
      await syncNow();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const FormatException('A telefon helymeghatározása ki van kapcsolva.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const FormatException('A helyengedély végleg tiltva van. Engedélyezd az Android beállításokban.');
    }
    if (permission == LocationPermission.denied) {
      throw const FormatException('A GPS nyomkövetéshez helyengedély szükséges.');
    }
  }

  Future<void> _startPositionStream() async {
    await _positionSubscription?.cancel();
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            intervalDuration: const Duration(minutes: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'AIMS Flow nyomkövetés aktív',
              notificationText: 'Az aktív fuvar GPS-pozíciója megosztásra kerül.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => unawaited(_handlePosition(position)),
      onError: (Object error) {
        _statusMessage = 'GPS hiba: $error';
        notifyListeners();
      },
    );
  }

  Future<void> _handlePosition(Position position) async {
    final current = _session;
    if (current == null || !current.active) return;
    final point = TrackingPoint(
      id: 'gps_${position.timestamp.microsecondsSinceEpoch}',
      capturedAt: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speedMps: position.speed,
      heading: position.heading,
      altitude: position.altitude,
      isMocked: position.isMocked,
    );
    _session = current.copyWith(points: [...current.points, point], clearLastSyncError: true);
    await _repository.save(_session!);
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    final current = _session;
    if (current == null) return;
    try {
      final credentials = await _identity.getOrCreateCredentials();
      final enroll = await _api.enroll(credentials, label: 'AIMS Flow • ${current.plate}');
      _deviceState = (enroll['state'] as String?) ?? _deviceState;
      final status = await _api.deviceStatus(credentials);
      _deviceState = (status['state'] as String?) ?? _deviceState;
      if (_deviceState != 'approved') {
        _statusMessage = _deviceState == 'revoked'
            ? 'A készülék hozzáférését az admin visszavonta.'
            : 'A készülék jóváhagyásra vár. A GPS pontok offline sorban maradnak.';
        notifyListeners();
        return;
      }

      var working = _session!;
      if (!working.serverStarted) {
        await _api.startTracking(credentials, working);
        working = working.copyWith(serverStarted: true, clearLastSyncError: true);
        _session = working;
        await _repository.save(working);
      }

      while (true) {
        working = _session!;
        final pending = working.points.where((point) => !point.synced).take(100).toList();
        if (pending.isEmpty) break;
        await _api.syncPoints(credentials, working, pending);
        final sent = pending.map((point) => point.id).toSet();
        working = working.copyWith(
          points: working.points.map((point) => sent.contains(point.id) ? point.copyWith(synced: true) : point).toList(),
          clearLastSyncError: true,
        );
        _session = working;
        await _repository.save(working);
      }

      working = _session!;
      if (!working.active && !working.serverStopped) {
        await _api.stopTracking(credentials, working);
        working = working.copyWith(serverStopped: true, clearLastSyncError: true);
        _session = working;
        await _repository.save(working);
      }
      _statusMessage = working.active ? 'Élő GPS szinkron aktív.' : 'A fuvar lezárva, a nyomkövetés leállt.';
      notifyListeners();
    } on TrackingApiException catch (e) {
      if (e.code == 'device_pending') _deviceState = 'pending';
      if (e.code == 'device_revoked') _deviceState = 'revoked';
      _statusMessage = 'GPS szinkron várakozik: ${e.code}';
      final currentSession = _session;
      if (currentSession != null) {
        _session = currentSession.copyWith(lastSyncError: e.code);
        await _repository.save(_session!);
      }
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Offline GPS sor: ${_session?.queuedPointCount ?? 0} pont.';
      final currentSession = _session;
      if (currentSession != null) {
        _session = currentSession.copyWith(lastSyncError: e.toString());
        await _repository.save(_session!);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
