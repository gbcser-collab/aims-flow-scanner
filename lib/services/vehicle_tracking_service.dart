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
import 'flow_local_journal.dart';
import 'flow_multipart_transport.dart';
import 'tracking_point_queue.dart';
import 'tracking_queue_sync.dart';
import 'tracking_shutdown.dart';
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
  Timer? _heartbeatTimer;
  Timer? _healthTimer;
  Timer? _retryTimer;
  Timer? _streamRecoveryTimer;

  final _queue = TrackingPointQueue(directory: getApplicationDocumentsDirectory);
  Future<void> _positionTail = Future<void>.value();

  bool _flushRunning = false;
  bool _flushAgain = false;
  bool _queueDepthLoaded = false;
  int _flushFailures = 0;
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
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_workdayKey);
    raw ??= prefs.getString(_legacyWorkdayKey);
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      session ??= await FlowSessionStore.instance.load();
      if (session == null || session.isExpired) return false;
      final key = '${session.flowId}:${flowJournalPlate(session.plate)}';
      final states = decoded['states'];
      final state = decoded['journalVersion'] == 3 && states is Map
          ? states[key] : decoded;
      if (state is! Map || state['active'] != true) return false;
      final owner = state['flowId']?.toString() ??
          RegExp(r'^(\d{6})-').firstMatch(state['workdayId']?.toString() ?? '')?.group(1);
      final plate = state['plate']?.toString() ?? '';
      final started = DateTime.tryParse(state['startedAt']?.toString() ?? '');
      if (capturedAt != null && (started == null || capturedAt.isBefore(started))) return false;
      return owner == session.flowId &&
          flowJournalPlate(plate).isNotEmpty &&
          flowJournalPlate(plate) == flowJournalPlate(session.plate);
    } catch (_) {
      return false;
    }
  }

  Future<VehicleTrackingStatus> currentStatus() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    return _status;
  }

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
  Future<bool> beginWorkday(String plate) async {
    await setVehicleLabel(plate);
    if (_runningUnderFlutterTest) return true;
    return enableWithPermission();
  }

  /// Stop foreground GPS first; a stalled upload never delays local closure.
  Future<void> endWorkday() async {
    if (_runningUnderFlutterTest) return;
    _lastError = null;
    await stopTrackingBeforeSync(stop: disable, sync: _requestFlush);
  }

  Future<void> syncPending() => _requestFlush();

  Future<void> recover() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    if (!await _hasActiveWorkday()) {
      if (_enabled || _subscription != null) await disable();
      unawaited(_requestFlush());
      return;
    }
    if (!_enabled) {
      unawaited(_requestFlush());
      return;
    }
    if (_subscription == null) {
      await _startLocationStream(requestPermission: false);
    }
    unawaited(_requestFlush());
  }

  Future<void> startIfEnabled() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    if (!await _hasActiveWorkday()) {
      if (_enabled || _subscription != null) await disable();
      unawaited(_requestFlush());
      return;
    }
    unawaited(_requestFlush());
    if (_enabled) {
      await _startLocationStream(requestPermission: false);
    }
  }

  Future<bool> enableWithPermission() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();

    if (!await _hasActiveWorkday()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
      _enabled = false;
      _lastError =
          'A nyomkövetés a munkanap indulásakor automatikusan bekapcsol.';
      _emit();
      return false;
    }

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
    _locationGeneration++;
    _enabled = false;
    final subscription = _subscription;
    _subscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _streamStartedAt = null;
    _streamFailures = 0;
    try {
      await subscription?.cancel();
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
      _emit();
    }
  }

  Future<void> setVehicleLabel(String label) async {
    final cleaned = label
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final prefs = await SharedPreferences.getInstance();
    if (_vehicleLabel != cleaned) {
      if (_subscription != null) await disable();
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
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _vehicleLabel = (prefs.getString(_vehicleLabelKey) ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.trim().isEmpty) {
      id = (await const DeviceIdentityService().loadOrCreate()).deviceId;
    }
    _deviceId = id;
  }

  Future<void> _startLocationStream({required bool requestPermission}) async {
    if (_subscription != null) return;
    final generation = _locationGeneration;
    if (!await _hasActiveWorkday()) {
      await disable();
      return;
    }
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

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 3,
            intervalDuration: const Duration(seconds: 8),
            foregroundNotificationConfig:
                const ForegroundNotificationConfig(
              notificationTitle: 'AIMS FLOW nyomkövetés aktív',
              notificationText:
                  'A jármű helyzete a munkavégzés alatt frissül.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 3,
          );

    if (!await _hasActiveWorkday() || !_enabled ||
        generation != _locationGeneration || _subscription != null) return;
    final streamSession = await FlowSessionStore.instance.load();
    if (streamSession == null || !_enabled || generation != _locationGeneration ||
        _subscription != null) return;
    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) => _enqueuePosition(position, streamSession, generation),
      onError: (Object error) {
        _lastError = 'GPS stream hiba: $error';
        _emit();
        _scheduleStreamRecovery();
      },
      onDone: _scheduleStreamRecovery,
      cancelOnError: false,
    );
    _streamFailures = 0;
    _streamStartedAt = DateTime.now();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_sendHeartbeat());
    });

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_enabled) return;
      final now = DateTime.now();
      final noFixTooLong = _lastFixAt == null &&
          _streamStartedAt != null &&
          now.difference(_streamStartedAt!) > const Duration(seconds: 75);
      final staleFix = _lastFixAt != null &&
          now.difference(_lastFixAt!) > const Duration(seconds: 120);
      if (_subscription == null || noFixTooLong || staleFix) {
        unawaited(_restartLocationStream());
      } else {
        unawaited(_requestFlush());
      }
    });

    unawaited(_requestFlush());
    _emit();
  }

  Future<void> _restartLocationStream() async {
    if (!_enabled || !await _hasActiveWorkday()) return;
    final current = _subscription;
    _subscription = null;
    if (current != null) {
      try {
        await current.cancel();
      } catch (_) {}
    }
    _streamStartedAt = null;
    _lastError = 'GPS kapcsolat újraindítása…';
    _emit();
    try {
      await _startLocationStream(requestPermission: false);
    } catch (error) {
      _lastError = 'GPS újraindítási hiba: $error';
      _emit();
      _scheduleStreamRecovery();
    }
  }

  void _scheduleStreamRecovery() {
    if (!_enabled) return;
    _streamFailures++;
    final current = _subscription;
    _subscription = null;
    if (current != null) unawaited(current.cancel());
    _streamRecoveryTimer?.cancel();
    final delay = RoamingResilience.retryDelay(_streamFailures);
    _streamRecoveryTimer = Timer(delay, () {
      if (_enabled && _subscription == null) unawaited(recover());
    });
  }

  void _enqueuePosition(Position position, FlowAccountSession session, int generation) {
    _positionTail = _positionTail.then(
      (_) async {
        if (generation != _locationGeneration) return;
        await _queueAndFlush(position, source: 'stream', capturedSession: session);
      },
    ).catchError((Object error) {
      _lastError = 'GPS feldolgozási hiba: $error';
      _emit();
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!_enabled || !await _hasActiveWorkday()) return;
    if (_subscription == null) {
      try {
        await _startLocationStream(requestPermission: false);
      } catch (_) {}
    }
    if (_lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) <
            const Duration(seconds: 25)) {
      return;
    }

    final capturedSession = await FlowSessionStore.instance.load();
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position != null && capturedSession != null) {
      await _queueAndFlush(position, source: 'heartbeat', capturedSession: capturedSession);
    }
  }

  Future<void> _ensureQueueDepthLoaded() async {
    if (_queueDepthLoaded) return;
    _queueDepth = (await _queue.snapshot()).length;
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

    if (source == 'stream' && assessment.stationaryJitter) {
      _lastPosition = previous ?? position;
      _lastError = null;
      _emit();
      return;
    }

    _lastAcceptedPosition = position;
    _lastPosition = position;
    _lastError = null;
    _emit();

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
    _queueDepth = (await _queue.snapshot()).length;
    _emit();
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
    } catch (_) {
      _scheduleRetry('A GPS-adatok helyi mentése nem sikerült. A korábbi sor megmaradt.');
    } finally {
      _flushRunning = false;
    }
  }

  void _scheduleRetry(String message, {Duration? minimumDelay}) {
    _flushFailures++;
    _lastError = message;
    _retryTimer?.cancel();
    final calculated = RoamingResilience.retryDelay(_flushFailures);
    final delay = minimumDelay != null && calculated < minimumDelay
        ? minimumDelay
        : calculated;
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
    _queueDepth = (await _queue.snapshot()).length;
    _queueDepthLoaded = true;
    if (result.sent > 0) _lastSentAt = DateTime.now();
    if (result.retryAfter != null) {
      _flushAgain = false;
      _scheduleRetry(result.error!, minimumDelay: result.retryAfter);
      return;
    }
    _flushFailures = 0;
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
      );

  void _emit() {
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }
}

