import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'country_code_service.dart';
import 'flow_account_service.dart';
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
/// the Android application.
class VehicleTrackingService {
  VehicleTrackingService._();

  static final VehicleTrackingService instance = VehicleTrackingService._();

  static const _enabledKey = 'aims_tracking_enabled';
  static const _deviceIdKey = 'aims_tracking_device_id';
  static const _vehicleLabelKey = 'aims_tracking_vehicle_label';
  static const _maxQueueLines = 20000;
  static const _uploadBatchSize = 40;

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

  Future<void> _queueIoTail = Future<void>.value();
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

  Stream<VehicleTrackingStatus> get statusStream => _statusController.stream;

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

  Future<void> recover() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    if (!_enabled) return;
    if (_subscription == null) {
      await _startLocationStream(requestPermission: false);
    }
    unawaited(_requestFlush());
  }

  Future<void> startIfEnabled() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();
    if (_enabled) {
      await _startLocationStream(requestPermission: false);
    }
  }

  Future<bool> enableWithPermission() async {
    await _loadIdentity();
    await _ensureQueueDepthLoaded();

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
    _healthTimer?.cancel();
    _healthTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _streamStartedAt = null;
    _streamFailures = 0;
    _emit();
  }

  Future<void> setVehicleLabel(String label) async {
    final cleaned = label
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final prefs = await SharedPreferences.getInstance();
    _vehicleLabel = cleaned;
    await prefs.setString(_vehicleLabelKey, cleaned);
    _emit();
  }

  Future<Map<String, String>> _sessionHeaders() async {
    final session = await FlowSessionStore.instance.load();
    if (session == null || session.isExpired) {
      throw const _TrackingSessionException();
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.sessionToken}',
    };
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
      final random = Random.secure();
      final suffix = List.generate(
        16,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
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

    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _enqueuePosition,
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
    if (!_enabled) return;
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

  void _enqueuePosition(Position position) {
    _positionTail = _positionTail.then(
      (_) => _queueAndFlush(position, source: 'stream'),
    ).catchError((Object error) {
      _lastError = 'GPS feldolgozási hiba: $error';
      _emit();
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!_enabled) return;
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
    if (position != null) {
      await _queueAndFlush(position, source: 'heartbeat');
    }
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

  Future<void> _ensureQueueDepthLoaded() async {
    if (_queueDepthLoaded) return;
    await _withQueueLock(() async {
      final file = await _queueFile();
      _queueDepth = (await file.readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .length;
      _queueDepthLoaded = true;
    });
  }

  Future<List<String>> _queueSnapshot({
    int maxLines = _uploadBatchSize,
  }) {
    return _withQueueLock(() async {
      final file = await _queueFile();
      final lines = (await file.readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .toList();
      _queueDepth = lines.length;
      _queueDepthLoaded = true;
      return lines.take(maxLines).toList();
    });
  }

  Future<void> _appendQueueLine(String line) {
    return _withQueueLock(() async {
      final file = await _queueFile();
      var lines = (await file.readAsLines())
          .where((item) => item.trim().isNotEmpty)
          .toList();
      lines.add(line);
      if (lines.length > _maxQueueLines) {
        final removed = lines.length - _maxQueueLines;
        final discarded = lines.take(removed).toList();
        lines = lines.sublist(removed);
        final quarantine = await _quarantineFile();
        final now = DateTime.now().toUtc().toIso8601String();
        for (final item in discarded) {
          await quarantine.writeAsString(
            '${jsonEncode({
              'quarantinedAt': now,
              'reason': 'queue_capacity',
              'raw': item,
            })}\n',
            mode: FileMode.append,
            flush: false,
          );
        }
      }
      await file.writeAsString(
        lines.isEmpty ? '' : '${lines.join('\n')}\n',
        flush: true,
      );
      _queueDepth = lines.length;
      _queueDepthLoaded = true;
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
      for (var index = 0; index < consumed.length; index++) {
        if (current[index] != consumed[index]) return false;
      }
      final remaining = current.sublist(consumed.length);
      await file.writeAsString(
        remaining.isEmpty ? '' : '${remaining.join('\n')}\n',
        flush: true,
      );
      _queueDepth = remaining.length;
      _queueDepthLoaded = true;
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

  Future<void> _queueAndFlush(
    Position position, {
    required String source,
  }) async {
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

    final countryCode = await CountryCodeService.instance.resolve(position);
    final normalizedPlate = _vehicleLabel
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final point = <String, dynamic>{
      'pointId': RoamingResilience.pointId(
        deviceId: _deviceId,
        timestamp: position.timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      'plate': normalizedPlate,
      'deviceId': _deviceId,
      'vehicleLabel': normalizedPlate,
      'countryCode': countryCode,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
      'latitude': _stableLatitude ?? position.latitude,
      'longitude': _stableLongitude ?? position.longitude,
      'rawLatitude': position.latitude,
      'rawLongitude': position.longitude,
      'gpsQuality': _gpsQuality,
      'gpsScore': _gpsScore,
      'accuracy': accuracy,
      'speedMps': speed,
      'heading': RoamingResilience.finiteOrZero(position.heading),
      'altitude': RoamingResilience.finiteOrZero(position.altitude),
      'source': source,
    };

    await _appendQueueLine(jsonEncode(point));
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

    final lines = await _queueSnapshot();
    if (lines.isEmpty) {
      _flushFailures = 0;
      _queueDepth = 0;
      _emit();
      return;
    }

    Map<String, String> headers;
    try {
      headers = await _sessionHeaders();
    } on _TrackingSessionException {
      _scheduleRetry(
        'A FLOW munkamenet lejárt. A GPS-pontok helyben maradnak; jelentkezz be újra.',
        minimumDelay: const Duration(minutes: 5),
      );
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
      payload['plate'] = _vehicleLabel;
      payload['vehicleLabel'] = _vehicleLabel;

      try {
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          Map<String, dynamic>? body;
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              body = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}

          if (body == null || body['ok'] != true) {
            networkFailed = true;
            _scheduleRetry(
              'A nyomkövető szerver hibás választ adott. A GPS-pont helyben marad.',
            );
            break;
          }
          if (body['registeredVehicle'] != true) {
            networkFailed = true;
            _scheduleRetry(
              'A szerver nem kapcsolta a GPS-pontot a bejelentkezett járműhöz. A pont helyben marad.',
            );
            break;
          }

          consumed.add(line);
          _lastSentAt = DateTime.now();
          _lastError = null;
          continue;
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          networkFailed = true;
          _scheduleRetry(
            'A FLOW hozzáférés ellenőrzése szükséges. A GPS-pontok helyben maradnak.',
            minimumDelay: const Duration(minutes: 5),
          );
          break;
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
      if (!removed) _flushAgain = true;
    }

    if (!networkFailed) {
      _flushFailures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      if (lines.length >= _uploadBatchSize) _flushAgain = true;
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

class _TrackingSessionException implements Exception {
  const _TrackingSessionException();
}
