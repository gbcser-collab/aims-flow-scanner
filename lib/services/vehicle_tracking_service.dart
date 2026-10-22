import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'country_code_service.dart';
import 'device_identity_service.dart';
import 'flow_account_service.dart';
import 'flow_queue_summary.dart';
import 'flow_local_journal.dart';
import 'flow_multipart_transport.dart';
import 'tracking_point_queue.dart';
import 'tracking_queue_sync.dart';
import 'tracking_shutdown.dart';
import 'tracking_workday_guard.dart';
import 'local_serial_executor.dart';
import 'tracking_policy.dart';
import 'tracking_platform.dart';
import 'gps_point_quality.dart';
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
    this.gpsQuality = 'unknown',
    this.gpsScore = 0,
    this.queueDepth = 0,
    this.lastFixAt,
    this.rejectedFixes = 0,
    this.stableLatitude,
    this.stableLongitude,
    this.stationary = false,
    this.sampleSeconds = 15,
    this.nextRetryAt,
  });

  final bool enabled;
  final bool running;
  final String deviceId;
  final String vehicleLabel;
  final Position? lastPosition;
  final DateTime? lastSentAt;
  final String? lastError;
  final String gpsQuality;
  final int gpsScore;
  final int queueDepth;
  final DateTime? lastFixAt;
  final int rejectedFixes;
  final double? stableLatitude;
  final double? stableLongitude;
  final bool stationary;
  final int sampleSeconds;
  final DateTime? nextRetryAt;
}

/// Driver-friendly, offline-first vehicle tracking.
///
/// GPS points are stored locally first and uploaded through the revocable
/// FLOW ID/PIN driver session. No shared server bearer token is compiled into
/// the Android application. Tracking is tied to the active workday: it starts
/// after job acceptance and stops when the driver closes the workday.
class VehicleTrackingService {
  VehicleTrackingService._();

  static final VehicleTrackingService instance = VehicleTrackingService._();

  static const _enabledKey = 'aims_tracking_enabled';
  static const _deviceIdKey = 'aims_tracking_device_id';
  static const _vehicleLabelKey = 'aims_tracking_vehicle_label';
  static const _workdayKey = 'aims_flow_workday_v2';
  static const _legacyWorkdayKey = 'aims_flow_workday_v1';

  static const _endpoint = String.fromEnvironment(
    'AIMS_TRACKING_ENDPOINT',
    defaultValue:
        'https://logistic-aims.hu/api/aims-tracking/session/ingest.php',
  );

  final _statusController =
      StreamController<VehicleTrackingStatus>.broadcast();

  StreamSubscription<Position>? _subscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  Timer? _healthTimer;
  Timer? _retryTimer;
  Timer? _streamRecoveryTimer;

