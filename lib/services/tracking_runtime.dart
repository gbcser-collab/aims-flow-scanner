import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/tracking_models.dart';
import 'aims_api_service.dart';
import 'device_identity_service.dart';
import 'tracking_repository.dart';

class TrackingRuntime extends ChangeNotifier {
  TrackingRuntime._();

  static final TrackingRuntime instance = TrackingRuntime._();

  static const int _maxRetainedSyncedPoints = 500;

  final TrackingRepository _repository = const TrackingRepository();
  final DeviceIdentityService _identityService = const DeviceIdentityService();
  final AimsApiService _api = const AimsApiService();

  TrackingSession? _session;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _syncTimer;
  Future<void> _positionTail = Future<void>.value();
  Future<void> _persistTail = Future<void>.value();

  bool _initialized = false;
  bool _busy = false;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _enrolled = false;
  int _syncFailureCount = 0;
  int _pendingSessionCount = 0;
  DateTime? _nextSyncAttemptAt;
  String _deviceState = 'unknown';
  String? _statusMessage;

  TrackingSession? get session => _session;
  bool get active => _session?.active == true;
  bool get busy => _busy || _syncing;
  bool get syncing => _syncing;
  String get deviceState => _deviceState;
  String? get statusMessage => _statusMessage;
  TrackingPoint? get latestPoint => _session?.latestPoint;
  int get queuedPointCount => _session?.queuedPointCount ?? 0;
  int get pendingSessionCount => _pendingSessionCount;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _session = await _repository.load();
    await _refreshPendingSessionCount();
    notifyListeners();

    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(syncNow()));
    unawaited(syncNow());

    if (_session?.active == true) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        try {
          await _startPositionStream();
        } catch (e) {
          _statusMessage = 'A GPS folytatása nem sikerült: $e';
          notifyListeners();
        }
      } else {
        _statusMessage = 'A fuvar aktív, de a GPS engedélyt újra meg kell adni.';
        notifyListeners();
      }
    }
  }

  Future<void> start({required String plate, required String reference}) async {
    if (_busy || _syncing || active) return;
    final cleanPlate = plate.trim().toUpperCase();
    if (cleanPlate.isEmpty) throw const FormatException('Add meg a jármű rendszámát.');

    _busy = true;
    _statusMessage = null;
    notifyListeners();
    try {
      await _ensureLocationPermission();

      final previous = _session;
      if (previous != null && !previous.active) {
        if (_needsDeferredSync(previous)) {
          await _repository.archive(previous);
        }
        await _repository.clear();
        _session = null;
        await _refreshPendingSessionCount();
      }

      final now = DateTime.now();
      _session = TrackingSession(
        id: 'trip_${now.microsecondsSinceEpoch}',
        plate: cleanPlate,
        reference: reference.trim(),
        startedAt: now,
        active: true,
      );
      await _persistCurrent();
      await _startPositionStream();

      try {
        final current = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
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
      try {
        await _positionTail;
      } catch (_) {}

      final current = _session;
      if (current != null && current.active) {
        _session = current.copyWith(active: false, stoppedAt: DateTime.now());
        await _persistCurrent();
      }
      await forceSyncNow();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> resumeWithPermission() async {
    if (!active) return;
    await _ensureLocationPermission();
    await _startPositionStream();
  }

  Future<void> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const FormatException('A telefon helymeghatározása ki van kapcsolva.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
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
              notificationText: 'Az aktív fuvar GPS-pozíciója megosztásra kerül a Logistic-AIMS admin felé.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
          );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _enqueuePosition,
      onError: (Object error) {
        _statusMessage = 'GPS hiba: $error';
        notifyListeners();
      },
    );
  }

  void _enqueuePosition(Position position) {
    _positionTail = _positionTail
        .catchError((_) {})
        .then((_) => _handlePosition(position))
        .catchError((Object error) {
      _statusMessage = 'GPS mentési hiba: $error';
      notifyListeners();
    });
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
    final nextPoints = [...current.points, point];
    _session = current.copyWith(points: nextPoints, clearLastSyncError: true);
    await _persistCurrent();
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> syncNow() => _requestSync(force: false);

  Future<void> forceSyncNow() => _requestSync(force: true);

  Future<void> _requestSync({required bool force}) async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }

    final nextAttempt = _nextSyncAttemptAt;
    if (!force && nextAttempt != null && DateTime.now().isBefore(nextAttempt)) return;

    _syncing = true;
    notifyListeners();
    try {
      await _performSync();
      _syncFailureCount = 0;
      _nextSyncAttemptAt = null;
    } on AimsApiException catch (e) {
      if (e.code == 'device_pending') _deviceState = 'pending';
      if (e.code == 'device_revoked') _deviceState = 'revoked';
      if (e.statusCode == 401 || e.statusCode == 404) _enrolled = false;
      _statusMessage = 'GPS szinkron várakozik: ${e.code}';
      await _storeCurrentSyncError(e.code);
      _scheduleBackoff();
    } catch (e) {
      _statusMessage = 'Offline GPS sor: ${_session?.queuedPointCount ?? 0} pont.';
      await _storeCurrentSyncError(e.toString());
      _scheduleBackoff();
    } finally {
      _syncing = false;
      notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _performSync() async {
    final current = _session;
    final pendingSessions = await _repository.loadPending();
    _pendingSessionCount = pendingSessions.length;
    if (current == null && pendingSessions.isEmpty) return;

    final identity = await _identityService.loadOrCreate();
    if (!_enrolled) {
      final labelPlate = current?.plate ?? (pendingSessions.isNotEmpty ? pendingSessions.last.plate : 'GPS');
      final enroll = await _api.enroll(identity, label: 'AIMS Flow • $labelPlate');
      _deviceState = (enroll['state'] as String?) ?? _deviceState;
      _enrolled = true;
    }

    final status = await _api.deviceStatus(identity);
    _deviceState = (status['state'] as String?) ?? _deviceState;
    if (_deviceState != 'approved') {
      _statusMessage = _deviceState == 'revoked'
          ? 'A készülék hozzáférését az admin visszavonta.'
          : 'A készülék jóváhagyásra vár. A GPS pontok addig offline sorban maradnak.';
      _nextSyncAttemptAt = DateTime.now().add(const Duration(minutes: 2));
      return;
    }

    for (final archived in pendingSessions) {
      final updated = await _syncArchivedSession(identity, archived);
      if (_isFullySynced(updated)) {
        await _repository.removeArchived(updated.id);
      }
    }
    await _refreshPendingSessionCount();

    await _syncCurrentSession(identity);

    final working = _session;
    final pendingText = _pendingSessionCount == 0 ? '' : ' • $_pendingSessionCount korábbi fuvar vár.';
    _statusMessage = working?.active == true
        ? 'Élő GPS szinkron aktív.$pendingText'
        : 'A fuvar lezárva, a nyomkövetés leállt.$pendingText';
  }

  Future<TrackingSession> _syncArchivedSession(
    DeviceIdentity identity,
    TrackingSession initial,
  ) async {
    var working = initial;
    try {
      if (!working.serverStarted) {
        await _api.startTracking(identity, working);
        working = working.copyWith(serverStarted: true, clearLastSyncError: true);
        await _repository.archive(working);
      }

      while (true) {
        final pending = working.points.where((point) => !point.synced).take(100).toList();
        if (pending.isEmpty) break;
        await _api.syncTrackingPoints(identity, working, pending);
        final sentIds = pending.map((point) => point.id).toSet();
        final updated = working.points
            .map((point) => sentIds.contains(point.id) ? point.copyWith(synced: true) : point)
            .toList();
        working = working.copyWith(
          points: _compactPoints(updated),
          clearLastSyncError: true,
        );
        await _repository.archive(working);
      }

      if (!working.active && !working.serverStopped) {
        await _api.stopTracking(identity, working);
        working = working.copyWith(serverStopped: true, clearLastSyncError: true);
        await _repository.archive(working);
      }
      return working;
    } catch (e) {
      working = working.copyWith(lastSyncError: e.toString());
      await _repository.archive(working);
      rethrow;
    }
  }

  Future<void> _syncCurrentSession(DeviceIdentity identity) async {
    var working = _session;
    if (working == null) return;
    final sessionId = working.id;

    if (!working.serverStarted) {
      await _api.startTracking(identity, working);
      final latest = _session;
      if (latest == null || latest.id != sessionId) return;
      working = latest.copyWith(serverStarted: true, clearLastSyncError: true);
      _session = working;
      await _persistCurrent();
    }

    while (true) {
      working = _session;
      if (working == null || working.id != sessionId) return;
      final pending = working.points.where((point) => !point.synced).take(100).toList();
      if (pending.isEmpty) break;

      await _api.syncTrackingPoints(identity, working, pending);
      final sentIds = pending.map((point) => point.id).toSet();
      final latest = _session;
      if (latest == null || latest.id != sessionId) return;
      final updated = latest.points
          .map((point) => sentIds.contains(point.id) ? point.copyWith(synced: true) : point)
          .toList();
      working = latest.copyWith(
        points: _compactPoints(updated),
        clearLastSyncError: true,
      );
      _session = working;
      await _persistCurrent();
    }

    working = _session;
    if (working != null && working.id == sessionId && !working.active && !working.serverStopped) {
      await _api.stopTracking(identity, working);
      final latest = _session;
      if (latest != null && latest.id == sessionId) {
        _session = latest.copyWith(serverStopped: true, clearLastSyncError: true);
        await _persistCurrent();
      }
    }
  }

  List<TrackingPoint> _compactPoints(List<TrackingPoint> points) {
    final syncedCount = points.where((point) => point.synced).length;
    var drop = max(0, syncedCount - _maxRetainedSyncedPoints);
    if (drop == 0) return points;

    final compacted = <TrackingPoint>[];
    for (final point in points) {
      if (point.synced && drop > 0) {
        drop--;
        continue;
      }
      compacted.add(point);
    }
    return compacted;
  }

  bool _needsDeferredSync(TrackingSession session) {
    return session.queuedPointCount > 0 || (session.serverStarted && !session.serverStopped);
  }

  bool _isFullySynced(TrackingSession session) {
    return !session.active && session.queuedPointCount == 0 && session.serverStarted && session.serverStopped;
  }

  Future<void> _storeCurrentSyncError(String error) async {
    final current = _session;
    if (current == null) return;
    _session = current.copyWith(lastSyncError: error);
    await _persistCurrent();
  }

  void _scheduleBackoff() {
    _syncFailureCount = min(_syncFailureCount + 1, 6);
    const delays = <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
    ];
    _nextSyncAttemptAt = DateTime.now().add(delays[_syncFailureCount - 1]);
  }

  Future<void> _refreshPendingSessionCount() async {
    _pendingSessionCount = (await _repository.loadPending()).length;
  }

  Future<void> _persistCurrent() {
    _persistTail = _persistTail.catchError((_) {}).then((_) async {
      final current = _session;
      if (current != null) await _repository.save(current);
    });
    return _persistTail;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