  final _queue = TrackingPointQueue(directory: getApplicationDocumentsDirectory);
  final _positions = LocalSerialExecutor();
  final _lifecycle = LocalSerialExecutor();
  final _workdayGuard = TrackingWorkdayGuard(
    readJournal: () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_workdayKey) ?? prefs.getString(_legacyWorkdayKey);
    },
    loadSession: FlowSessionStore.instance.load,
  );

  bool _flushRunning = false;
  bool _flushAgain = false;
  bool _queueDepthLoaded = false;
  bool _identityLoaded = false;
  Future<void>? _identityLoading;
  final _retryGate = TrackingRetryGate();
  final _policy = TrackingPolicy();
  bool _starting = false;
  bool _restarting = false;
  bool _healthBusy = false;
  Duration _activeInterval = const Duration(seconds: 15);
  Position? _motionAnchor;
  DateTime? _lastReceivedAt;
  int _streamFailures = 0;
  int _queueDepth = 0;
  int _rejectedFixes = 0;

  Position? _lastPosition;
  Position? _lastAcceptedPosition;
  DateTime? _lastFixAt;
  DateTime? _lastSentAt;
  DateTime? _streamStartedAt;
  String? _lastError;
  String _gpsQuality = 'unknown';
  int _gpsScore = 0;
  double? _stableLatitude;
  double? _stableLongitude;
  String _deviceId = '';
  String _vehicleLabel = '';
  bool _enabled = false;
  int _locationGeneration = 0;

  Stream<VehicleTrackingStatus> get statusStream => _statusController.stream;

  bool get _runningUnderFlutterTest {
    try {
      return WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasActiveWorkday({FlowAccountSession? session, DateTime? capturedAt}) async {
    try {
      return await _workdayGuard.isActive(session: session, capturedAt: capturedAt);
    } catch (_) {
      // Preserve the scheduler, not permission to save unauthenticated points.
      _lastError = 'A munkanap állapota átmenetileg nem olvasható. Automatikus újraellenőrzés.';
      _ensureSupervisor();
      _emit();
      rethrow;
    }
  }

  Future<VehicleTrackingStatus> currentStatus() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    return _status;
  }

  Future<FlowQueueSummary> queueSummary(FlowAccountSession session) async =>
      FlowQueueSummary.fromRecords((await _queue.snapshot()).map(TrackingQueueSync.decode),
        session, timeKey: 'timestamp', archived: await _queue.quarantinedCount());

  Future<Position?> currentPositionForAction() async {
    await _loadIdentity();

    bool usable(Position? position) {
      if (position == null) return false;
      final assessment = GpsPointQuality.assess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: RoamingResilience.finiteOrZero(position.accuracy),
        speedMps: max(
          0.0,
          RoamingResilience.finiteOrZero(position.speed),
        ),
        capturedAt: position.timestamp,
      );
      return assessment.accepted &&
          assessment.quality != GpsFixQuality.stale &&
          assessment.score >= 55;
    }

    if (usable(_lastAcceptedPosition)) return _lastAcceptedPosition;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final fallback = await Geolocator.getLastKnownPosition();
        return usable(fallback) ? fallback : null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!usable(position)) return null;
      _lastPosition = position;
      _lastAcceptedPosition = position;
      _lastFixAt = position.timestamp;
      _emit();
      return position;
    } on TimeoutException {
      final fallback =
          _lastAcceptedPosition ?? await Geolocator.getLastKnownPosition();
      return usable(fallback) ? fallback : null;
    } catch (_) {
      final fallback =
          _lastAcceptedPosition ?? await Geolocator.getLastKnownPosition();
      return usable(fallback) ? fallback : null;
    }
  }

  /// Starts tracking for an active workday. The test guard prevents widget
  /// tests from invoking platform GPS plugins while keeping production logic
  /// identical.
  Future<bool> beginWorkday(String plate) => _lifecycle.run(() async {
    await _setVehicleLabel(plate);
    if (_runningUnderFlutterTest) return true;
    return _enableWithPermission();
  });

  /// Stop foreground GPS first; a stalled upload never delays local closure.
  Future<void> endWorkday() async {
    if (_runningUnderFlutterTest) return;
    _lastError = null;
    await stopTrackingBeforeSync(stop: () => _lifecycle.run(() async {
      // A late close must not stop a newer, already durable workday.
      if (await _hasActiveWorkday()) { await _recover(); return; }
      await _disable();
    }), sync: _requestFlush);
  }

  Future<void> syncPending() => _requestFlush(force: true);

  Future<void> recover() => _lifecycle.run(_recover);

  Future<void> _recover() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    if (!await _hasActiveWorkday()) {
      if (_enabled || _subscription != null || _healthTimer != null) await _disable();
      unawaited(_requestFlush());
      return;
    }
    // The durable workday is the source of truth, including a start that was
    // interrupted before the old enabled preference was written.
    if (!_enabled) {
      _enabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
    }
    if (_subscription == null && _streamRecoveryTimer == null) {
      await _startLocationStream(requestPermission: false);
    } else {
      await _applyProfile();
    }
    unawaited(_requestFlush());
  }

  Future<void> startIfEnabled() => recover();

  Future<bool> enableWithPermission() => _lifecycle.run(_enableWithPermission);

  Future<bool> _enableWithPermission() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();

    if (!await _hasActiveWorkday()) {
      await _disable();
      _lastError =
          'A nyomkövetés a munkanap indulásakor automatikusan bekapcsol.';
      _emit();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    _enabled = true;
    _ensureSupervisor();

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

    _lastError = null;
    await _startLocationStream(requestPermission: false);
    return _subscription != null;
  }

  Future<void> disable() => _lifecycle.run(_disable);

  Future<void> _disable() async {
    _workdayGuard.retryRequired = false;
    _locationGeneration++;
    _enabled = false;
    final subscription = _subscription;
    _subscription = null;
    final serviceStatus = _serviceStatusSubscription;
    _serviceStatusSubscription = null;
    _policy.reset();
    _motionAnchor = null;
    _lastReceivedAt = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _streamStartedAt = null;
    _streamFailures = 0;
    try {
      await finishTrackingCleanup([
        () async { await subscription?.cancel(); },
        () async { await serviceStatus?.cancel(); },
        () async {
          final prefs = await SharedPreferences.getInstance();
          if (!await prefs.setBool(_enabledKey, false)) {
            throw StateError('A követés leállításának mentése nem sikerült.');
          }
        },
        () async {
          if (Platform.isAndroid && !_runningUnderFlutterTest) await TrackingPlatform.setActive(false);
        },
      ]);
    } catch (_) {
      _lastError = 'A GPS leállítása nem igazolható teljesen. Ellenőrizd a követési értesítést.';
      rethrow;
    } finally {
      _emit();
    }
  }

  Future<void> setVehicleLabel(String label) => _lifecycle.run(() => _setVehicleLabel(label));

  Future<void> _setVehicleLabel(String label) async {
    await _loadIdentity();
    final cleaned = label
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final prefs = await SharedPreferences.getInstance();
    if (_vehicleLabel != cleaned) {
      if (_subscription != null) await _disable();
      _locationGeneration++;
      _lastAcceptedPosition = null;
      _lastPosition = null;
      _stableLatitude = null;
      _stableLongitude = null;
      _lastFixAt = null;
    }
    _vehicleLabel = cleaned;
    await prefs.setString(_vehicleLabelKey, cleaned);
    _emit();
  }

  Future<void> _loadIdentity() async {
    if (_identityLoaded) return;
    final pending = _identityLoading;
    if (pending != null) return pending;
    final loading = _readIdentity();
    _identityLoading = loading;
    try { await loading; } finally { _identityLoading = null; }
  }

  Future<void> _readIdentity() async {
    final generation = _locationGeneration;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final label = (prefs.getString(_vehicleLabelKey) ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.trim().isEmpty) {
      id = (await const DeviceIdentityService().loadOrCreate()).deviceId;
    }
    if (generation != _locationGeneration) return;
    _deviceId = id;
    _enabled = enabled;
    _vehicleLabel = label;
    _identityLoaded = true;
  }

  Future<void> _startLocationStream({required bool requestPermission}) async {
    if (_subscription != null || _starting || !_enabled) return;
    _starting = true;
    final generation = ++_locationGeneration;
    try {
      if (!await _hasActiveWorkday()) {
        await _disable();
        return;
      }
      _ensureSupervisor();
      if (!await Geolocator.isLocationServiceEnabled()) {
        _lastError = 'A helymeghatározás ki van kapcsolva. Kapcsold vissza a telefonon.';
        _emit();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (requestPermission && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _lastError = 'A helyhozzáférés nincs engedélyezve. Ellenőrizd a követés beállításait.';
        _emit();
        return;
      }
      final foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (Platform.isAndroid && !foreground && permission != LocationPermission.always) {
        _lastError = 'A GPS újraindításához nyisd meg az appot, vagy engedélyezd a helyhozzáférést mindig.';
        _emit();
        return;
      }
      final streamSession = await FlowSessionStore.instance.load();
      if (streamSession == null || !_enabled || generation != _locationGeneration ||
          !await _hasActiveWorkday(session: streamSession)) return;
      _activeInterval = _policy.sampleInterval;
      final LocationSettings settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              // Timed stationary fixes avoid extra getCurrentPosition requests.
              distanceFilter: 0,
              intervalDuration: _activeInterval,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'AIMS FLOW – munkanapkövetés',
                notificationText: 'A helyzet a munkanap lezárásáig frissül. Megnyitás: részletek.',
                enableWakeLock: false,
                enableWifiLock: false,
                setOngoing: true,
              ),
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
      if (Platform.isAndroid && !_runningUnderFlutterTest) await TrackingPlatform.setActive(true);
      if (!_enabled || generation != _locationGeneration) return;
      _streamStartedAt = DateTime.now();
      _lastReceivedAt = null;
      _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (generation != _locationGeneration) return;
          _lastReceivedAt = DateTime.now();
          _streamFailures = 0;
          _enqueuePosition(position, streamSession, generation);
        },
        onError: (Object error) {
          if (generation != _locationGeneration) return;
          _lastError = 'A GPS-kapcsolat megszakadt. Automatikus újrapróbálás.';
          _emit();
          _scheduleStreamRecovery(generation);
        },
        onDone: () => _scheduleStreamRecovery(generation),
        cancelOnError: false,
      );
      _emit();
    } catch (_) {
      if (_enabled && generation == _locationGeneration) {
        _lastError = 'A GPS indítása nem sikerült. Automatikus újrapróbálás.';
        _scheduleStreamRecovery(generation);
        _emit();
      }
    } finally {
      _starting = false;
    }
  }

  void _ensureSupervisor() {
    _healthTimer ??= Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_checkHealth()));
    _serviceStatusSubscription ??= Geolocator.getServiceStatusStream().listen((status) {
      if ((_enabled || _workdayGuard.retryRequired) && status == ServiceStatus.enabled) {
        unawaited(recover().catchError((Object _) {}));
      }
    }, onError: (Object _) {});
  }

  Future<void> _checkHealth() async {
    if (_healthBusy || (!_enabled && !_workdayGuard.retryRequired)) return;
    _healthBusy = true;
    try {
      await _lifecycle.run(() async {
      if (_workdayGuard.retryRequired) { await _recover(); return; }
      if (!_enabled) return;
      if (!await _hasActiveWorkday()) { await _disable(); return; }
      final since = _lastReceivedAt ?? _streamStartedAt;
      if (_streamRecoveryTimer == null && (_subscription == null ||
          (since != null && DateTime.now().difference(since) > _policy.staleAfter))) {
        await _restartLocationStream();
      } else {
        await _applyProfile();
      }
      });
      await _requestFlush();
    } catch (_) {
      _lastError = 'A követés ellenőrzése nem sikerült. Az állapotot újra ellenőrizzük.';
    } finally {
      _healthBusy = false;
      _emit();
    }
  }

  Future<void> _applyProfile() async {
    if (_subscription == null || _activeInterval == _policy.sampleInterval) return;
    // Keep an already running foreground service intact if Android would
    // forbid restarting it from the background with while-in-use permission.
    if (Platform.isAndroid && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
        await Geolocator.checkPermission() != LocationPermission.always) return;
    await _restartLocationStream();
  }

  Future<void> _restartLocationStream() async {
    if (_restarting || _starting || !_enabled) return;
    _restarting = true;
    try {
      if (!await _hasActiveWorkday()) { await _disable(); return; }
      if (Platform.isAndroid && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
          await Geolocator.checkPermission() != LocationPermission.always) return;
      _locationGeneration++;
      final current = _subscription;
      _subscription = null;
      await current?.cancel();
      _streamStartedAt = null;
      await _startLocationStream(requestPermission: false);
    } finally {
      _restarting = false;
    }
  }

  void _scheduleStreamRecovery(int generation) {
    if (!_enabled || generation != _locationGeneration) return;
    _locationGeneration++;
    _streamFailures++;
    final current = _subscription;
    _subscription = null;
    if (current != null) unawaited(current.cancel().catchError((Object _) {}));
    _streamRecoveryTimer?.cancel();
    final delay = Duration(seconds: [2, 5, 15, 30, 60, 120][(_streamFailures - 1).clamp(0, 5)]);
    _streamRecoveryTimer = Timer(delay, () {
      _streamRecoveryTimer = null;
      if (_enabled && _subscription == null) unawaited(recover().catchError((Object _) {}));
    });
  }

  void _enqueuePosition(Position position, FlowAccountSession session, int generation) {
    unawaited(_positions.run(() async {
      if (generation != _locationGeneration) return;
      await _queueAndFlush(position, source: 'stream', capturedSession: session);
    }).catchError((Object error) {
      _lastError = 'GPS feldolgozási hiba: $error';
      _emit();
    }));
  }

  Future<void> _ensureQueueDepthLoaded() async {
    if (_queueDepthLoaded) return;
    _queueDepth = await _queue.count();
    _queueDepthLoaded = true;
  }

  Future<void> _queueAndFlush(
    Position position, {
    required String source,
    required FlowAccountSession capturedSession,
  }) async {
    final generation = _locationGeneration;
    final session = await FlowSessionStore.instance.load();
    if (!_enabled || session == null ||
        session.sessionToken != capturedSession.sessionToken ||
        session.flowId != capturedSession.flowId ||
        flowJournalPlate(session.plate) != flowJournalPlate(capturedSession.plate) ||
        !await _hasActiveWorkday(session: session, capturedAt: position.timestamp)) return;
    final originalDevice = _deviceId;
    final originalPlate = flowJournalPlate(session.plate);
    if (originalDevice.isEmpty || originalPlate.isEmpty) return;
    if (!RoamingResilience.validCoordinates(
      position.latitude,
      position.longitude,
    )) {
      _lastError = 'Érvénytelen GPS pozíciót nem küldtem el.';
      _emit();
      return;
    }

    final previous = _lastAcceptedPosition;
    if (previous != null && !position.timestamp.isAfter(previous.timestamp)) return;
    final speed = max(
      0.0,
      RoamingResilience.finiteOrZero(position.speed),
    );
    final accuracy = RoamingResilience.finiteOrZero(position.accuracy);
    final assessment = GpsPointQuality.assess(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: accuracy,
      speedMps: speed,
      capturedAt: position.timestamp,
      previousLatitude: previous?.latitude,
      previousLongitude: previous?.longitude,
      previousAccuracy: previous?.accuracy,
      previousSpeedMps: previous == null
          ? null
          : max(
              0.0,
              RoamingResilience.finiteOrZero(previous.speed),
            ),
      previousCapturedAt: previous?.timestamp,
    );

    if (!assessment.accepted) {
      _gpsQuality = assessment.quality.name;
      _gpsScore = assessment.score;
      _rejectedFixes++;
      _lastError = assessment.reason == 'impossible_jump'
          ? 'Hibás GPS-ugrást kiszűrtem.'
          : 'GPS pontosság gyenge, várok jobb jelre.';
      _emit();
      return;
    }

    final stable = GpsPointQuality.stabilize(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: accuracy,
      speedMps: speed,
      stationaryJitter: assessment.stationaryJitter,
      previousLatitude: _stableLatitude,
      previousLongitude: _stableLongitude,
    );

    _gpsQuality = assessment.quality.name;
    _gpsScore = assessment.score;
    _lastFixAt = position.timestamp;
    _rejectedFixes = 0;
    _stableLatitude = stable.latitude;
    _stableLongitude = stable.longitude;

    _lastAcceptedPosition = position;
    _lastPosition = position;
    final anchor = _motionAnchor;
    final distance = anchor == null ? 0.0 : GpsPointQuality.distanceMeters(
      anchor.latitude, anchor.longitude, position.latitude, position.longitude);
    final changed = _policy.observe(at: position.timestamp, speedMps: speed,
      distanceM: distance, accuracyM: accuracy);
    if (anchor == null || speed >= 1.5 || distance > 35) _motionAnchor = position;
    _emit();
    if (!_policy.shouldSave(position.timestamp)) {
      if (changed) unawaited(_lifecycle.run(_applyProfile).catchError((Object _) {}));
      return;
    }

    // Freeze identity and coordinates before asynchronous country lookup.
    final latitude = stable.latitude;
    final longitude = stable.longitude;
    final countryCode = await CountryCodeService.instance.resolve(position);
    final current = await FlowSessionStore.instance.load();
    if (!_enabled || generation != _locationGeneration || current == null ||
        current.sessionToken != session.sessionToken ||
        current.flowId != session.flowId ||
        flowJournalPlate(current.plate) != originalPlate ||
        !await _hasActiveWorkday(session: current, capturedAt: position.timestamp)) return;

    final point = <String, dynamic>{
      'pointId': RoamingResilience.pointId(
        deviceId: originalDevice,
        timestamp: position.timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        scope: jsonEncode([session.flowId, originalPlate, source, latitude, longitude, countryCode]),
      ),
      'flowId': session.flowId,
      'plate': originalPlate,
      'deviceId': originalDevice,
      'vehicleLabel': originalPlate,
      'countryCode': countryCode,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'rawLatitude': position.latitude,
      'rawLongitude': position.longitude,
      'gpsQuality': assessment.quality.name,
      'gpsScore': assessment.score,
      'accuracy': accuracy,
      'speedMps': speed,
      'heading': RoamingResilience.finiteOrZero(position.heading),
      'altitude': RoamingResilience.finiteOrZero(position.altitude),
      'source': source,
    };

    await _queue.append(jsonEncode(point));
    _policy.saved(position.timestamp);
    _queueDepth = await _queue.count();
    _emit();
    unawaited(_requestFlush());
    if (changed) unawaited(_lifecycle.run(_applyProfile).catchError((Object _) {}));
  }

  Future<void> _requestFlush({bool force = false}) async {
    if (force) _retryGate.retryNow();
    if (!_retryGate.ready(DateTime.now())) return;
    if (_flushRunning) {
      _flushAgain = true;
      return;
    }
    _flushRunning = true;
    try {
      do {
        _flushAgain = false;
        await _flushQueuePass();
      } while (_flushAgain && _retryGate.ready(DateTime.now()));
    } catch (_) {
      _scheduleRetry('A GPS-adatok helyi mentése nem sikerült. A korábbi sor megmaradt.');
    } finally {
      _flushRunning = false;
    }
  }

  void _scheduleRetry(String message, {Duration? minimumDelay}) {
    _lastError = message;
    _retryTimer?.cancel();
    final delay = _retryGate.fail(DateTime.now(), minimum: minimumDelay ?? Duration.zero);
    _retryTimer = Timer(delay, () => unawaited(_requestFlush()));
    _emit();
  }

  Future<void> _flushQueuePass() async {
    if (_endpoint.trim().isEmpty) {
      _lastError = 'A nyomkövető szerver címe nincs beállítva.';
      _emit();
      return;
    }

    final result = await TrackingQueueSync(
      queue: _queue,
      loadSession: FlowSessionStore.instance.load,
      send: (session, payload) {
        final request = http.Request('POST', Uri.parse(_endpoint));
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.sessionToken}',
        });
        request.body = jsonEncode(payload);
        return sendFlowMultipart(request, timeout: const Duration(seconds: 10));
      },
    ).run();
    _queueDepth = await _queue.count();
    _queueDepthLoaded = true;
    if (result.sent > 0) _lastSentAt = DateTime.now();
    if (result.retryAfter != null) {
      _flushAgain = false;
      _scheduleRetry(result.error!, minimumDelay: result.retryAfter);
      return;
    }
    _retryGate.succeeded();
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastError = result.error;
    if (result.more) _flushAgain = true;
    _emit();
  }

  VehicleTrackingStatus get _status => VehicleTrackingStatus(
        enabled: _enabled,
        running: _subscription != null,
        deviceId: _deviceId,
        vehicleLabel: _vehicleLabel,
        lastPosition: _lastPosition,
        lastSentAt: _lastSentAt,
        lastError: _lastError,
        gpsQuality: _gpsQuality,
        gpsScore: _gpsScore,
        queueDepth: _queueDepth,
        lastFixAt: _lastFixAt,
        rejectedFixes: _rejectedFixes,
        stableLatitude: _stableLatitude,
        stableLongitude: _stableLongitude,
        stationary: _policy.stationary,
        sampleSeconds: _activeInterval.inSeconds,
        nextRetryAt: _retryGate.retryAt,
      );

  void _emit() {
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }
}

