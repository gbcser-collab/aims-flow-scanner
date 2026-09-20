import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/aims_locale.dart';
import '../services/aims_voice_command.dart';
import '../services/aims_voice_service.dart';
import '../services/driver_api_service.dart';
import '../services/driver_push_service.dart';
import '../services/roaming_resilience.dart';
import '../services/vehicle_tracking_service.dart';
import '../widgets/aims_flow_logo.dart';
import 'invoice_scanner_screen.dart';
import 'scanner_screen.dart';

class _PendingStopAction {
  const _PendingStopAction({
    required this.action,
    required this.source,
    required this.occurredAt,
  });

  final String action;
  final String source;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
        'action': action,
        'source': source,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
      };

  static _PendingStopAction? fromJson(Object? value) {
    if (value is! Map) return null;
    final action = value['action']?.toString() ?? '';
    final source = value['source']?.toString() ?? '';
    final occurredAt = DateTime.tryParse(
      value['occurredAt']?.toString() ?? '',
    );
    if (!const {'arrived', 'completed'}.contains(action) ||
        !const {'voice', 'manual', 'touch'}.contains(source) ||
        occurredAt == null) {
      return null;
    }
    return _PendingStopAction(
      action: action,
      source: source,
      occurredAt: occurredAt.toUtc(),
    );
  }
}

class _PendingDriverSignal {
  const _PendingDriverSignal({
    required this.id,
    required this.type,
    required this.urgent,
    required this.occurredAt,
    this.message,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String type;
  final bool urgent;
  final DateTime occurredAt;
  final String? message;
  final double? latitude;
  final double? longitude;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'urgent': urgent,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'message': message,
        'latitude': latitude,
        'longitude': longitude,
      };

  static _PendingDriverSignal? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    final type = value['type']?.toString().trim() ?? '';
    final occurredAt = DateTime.tryParse(
      value['occurredAt']?.toString() ?? '',
    );
    if (id.isEmpty || type.isEmpty || occurredAt == null) return null;
    return _PendingDriverSignal(
      id: id,
      type: type,
      urgent: value['urgent'] == true,
      occurredAt: occurredAt.toUtc(),
      message: value['message']?.toString(),
      latitude: (value['latitude'] as num?)?.toDouble(),
      longitude: (value['longitude'] as num?)?.toDouble(),
    );
  }
}

enum _SignalDelivery { sent, queued, failed }

class DriverShellScreen extends StatefulWidget {
  const DriverShellScreen({super.key});

  @override
  State<DriverShellScreen> createState() => _DriverShellScreenState();
}

class _DriverShellScreenState extends State<DriverShellScreen>
    with WidgetsBindingObserver {
  static const _blue = Color(0xFF1CB8FF);
  static const _green = Color(0xFF4DE3A4);
  static const _panelColor = Color(0xFF071725);
  static const _prefsPlate = 'aims_driver_plate';
  static const _prefsDriverName = 'aims_driver_name';
  static const _prefsHandsFree = 'aims_hands_free';
  static const _prefsPendingStopPrefix = 'aims_pending_stop_actions_v1_';
  static const _prefsJobsCachePrefix = 'aims_driver_jobs_cache_v1_';
  static const _prefsJobsCacheAtPrefix = 'aims_driver_jobs_cache_at_v1_';
  static const _prefsPendingSignalPrefix = 'aims_pending_driver_signals_v1_';

  final _api = const DriverApiService();
  final _tracking = VehicleTrackingService.instance;
  final _push = DriverPushService.instance;
  final ScrollController _homeScrollController = ScrollController();
  late final AimsVoiceService _voice;

  StreamSubscription<DriverPushEvent>? _pushSub;
  StreamSubscription<AimsVoiceState>? _voiceSub;
  StreamSubscription<VehicleTrackingStatus>? _trackingSub;

  int _index = 0;
  String _plate = '';
  String _driverName = '';
  List<DriverJob> _jobs = const [];
  bool _loading = true;
  bool _actionBusy = false;
  String? _message;
  VehicleTrackingStatus? _trackingStatus;
  AimsVoiceState _voiceState = const AimsVoiceState(
    enabled: false,
    mode: AimsVoiceMode.off,
    message: 'AIMS Hands-Free kikapcsolva.',
  );
  bool _handsFreeBusy = false;
  int _refreshGeneration = 0;
  DateTime? _lastResumeRefreshAt;
  final Map<int, List<_PendingStopAction>> _pendingStopActions = {};
  bool _pendingStopFlushBusy = false;
  Timer? _pendingStopRetryTimer;
  final List<_PendingDriverSignal> _pendingSignals = [];
  bool _pendingSignalFlushBusy = false;
  Timer? _pendingSignalRetryTimer;
  int _signalNonce = 0;

  bool _isStopCompleted(DriverStop stop) =>
      stop.completed ||
      (_pendingStopActions[stop.id]?.any(
            (item) => item.action == 'completed',
          ) ??
          false);

  bool _isStopArrived(DriverStop stop) =>
      stop.arrived || (_pendingStopActions[stop.id]?.isNotEmpty ?? false);

  bool _hasOpenStop(DriverJob job) {
    for (final stop in job.stops) {
      if (!_isStopCompleted(stop)) return true;
    }
    return false;
  }

  DriverJob? get _job {
    if (_jobs.isEmpty) return null;
    for (final job in _jobs) {
      if (job.acceptedAt != null && _hasOpenStop(job)) return job;
    }
    for (final job in _jobs) {
      if (job.acceptedAt != null) return job;
    }
    for (final job in _jobs) {
      if (_hasOpenStop(job)) return job;
    }
    return _jobs.first;
  }

  DriverStop? get _stop {
    final job = _job;
    if (job == null) return null;
    for (final stop in job.stops) {
      if (!_isStopCompleted(stop)) return stop;
    }
    return null;
  }

  List<DriverJob> get _otherJobs {
    final current = _job;
    if (current == null) return _jobs;
    return _jobs.where((job) => job.id != current.id).toList();
  }

  String _displayPlate(String value) {
    final compact = value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.length == 6) return '${compact.substring(0, 3)}-${compact.substring(3)}';
    return value.trim().toUpperCase();
  }

  String _normalizedPlateKey([String? plate]) => (plate ?? _plate)
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  String _pendingStopPrefsKey([String? plate]) =>
      '$_prefsPendingStopPrefix${_normalizedPlateKey(plate)}';

  String _jobsCachePrefsKey([String? plate]) =>
      '$_prefsJobsCachePrefix${_normalizedPlateKey(plate)}';

  String _jobsCacheAtPrefsKey([String? plate]) =>
      '$_prefsJobsCacheAtPrefix${_normalizedPlateKey(plate)}';

  String _pendingSignalPrefsKey([String? plate]) =>
      '$_prefsPendingSignalPrefix${_normalizedPlateKey(plate)}';

  Future<void> _loadPendingSignals(
    SharedPreferences prefs,
    String plate,
  ) async {
    _pendingSignals.clear();
    final raw = prefs.getString(_pendingSignalPrefsKey(plate));
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        final signal = _PendingDriverSignal.fromJson(item);
        if (signal != null) _pendingSignals.add(signal);
      }
      _pendingSignals.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    } catch (_) {
      await prefs.remove(_pendingSignalPrefsKey(plate));
    }
  }

  Future<void> _savePendingSignals() async {
    if (_plate.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingSignalPrefsKey();
    if (_pendingSignals.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode([for (final signal in _pendingSignals) signal.toJson()]),
    );
  }

  String _newSignalId(DateTime occurredAt) {
    _signalNonce = (_signalNonce + 1) % 1000000;
    return 'sig_${occurredAt.microsecondsSinceEpoch}_$_signalNonce';
  }

  Future<void> _queueSignal(_PendingDriverSignal signal) async {
    if (_pendingSignals.any((item) => item.id == signal.id)) return;
    if (mounted) {
      setState(() => _pendingSignals.add(signal));
    } else {
      _pendingSignals.add(signal);
    }
    _pendingSignals.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    await _savePendingSignals();
    _schedulePendingSignalFlush();
  }

  void _schedulePendingSignalFlush({
    Duration delay = const Duration(seconds: 30),
  }) {
    if (_pendingSignals.isEmpty || _pendingSignalFlushBusy) return;
    if (_pendingSignalRetryTimer?.isActive == true) return;
    _pendingSignalRetryTimer = Timer(delay, () {
      _pendingSignalRetryTimer = null;
      unawaited(_flushPendingSignals());
    });
  }

  Future<List<DriverJob>> _loadCachedJobs(
    SharedPreferences prefs,
    String plate,
  ) async {
    if (plate.trim().isEmpty) return const [];
    final raw = prefs.getString(_jobsCachePrefsKey(plate));
    final savedAtRaw = prefs.getString(_jobsCacheAtPrefsKey(plate));
    final savedAt = DateTime.tryParse(savedAtRaw ?? '');
    if (raw == null || savedAt == null) return const [];
    if (DateTime.now().toUtc().difference(savedAt.toUtc()) >
        const Duration(days: 7)) {
      await prefs.remove(_jobsCachePrefsKey(plate));
      await prefs.remove(_jobsCacheAtPrefsKey(plate));
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => DriverJob.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      await prefs.remove(_jobsCachePrefsKey(plate));
      await prefs.remove(_jobsCacheAtPrefsKey(plate));
      return const [];
    }
  }

  Future<void> _saveJobsCache(List<DriverJob> jobs) async {
    if (_plate.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jobsCachePrefsKey(),
      jsonEncode([for (final job in jobs) job.toJson()]),
    );
    await prefs.setString(
      _jobsCacheAtPrefsKey(),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _loadPendingStopActions(
    SharedPreferences prefs,
    String plate,
  ) async {
    _pendingStopActions.clear();
    final raw = prefs.getString(_pendingStopPrefsKey(plate));
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id == null || id <= 0) continue;
        final actions = <_PendingStopAction>[];
        if (entry.value is List) {
          for (final item in entry.value as List) {
            final action = _PendingStopAction.fromJson(item);
            if (action != null) actions.add(action);
          }
        } else {
          final legacy = _PendingStopAction.fromJson(entry.value);
          if (legacy != null) actions.add(legacy);
        }
        if (actions.isNotEmpty) {
          actions.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
          _pendingStopActions[id] = actions;
        }
      }
    } catch (_) {
      await prefs.remove(_pendingStopPrefsKey(plate));
    }
  }

  Future<void> _savePendingStopActions() async {
    if (_plate.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingStopPrefsKey();
    if (_pendingStopActions.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final encoded = <String, dynamic>{
      for (final entry in _pendingStopActions.entries)
        entry.key.toString(): [
          for (final action in entry.value) action.toJson(),
        ],
    };
    await prefs.setString(key, jsonEncode(encoded));
  }

  Future<void> _queuePendingStopAction(
    DriverStop stop,
    String action,
    String source,
    DateTime occurredAt,
  ) async {
    final normalizedAction =
        action == 'completed' ? 'completed' : 'arrived';
    final current = List<_PendingStopAction>.from(
      _pendingStopActions[stop.id] ?? const <_PendingStopAction>[],
    );
    if (current.any((item) => item.action == normalizedAction)) return;
    if (normalizedAction == 'arrived' &&
        current.any((item) => item.action == 'completed')) {
      return;
    }
    current.add(
      _PendingStopAction(
        action: normalizedAction,
        source: source,
        occurredAt: occurredAt.toUtc(),
      ),
    );
    current.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (mounted) {
      setState(() => _pendingStopActions[stop.id] = current);
    } else {
      _pendingStopActions[stop.id] = current;
    }
    await _savePendingStopActions();
    _schedulePendingStopFlush();
  }

  void _schedulePendingStopFlush({
    Duration delay = const Duration(seconds: 30),
  }) {
    if (_pendingStopActions.isEmpty || _pendingStopFlushBusy) return;
    if (_pendingStopRetryTimer?.isActive == true) return;
    _pendingStopRetryTimer = Timer(delay, () {
      _pendingStopRetryTimer = null;
      unawaited(_flushPendingStopActions());
    });
  }

  bool _isTerminalPendingStopError(Object error) {
    if (error is DriverApiException) {
      if (const {400, 404, 409, 422}.contains(error.statusCode)) {
        return true;
      }
      if (error.retryable ||
          error.statusCode == 401 ||
          error.statusCode == 403) {
        return false;
      }
    }
    final value = error.toString().toLowerCase();
    return value.contains('stop_not_found') ||
        value.contains('job_not_active') ||
        value.contains('invalid_payload');
  }

  Future<void> _flushPendingStopActions({bool refreshAfter = true}) async {
    if (_pendingStopFlushBusy ||
        _pendingStopActions.isEmpty ||
        _plate.isEmpty) {
      return;
    }

    _pendingStopFlushBusy = true;
    _pendingStopRetryTimer?.cancel();
    _pendingStopRetryTimer = null;

    final queue = <({int stopId, _PendingStopAction action})>[];
    for (final entry in _pendingStopActions.entries) {
      for (final action in entry.value) {
        queue.add((stopId: entry.key, action: action));
      }
    }
    queue.sort(
      (a, b) => a.action.occurredAt.compareTo(b.action.occurredAt),
    );

    final delivered = <({int stopId, String action})>[];
    var retryNeeded = false;

    try {
      for (final item in queue) {
        try {
          await _api.updateStop(
            plate: _plate,
            stopId: item.stopId,
            action: item.action.action,
            source: item.action.source,
            occurredAt: item.action.occurredAt,
          );
          delivered.add(
            (stopId: item.stopId, action: item.action.action),
          );
        } on DriverApiException catch (error) {
          if (_isTerminalPendingStopError(error)) {
            delivered.add(
              (stopId: item.stopId, action: item.action.action),
            );
            continue;
          }
          retryNeeded = true;
          break;
        } on StateError {
          retryNeeded = true;
          break;
        } catch (_) {
          retryNeeded = true;
          break;
        }
      }

      if (delivered.isNotEmpty) {
        if (mounted) {
          setState(() {
            for (final item in delivered) {
              final actions = _pendingStopActions[item.stopId];
              if (actions == null) continue;
              actions.removeWhere(
                (action) => action.action == item.action,
              );
              if (actions.isEmpty) {
                _pendingStopActions.remove(item.stopId);
              }
            }
          });
        } else {
          for (final item in delivered) {
            final actions = _pendingStopActions[item.stopId];
            if (actions == null) continue;
            actions.removeWhere(
              (action) => action.action == item.action,
            );
            if (actions.isEmpty) {
              _pendingStopActions.remove(item.stopId);
            }
          }
        }
        await _savePendingStopActions();
        if (refreshAfter) {
          await _refreshJobs(showLoading: false);
        }
      }
    } finally {
      _pendingStopFlushBusy = false;
      if (_pendingStopActions.isNotEmpty) {
        _schedulePendingStopFlush(
          delay: Duration(seconds: retryNeeded ? 60 : 20),
        );
      }
    }
  }

  Future<void> _flushPendingSignals() async {
    if (_pendingSignalFlushBusy ||
        _pendingSignals.isEmpty ||
        _plate.isEmpty) {
      return;
    }

    _pendingSignalFlushBusy = true;
    _pendingSignalRetryTimer?.cancel();
    _pendingSignalRetryTimer = null;
    var retryNeeded = false;
    final deliveredIds = <String>[];

    try {
      for (final signal in List<_PendingDriverSignal>.from(_pendingSignals)) {
        try {
          await _api.sendSignal(
            plate: _plate,
            type: signal.type,
            urgent: signal.urgent,
            message: signal.message,
            latitude: signal.latitude,
            longitude: signal.longitude,
            eventId: signal.id,
            occurredAt: signal.occurredAt,
          );
          deliveredIds.add(signal.id);
        } on DriverApiException catch (error) {
          if (const {400, 422}.contains(error.statusCode)) {
            deliveredIds.add(signal.id);
            continue;
          }
          retryNeeded = true;
          break;
        } on StateError {
          retryNeeded = true;
          break;
        } catch (_) {
          retryNeeded = true;
          break;
        }
      }

      if (deliveredIds.isNotEmpty) {
        if (mounted) {
          setState(() {
            _pendingSignals.removeWhere(
              (signal) => deliveredIds.contains(signal.id),
            );
          });
        } else {
          _pendingSignals.removeWhere(
            (signal) => deliveredIds.contains(signal.id),
          );
        }
        await _savePendingSignals();
      }
    } finally {
      _pendingSignalFlushBusy = false;
      if (_pendingSignals.isNotEmpty) {
        _schedulePendingSignalFlush(
          delay: Duration(seconds: retryNeeded ? 60 : 20),
        );
      }
    }
  }

  int get _pendingStopEventCount {
    var count = 0;
    for (final actions in _pendingStopActions.values) {
      count += actions.length;
    }
    return count;
  }

  String? _pendingStopNotice() {
    final count = _pendingStopEventCount;
    if (count == 0) return null;
    return _l(
      '$count stop-esemény offline elmentve. Automatikus szinkron folyamatban.',
      '$count stop event(s) saved offline. Automatic sync is in progress.',
      '$count Stopp-Ereignis(se) offline gespeichert. Automatische Synchronisierung läuft.',
    );
  }

  String? _pendingSignalNotice() {
    final count = _pendingSignals.length;
    if (count == 0) return null;
    return _l(
      '$count jelzés offline elmentve. Automatikus küldés folyamatban.',
      '$count signal(s) saved offline. Automatic delivery is in progress.',
      '$count Meldung(en) offline gespeichert. Automatische Übertragung läuft.',
    );
  }

  bool get _trackingQueuedOffline {
    final error = (_trackingStatus?.lastError ?? '').toLowerCase();
    return error.contains('nincs kapcsolat') ||
        error.contains('helyben sorban áll') ||
        error.contains('biztonságosan helyben');
  }

  String? _driverTrackingNotice() {
    final error = (_trackingStatus?.lastError ?? '').trim();
    if (error.isEmpty) return null;
    if (_trackingQueuedOffline) {
      return _l(
        'Nincs mobilnet. A GPS-pontok biztonságosan a telefonon sorban állnak, és kapcsolatkor automatikusan elküldjük őket.',
        'No mobile data. GPS points are safely queued on the phone and will upload automatically when the connection returns.',
        'Keine mobile Datenverbindung. GPS-Punkte werden sicher auf dem Telefon gespeichert und bei Verbindung automatisch gesendet.',
      );
    }
    if (error.toLowerCase().contains('szerverkulcs')) {
      return _l(
        'A GPS-kapcsolat beállítási hibát jelez. A nyomkövetés fut, de szólj az adminnak.',
        'GPS reports a configuration issue. Tracking is running, but contact the administrator.',
        'GPS meldet ein Konfigurationsproblem. Tracking läuft, bitte die Administration informieren.',
      );
    }
    return error;
  }

  String _l(String hu, String en, String de) => switch (
        AimsLocaleController.instance.languageCode
      ) {
        'en' => en,
        'de' => de,
        _ => hu,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = AimsVoiceService(
      onCommand: _handleVoiceCommand,
      driverNameProvider: () => _driverName,
    );
    _voiceSub = _voice.states.listen((state) {
      if (mounted) setState(() => _voiceState = state);
    });
    _pushSub = _push.events.listen(_handlePush);
    _trackingSub = _tracking.statusStream.listen((status) {
      if (mounted) setState(() => _trackingStatus = status);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('aims_user_role') ?? 'driver').trim();
    var plate = (prefs.getString(_prefsPlate) ?? '').trim().toUpperCase();
    final driverName = (prefs.getString(_prefsDriverName) ?? '').trim();

    final status = await _tracking.currentStatus();

    // Admin phones must never inherit a stale driver plate or start driver GPS.
    if (role == 'admin') {
      if (!mounted) return;
      setState(() {
        _plate = '';
        _driverName = 'AIMS Admin';
        _trackingStatus = status;
        _loading = false;
        _message = _l(
          'Admin push aktív. A jármű- és sofőrértesítések erre a telefonra érkeznek.',
          'Admin push is active. Vehicle and driver alerts are delivered to this phone.',
          'Admin-Push ist aktiv. Fahrzeug- und Fahrerwarnungen kommen auf dieses Telefon.',
        );
      });
      return;
    }

    if (plate.isEmpty && status.vehicleLabel.trim().isNotEmpty) {
      plate = status.vehicleLabel.trim().toUpperCase();
    }

    final cachedJobs = await _loadCachedJobs(prefs, plate);
    await _loadPendingStopActions(prefs, plate);
    await _loadPendingSignals(prefs, plate);

    if (!mounted) return;
    setState(() {
      _plate = plate;
      _driverName = driverName;
      _trackingStatus = status;
      _jobs = cachedJobs;
      _loading = cachedJobs.isEmpty;
    });

    if (_plate.isEmpty) {
      setState(() {
        _loading = false;
        _message = _l('Nincs bejelentkezett rendszám. Lépj be újra.', 'No signed-in plate. Sign in again.', 'Kein angemeldetes Kennzeichen. Bitte erneut anmelden.');
      });
    } else {
      await _tracking.setVehicleLabel(_plate);
      await _activateDriverServices();
    }

    // Driver-first default: voice control is ON unless the driver explicitly
    // switched it off earlier. No need to hunt for the microphone every trip.
    final savedHandsFree = prefs.getBool(_prefsHandsFree);
    final handsFree = savedHandsFree ?? true;
    if (savedHandsFree == null) {
      await prefs.setBool(_prefsHandsFree, true);
    }
    if (handsFree && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_setHandsFree(true));
      });
    }

    final pending = _push.takePendingLaunch();
    if (pending != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePush(pending));
    }
  }

  Future<void> _activateDriverServices() async {
    if (_plate.isEmpty) return;

    String? pushError;
    String? trackingError;

    // Push registration must not depend on location/background permissions.
    try {
      await _push.registerForPlate(_plate);
    } catch (e) {
      pushError = e.toString().replaceFirst('Bad state: ', '');
    }

    try {
      await _tracking.setVehicleLabel(_plate);
      final status = await _tracking.currentStatus();
      if (!status.enabled) {
        await _tracking.enableWithPermission();
      } else {
        await _tracking.startIfEnabled();
      }
    } catch (e) {
      trackingError = e.toString().replaceFirst('Bad state: ', '');
    }

    if (_pendingStopActions.isNotEmpty) {
      await _flushPendingStopActions(refreshAfter: false);
    }
    if (_pendingSignals.isNotEmpty) {
      await _flushPendingSignals();
    }
    await _refreshJobs();

    if (!mounted) return;
    final issues = <String>[
      if (pushError != null) 'Push: $pushError',
      if (trackingError != null) 'GPS: $trackingError',
    ];
    if (issues.isNotEmpty) {
      setState(() => _message = issues.join(' • '));
    }
  }

  Future<void> _refreshJobs({bool showLoading = true}) async {
    if (_plate.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final generation = ++_refreshGeneration;
    if (mounted && showLoading) setState(() => _loading = true);
    try {
      final jobs = await _api.fetchJobs(_plate);
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _message = null;
      });
      unawaited(_saveJobsCache(jobs));
    } catch (e) {
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _loading = false;
        _message = _jobs.isNotEmpty
            ? _l(
                'Nincs stabil kapcsolat. A legutóbbi mentett fuvaradatot mutatom.',
                'No stable connection. Showing the latest saved job data.',
                'Keine stabile Verbindung. Die zuletzt gespeicherten Auftragsdaten werden angezeigt.',
              )
            : _l(
                'Fuvaradatok nem frissültek: $e',
                'Job data could not be refreshed: $e',
                'Auftragsdaten konnten nicht aktualisiert werden: $e',
              );
      });
    }
  }

  Future<void> _handlePush(DriverPushEvent event) async {
    if (!mounted) return;
    if (event.data['type']?.toString() != 'driver_job') return;
    await _refreshJobs();
    if (!mounted) return;

    final jobId = event.jobId;
    if (event.actionId == 'seen_job' && jobId > 0) {
      await _ack(jobId, 'seen', closeDialog: false);
      return;
    }
    if (event.actionId == 'navigate_pickup' && jobId > 0) {
      await _acceptAndNavigate(jobId);
      return;
    }
    _showJobDialog(jobId: jobId);
  }

  DriverJob? _jobById(int jobId) {
    for (final item in _jobs) {
      if (item.id == jobId) return item;
    }
    return null;
  }

  Future<void> _acceptAndNavigate(int jobId) async {
    if (_actionBusy || _plate.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      var job = _jobById(jobId);
      if (job == null) {
        await _refreshJobs(showLoading: false);
        job = _jobById(jobId);
      }
      if (job == null) {
        throw StateError(_l(
          'A kiválasztott fuvar már nem aktív.',
          'The selected job is no longer active.',
          'Der ausgewählte Auftrag ist nicht mehr aktiv.',
        ));
      }
      if (job.acceptedAt == null) {
        await _api.acknowledge(plate: _plate, jobId: jobId, action: 'accepted');
        await _push.cancelJobNotification(jobId);
        await _refreshJobs(showLoading: false);
        job = _jobById(jobId) ?? job;
      }
      if (!mounted) return;
      setState(() => _index = 0);
      final pickup = job.stops.isEmpty ? null : job.stops.first;
      if (pickup == null) {
        throw StateError(_l(
          'A fuvarhoz nincs felrakócím.',
          'The job has no pickup address.',
          'Der Auftrag hat keine Beladeadresse.',
        ));
      }
      await _openMapsForStop(pickup);
    } catch (e) {
      if (mounted) {
        _snack(_l(
          'A navigáció nem indult el: $e',
          'Navigation could not start: $e',
          'Navigation konnte nicht gestartet werden: $e',
        ));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _showJobDialog({int? jobId}) async {
    DriverJob? job;
    if (jobId != null && jobId > 0) {
      for (final item in _jobs) {
        if (item.id == jobId) {
          job = item;
          break;
        }
      }
    }
    job ??= _job;
    if (job == null || !mounted) return;

    final first = job.stops.isEmpty ? null : job.stops.first;
    final last = job.stops.isEmpty ? null : job.stops.last;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: Text(
          _l('ÚJ FUVAR ÉRKEZETT', 'NEW JOB RECEIVED', 'NEUER AUFTRAG'),
          style: const TextStyle(color: _blue, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first?.company.isNotEmpty == true ? first!.company : job!.reference,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '${first?.address ?? '—'}\n→\n${last?.address ?? '—'}',
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              _l('${job!.stops.length} megálló · ${job.reference}', '${job.stops.length} stops · ${job.reference}', '${job.stops.length} Stopps · ${job.reference}'),
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
        actions: [
          if (job.orderData.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Future.microtask(() => _showOrderDetails(job));
              },
              icon: const Icon(Icons.description_outlined),
              label: Text(_l('FUVARMEGBÍZÁS', 'TRANSPORT ORDER', 'TRANSPORTAUFTRAG')),
            ),
          if (first != null)
            FilledButton.icon(
              onPressed: _actionBusy
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      unawaited(_acceptAndNavigate(job!.id));
                    },
              icon: const Icon(Icons.navigation_rounded),
              label: Text(_l('NAVIGÁCIÓ A FELRAKÓRA', 'NAVIGATE TO PICKUP', 'NAVIGATION ZUR BELADUNG')),
            ),
          TextButton(
            onPressed: _actionBusy
                ? null
                : () => _ack(job!.id, 'seen', closeDialog: true),
            child: Text(_l('LÁTTAM', 'SEEN', 'GESEHEN')),
          ),
          FilledButton(
            onPressed: _actionBusy
                ? null
                : () => _ack(job!.id, 'accepted', closeDialog: true),
            child: Text(_l('ELFOGADOM', 'ACCEPT', 'ANNEHMEN')),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderDetails(DriverJob job) async {
    if (!mounted) return;
    final data = job.orderData;
    String value(String key) => data[key]?.toString().trim() ?? '';
    final rows = <MapEntry<String, String>>[
      MapEntry(_l('Ügyfél / referencia', 'Customer / reference', 'Kunde / Referenz'), value('customer_reference')),
      MapEntry(_l('Felrakás időpontja', 'Pickup time', 'Beladezeit'), value('pickup_time')),
      MapEntry(_l('Felrakó kapcsolattartó', 'Pickup contact', 'Kontakt Beladung'), value('pickup_contact')),
      MapEntry(_l('Felrakó telefon', 'Pickup phone', 'Telefon Beladung'), value('pickup_phone')),
      MapEntry(_l('Rakodási referencia', 'Pickup reference', 'Ladereferenz'), value('pickup_reference')),
      MapEntry(_l('Felrakási utasítás', 'Pickup instructions', 'Beladehinweise'), value('pickup_instructions')),
      MapEntry(_l('Lerakás időpontja', 'Delivery time', 'Entladezeit'), value('delivery_time')),
      MapEntry(_l('Lerakó kapcsolattartó', 'Delivery contact', 'Kontakt Entladung'), value('delivery_contact')),
      MapEntry(_l('Lerakó telefon', 'Delivery phone', 'Telefon Entladung'), value('delivery_phone')),
      MapEntry(_l('Lerakási referencia', 'Delivery reference', 'Entladereferenz'), value('delivery_reference')),
      MapEntry(_l('Lerakási utasítás', 'Delivery instructions', 'Entladehinweise'), value('delivery_instructions')),
      MapEntry(_l('Áru', 'Cargo', 'Ladung'), value('cargo')),
      MapEntry(_l('Csomag / raklap', 'Packages / pallets', 'Pakete / Paletten'), value('package_count')),
      MapEntry(_l('Súly (kg)', 'Weight (kg)', 'Gewicht (kg)'), value('weight_kg')),
      MapEntry(_l('Méretek', 'Dimensions', 'Abmessungen'), value('dimensions')),
      MapEntry(_l('Rakomány típusa', 'Load type', 'Ladungsart'), value('load_type')),
      MapEntry(_l('Járműigény', 'Vehicle requirement', 'Fahrzeuganforderung'), value('vehicle_requirement')),
      MapEntry(_l('Speciális feltétel', 'Special requirement', 'Sonderanforderung'), value('special_requirements')),
      MapEntry(_l('Sofőr', 'Driver', 'Fahrer'), value('driver_name')),
      MapEntry(_l('Sofőr telefon', 'Driver phone', 'Fahrertelefon'), value('driver_phone')),
      MapEntry(_l('CMR utasítás', 'CMR instructions', 'CMR-Anweisung'), value('cmr_instructions')),
      MapEntry(_l('POD utasítás', 'POD instructions', 'POD-Anweisung'), value('pod_instructions')),
      MapEntry(_l('Számlázás / dokumentum', 'Billing / documents', 'Abrechnung / Dokumente'), value('billing_instructions')),
      MapEntry(_l('Vám / határ dokumentum', 'Customs / border documents', 'Zoll / Grenzdokumente'), value('customs_documents')),
    ].where((item) => item.value.isNotEmpty).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071522),
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .84,
          minChildSize: .55,
          maxChildSize: .96,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
            children: [
              Text(
                _l('FUVARMEGBÍZÁS', 'TRANSPORT ORDER', 'TRANSPORTAUFTRAG'),
                style: const TextStyle(color: _blue, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              SelectableText(job.reference, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              for (final row in rows) ...[
                Text(row.key, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                SelectableText(row.value, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35, fontWeight: FontWeight.w600)),
                const SizedBox(height: 13),
              ],
              FilledButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_acceptAndNavigate(job.id));
                      },
                icon: const Icon(Icons.navigation_rounded),
                label: Text(_l('NAVIGÁCIÓ A FELRAKÓRA', 'NAVIGATE TO PICKUP', 'NAVIGATION ZUR BELADUNG')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(62),
                  backgroundColor: _blue,
                  foregroundColor: const Color(0xFF00131F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ack(
    int jobId,
    String action, {
    required bool closeDialog,
  }) async {
    if (_actionBusy || _plate.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      await _api.acknowledge(plate: _plate, jobId: jobId, action: action);
      if (action == 'accepted') {
        await _push.cancelJobNotification(jobId);
      }
      if (closeDialog && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await _refreshJobs();
      if (mounted && action == 'accepted') {
        setState(() => _index = 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_homeScrollController.hasClients) {
            _homeScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
      if (mounted) {
        _snack(action == 'accepted'
            ? _l('Fuvar elfogadva.', 'Job accepted.', 'Auftrag angenommen.')
            : _l('Visszaigazolva: LÁTTAM.', 'Acknowledged: SEEN.', 'Bestätigt: GESEHEN.'));
      }
    } catch (e) {
      if (mounted) _snack(_l('Visszaigazolási hiba: $e', 'Acknowledgement error: $e', 'Bestätigungsfehler: $e'));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openMaps() async {
    final stop = _stop;
    if (stop == null) {
      _snack(_l('Nincs megnyitható következő cím.', 'There is no next address to open.', 'Es gibt keine nächste Adresse zum Öffnen.'));
      return;
    }
    await _openMapsForStop(stop);
  }

  Future<void> _openMapsForStop(DriverStop stop) async {
    final address = stop.address.trim();
    final hasCoordinates = RoamingResilience.validCoordinates(
      stop.latitude,
      stop.longitude,
    );
    if (address.isEmpty && !hasCoordinates) {
      _snack(_l('Nincs megnyitható cím.', 'There is no address to open.', 'Es gibt keine Adresse zum Öffnen.'));
      return;
    }

    final destination = hasCoordinates
        ? '${stop.latitude},${stop.longitude}'
        : address;
    final nativeUri = hasCoordinates
        ? Uri.parse('geo:$destination?q=$destination')
        : Uri(
            scheme: 'geo',
            path: '0,0',
            queryParameters: {'q': address},
          );

    try {
      if (await launchUrl(nativeUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}

    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(destination)}&travelmode=driving',
    );
    try {
      if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}

    _snack(_l(
      'A navigációs alkalmazás nem nyitható meg.',
      'The navigation app could not be opened.',
      'Die Navigations-App konnte nicht geöffnet werden.',
    ));
  }

  Future<CameraDescription?> _backCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;
    final backs =
        cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
    return backs.isNotEmpty ? backs.first : cameras.first;
  }

  Future<void> _openCmrScanner() async {
    try {
      final camera = await _backCamera();
      if (!mounted) return;
      if (camera == null) {
        _snack(_l('Nem található kamera.', 'No camera found.', 'Keine Kamera gefunden.'));
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScannerScreen(camera: camera)),
      );
    } catch (e) {
      _snack('A scanner nem indult el: $e');
    }
  }

  Future<void> _openInvoiceScanner() async {
    try {
      final camera = await _backCamera();
      if (!mounted) return;
      if (camera == null) {
        _snack('Nem található kamera.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InvoiceScannerScreen(camera: camera)),
      );
    } catch (e) {
      _snack('A számla scanner nem indult el: $e');
    }
  }

  Future<_SignalDelivery> _sendSignal(
    String type, {
    bool urgent = false,
    String? message,
    bool showFeedback = true,
  }) async {
    if (_plate.isEmpty) return _SignalDelivery.failed;
    if (mounted) setState(() => _actionBusy = true);

    double? latitude;
    double? longitude;
    try {
      final status = await _tracking.currentStatus();
      latitude = status.lastPosition?.latitude;
      longitude = status.lastPosition?.longitude;
    } catch (_) {
      // A driver signal is more important than optional GPS enrichment.
    }

    final occurredAt = DateTime.now().toUtc();
    final signal = _PendingDriverSignal(
      id: _newSignalId(occurredAt),
      type: type,
      urgent: urgent,
      occurredAt: occurredAt,
      message: message,
      latitude: latitude,
      longitude: longitude,
    );

    try {
      await _api.sendSignal(
        plate: _plate,
        type: type,
        urgent: urgent,
        message: message,
        latitude: latitude,
        longitude: longitude,
        eventId: signal.id,
        occurredAt: occurredAt,
      );
      if (showFeedback && mounted) {
        _snack(
          _l(
            'Jelzés elküldve a főnökségnek.',
            'Signal sent to the office.',
            'Meldung an die Disposition gesendet.',
          ),
        );
      }
      return _SignalDelivery.sent;
    } on DriverApiException catch (error) {
      if (const {400, 422}.contains(error.statusCode)) {
        if (showFeedback && mounted) {
          _snack(
            _l(
              'A jelzés hibás adat miatt nem küldhető el.',
              'The signal could not be sent because its data is invalid.',
              'Die Meldung konnte wegen ungültiger Daten nicht gesendet werden.',
            ),
          );
        }
        return _SignalDelivery.failed;
      }
      await _queueSignal(signal);
    } on StateError {
      await _queueSignal(signal);
    } catch (_) {
      await _queueSignal(signal);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }

    if (showFeedback && mounted) {
      _snack(
        _l(
          'Nincs stabil kapcsolat. A jelzést elmentettem, és automatikusan elküldöm.',
          'No stable connection. The signal was saved and will upload automatically.',
          'Keine stabile Verbindung. Die Meldung wurde gespeichert und wird automatisch gesendet.',
        ),
      );
    }
    return _SignalDelivery.queued;
  }

  DriverStop? _nextStopOfType(String type) {
    final job = _job;
    if (job == null) return null;
    for (final stop in job.stops) {
      if (!_isStopCompleted(stop) && stop.type == type) return stop;
    }
    return null;
  }

  Future<String> _queueStopForLater(
    DriverStop stop,
    String action,
    String source,
    DateTime occurredAt,
  ) async {
    await _queuePendingStopAction(
      stop,
      action,
      source,
      occurredAt,
    );
    return action == 'arrived'
        ? _l(
            'Nincs stabil kapcsolat. A megérkezést elmentettem a telefonon, és automatikusan elküldöm.',
            'No stable connection. Arrival was saved on the phone and will upload automatically.',
            'Keine stabile Verbindung. Die Ankunft wurde auf dem Telefon gespeichert und wird automatisch gesendet.',
          )
        : _l(
            'Nincs stabil kapcsolat. A kész állapotot elmentettem, továbbléphetsz; automatikusan szinkronizálom.',
            'No stable connection. Completion was saved locally; you can continue and it will sync automatically.',
            'Keine stabile Verbindung. Der Abschluss wurde lokal gespeichert; du kannst weiterfahren, die Synchronisierung erfolgt automatisch.',
          );
  }

  Future<String> _markStop(
    DriverStop stop,
    String action, {
    required String expectedType,
    String source = 'voice',
  }) async {
    if (stop.type != expectedType) {
      return expectedType == 'pickup'
          ? _l(
              'A következő megálló nem felrakó.',
              'The next stop is not a pickup.',
              'Der nächste Stopp ist keine Abholung.',
            )
          : _l(
              'A következő megálló nem lerakó.',
              'The next stop is not a delivery.',
              'Der nächste Stopp ist keine Zustellung.',
            );
    }
    final occurredAt = DateTime.now().toUtc();

    if (_pendingStopActions[stop.id]?.isNotEmpty == true) {
      final message = await _queueStopForLater(
        stop,
        action,
        source,
        occurredAt,
      );
      unawaited(_flushPendingStopActions());
      return message;
    }

    try {
      await _api.updateStop(
        plate: _plate,
        stopId: stop.id,
        action: action,
        source: source,
        occurredAt: occurredAt,
      );
      await _refreshJobs();
      if (action == 'arrived') {
        return expectedType == 'pickup'
            ? _l(
                'Megérkezés a felrakóra rögzítve.',
                'Arrival at pickup recorded.',
                'Ankunft an der Ladestelle gespeichert.',
              )
            : _l(
                'Megérkezés a lerakóra rögzítve.',
                'Arrival at delivery recorded.',
                'Ankunft an der Entladestelle gespeichert.',
              );
      }
      return expectedType == 'pickup'
          ? _l(
              'Felrakás kész. Jöhet a következő megálló.',
              'Pickup complete. Ready for the next stop.',
              'Beladung fertig. Weiter zum nächsten Stopp.',
            )
          : _l(
              'Lerakás kész. Rögzítettem.',
              'Delivery complete. Recorded.',
              'Entladung fertig. Gespeichert.',
            );
    } on DriverApiException catch (error) {
      if (_isTerminalPendingStopError(error)) {
        return _l(
          'A stop állapotát a szerver elutasította. Frissítsd a fuvart vagy szólj az adminnak.',
          'The server rejected the stop update. Refresh the job or contact the administrator.',
          'Der Server hat die Stopp-Aktualisierung abgelehnt. Auftrag aktualisieren oder Administration kontaktieren.',
        );
      }
      return _queueStopForLater(
        stop,
        action,
        source,
        occurredAt,
      );
    } on StateError {
      return _queueStopForLater(
        stop,
        action,
        source,
        occurredAt,
      );
    } catch (_) {
      return _queueStopForLater(
        stop,
        action,
        source,
        occurredAt,
      );
    }
  }

  Future<void> _runPrimaryStopAction() async {
    final stop = _stop;
    if (stop == null || _actionBusy) return;

    if (_isStopArrived(stop)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF071522),
          title: Text(
            stop.type == 'delivery'
                ? _l(
                    'Lerakás befejezése?',
                    'Finish delivery?',
                    'Entladung abschließen?',
                  )
                : _l(
                    'Felrakás befejezése?',
                    'Finish pickup?',
                    'Beladung abschließen?',
                  ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            _l(
              'Csak akkor jelöld késznek, ha a rakodás valóban befejeződött.',
              'Mark it complete only when loading/unloading is really finished.',
              'Nur als fertig markieren, wenn die Be-/Entladung wirklich abgeschlossen ist.',
            ),
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_l('MÉGSE', 'CANCEL', 'ABBRECHEN')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_l('IGEN, KÉSZ', 'YES, COMPLETE', 'JA, FERTIG')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _actionBusy = true);
    try {
      final action = _isStopArrived(stop) ? 'completed' : 'arrived';
      final message = await _markStop(
        stop,
        action,
        expectedType: stop.type,
        source: 'touch',
      );
      if (!mounted) return;
      _snack(message);
      setState(() => _index = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_homeScrollController.hasClients) {
          _homeScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _callCurrentContactTouch() async {
    if (_actionBusy) return;
    final message = await _callCurrentContact();
    if (mounted) _snack(message);
  }

  Future<String> _callCurrentContact() async {
    final stop = _stop;
    if (stop == null) {
      return _l(
        'Nincs aktív megálló.',
        'There is no active stop.',
        'Es gibt keinen aktiven Stopp.',
      );
    }
    final phone = stop.phone.trim();
    if (phone.isEmpty) {
      return _l(
        'Ehhez a megállóhoz nincs telefonszám megadva.',
        'No phone number is available for this stop.',
        'Für diesen Stopp ist keine Telefonnummer hinterlegt.',
      );
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return _l(
        'A telefonhívást nem sikerült elindítani.',
        'The phone call could not be started.',
        'Der Anruf konnte nicht gestartet werden.',
      );
    }
    return _l(
      'Hívom a kapcsolattartót.',
      'Calling the contact person.',
      'Ich rufe den Ansprechpartner an.',
    );
  }

  String _jobVoiceSummary() {
    final job = _job;
    if (job == null) {
      return _l(
        'Nincs aktív fuvar.',
        'There is no active job.',
        'Es gibt keinen aktiven Auftrag.',
      );
    }
    final stop = job.currentStop;
    if (stop == null) {
      return _l(
        'A fuvar minden megállója kész.',
        'All stops on the job are complete.',
        'Alle Stopps des Auftrags sind abgeschlossen.',
      );
    }
    final company = stop.company.trim();
    final companyPart = company.isEmpty ? '' : ' $company.';
    if (AimsLocaleController.instance.languageCode == 'en') {
      final kind = stop.type == 'pickup' ? 'pickup' : 'delivery';
      return 'Active job: ${job.reference}. Next $kind.$companyPart Address: ${stop.address}.';
    }
    if (AimsLocaleController.instance.languageCode == 'de') {
      final kind = stop.type == 'pickup' ? 'Abholung' : 'Zustellung';
      return 'Aktiver Auftrag: ${job.reference}. Nächster Stopp: $kind.$companyPart Adresse: ${stop.address}.';
    }
    final kind = stop.type == 'pickup' ? 'felrakó' : 'lerakó';
    return 'Aktív fuvar: ${job.reference}. Következő $kind.$companyPart Cím: ${stop.address}.';
  }

  Future<String> _handleVoiceCommand(AimsVoiceCommand command) async {
    final current = _stop;
    final noStop = _l(
      'Nincs aktív megálló.',
      'There is no active stop.',
      'Es gibt keinen aktiven Stopp.',
    );

    switch (command.intent) {
      case AimsVoiceIntent.showJob:
        if (mounted) setState(() => _index = 1);
        return _jobVoiceSummary();
      case AimsVoiceIntent.showNextJobs:
        final count = _otherJobs.length;
        if (mounted && _jobs.isNotEmpty) {
          unawaited(_showJobsBrowser());
        }
        return count == 0
            ? _l(
                'Nincs további kiosztott munkád.',
                'There are no additional assigned jobs.',
                'Es gibt keine weiteren zugewiesenen Aufträge.',
              )
            : _l(
                '$count további munkád van. Megnyitottam a listát.',
                'You have $count more assigned job(s). I opened the list.',
                'Du hast $count weitere Aufträge. Ich habe die Liste geöffnet.',
              );
      case AimsVoiceIntent.navigateNext:
        if (current == null) return noStop;
        await _openMapsForStop(current);
        return _l(
          'Indítom a navigációt a következő címre.',
          'Starting navigation to the next address.',
          'Ich starte die Navigation zur nächsten Adresse.',
        );
      case AimsVoiceIntent.assistantHelp:
        return _l(
          'Tudok fuvart és következő munkát mutatni, címet felolvasni, navigációt indítani, kapcsolattartót hívni, érkezést és rakodást rögzíteni, CMR-t vagy tankolási bizonylatot nyitni, valamint késést, várakozást, műszaki hibát és sürgős jelzést küldeni.',
          'I can show the current and next jobs, read addresses, start navigation, call contacts, record arrivals and loading, open CMR or fuel receipt scanning, and send delay, waiting, technical or urgent alerts.',
          'Ich kann aktuelle und nächste Aufträge zeigen, Adressen vorlesen, Navigation starten, Kontakte anrufen, Ankunft und Be-/Entladung erfassen, CMR oder Tankbelege öffnen und Meldungen senden.',
        );
      case AimsVoiceIntent.trackingStatus:
        final running = _trackingStatus?.running == true;
        return running
            ? _l(
                'A GPS követés aktív.',
                'GPS tracking is active.',
                'GPS-Tracking ist aktiv.',
              )
            : _l(
                'A GPS követés jelenleg nem aktív.',
                'GPS tracking is not active right now.',
                'GPS-Tracking ist derzeit nicht aktiv.',
              );
      case AimsVoiceIntent.navigatePickup:
        final stop = _nextStopOfType('pickup');
        if (stop == null) {
          return _l('Nincs következő felrakó.', 'There is no next pickup.',
              'Es gibt keine nächste Abholung.');
        }
        await _openMapsForStop(stop);
        return _l('Navigáció indítása a felrakóra.',
            'Starting navigation to the pickup.',
            'Navigation zur Ladestelle wird gestartet.');
      case AimsVoiceIntent.navigateDelivery:
        final stop = _nextStopOfType('delivery');
        if (stop == null) {
          return _l('Nincs következő lerakó.', 'There is no next delivery.',
              'Es gibt keine nächste Zustellung.');
        }
        await _openMapsForStop(stop);
        return _l('Navigáció indítása a lerakóra.',
            'Starting navigation to the delivery.',
            'Navigation zur Entladestelle wird gestartet.');
      case AimsVoiceIntent.arrivePickup:
        if (current == null) return noStop;
        return _markStop(current, 'arrived', expectedType: 'pickup');
      case AimsVoiceIntent.arriveDelivery:
        if (current == null) return noStop;
        return _markStop(current, 'arrived', expectedType: 'delivery');
      case AimsVoiceIntent.pickupComplete:
        if (current == null) return noStop;
        return _markStop(current, 'completed', expectedType: 'pickup');
      case AimsVoiceIntent.deliveryComplete:
        if (current == null) return noStop;
        return _markStop(current, 'completed', expectedType: 'delivery');
      case AimsVoiceIntent.nextAddress:
        if (current == null) {
          return _l('Nincs következő cím.', 'There is no next address.',
              'Es gibt keine nächste Adresse.');
        }
        final company = current.company.trim();
        if (AimsLocaleController.instance.languageCode == 'en') {
          return company.isEmpty
              ? 'The next address is ${current.address}.'
              : 'The next stop is $company. Address: ${current.address}.';
        }
        if (AimsLocaleController.instance.languageCode == 'de') {
          return company.isEmpty
              ? 'Die nächste Adresse ist ${current.address}.'
              : 'Der nächste Stopp ist $company. Adresse: ${current.address}.';
        }
        return company.isEmpty
            ? 'A következő cím: ${current.address}.'
            : 'A következő megálló $company. Cím: ${current.address}.';
      case AimsVoiceIntent.callContact:
        return _callCurrentContact();
      case AimsVoiceIntent.delaySignal:
        await _sendSignal('Késés', message: 'Voice command');
        return _l('A késés jelzést elküldtem a főnökségnek.',
            'The delay notice was sent to the office.',
            'Die Verspätungsmeldung wurde an die Disposition gesendet.');
      case AimsVoiceIntent.fuelReceipt:
        unawaited(_openInvoiceScanner());
        return _l('Megnyitottam az AIMS számla scannert.',
            'I opened the AIMS invoice scanner.',
            'Der AIMS-Rechnungsscanner ist geöffnet.');
      case AimsVoiceIntent.cmrDocument:
        unawaited(_openCmrScanner());
        return _l('Megnyitottam a CMR scannert.',
            'I opened the CMR scanner.', 'Der CMR-Scanner ist geöffnet.');
      case AimsVoiceIntent.technicalIssue:
        await _sendSignal('Műszaki hiba', message: 'Voice command');
        return _l('A műszaki hibát jeleztem a főnökségnek.',
            'The technical issue was reported to the office.',
            'Das technische Problem wurde an die Disposition gemeldet.');
      case AimsVoiceIntent.readJobDetails:
        return _jobVoiceSummary();
      case AimsVoiceIntent.waitingSignal:
        await _sendSignal('Várakozás', message: 'Voice command');
        return _l('A várakozást jeleztem.', 'The waiting status was reported.',
            'Die Wartezeit wurde gemeldet.');
      case AimsVoiceIntent.urgentSignal:
        await _sendSignal('Baleset / sürgős',
            urgent: true, message: 'Voice command');
        return _l('Sürgős jelzést küldtem.', 'I sent an urgent alert.',
            'Ich habe eine dringende Meldung gesendet.');
      case AimsVoiceIntent.unknown:
        return AimsLocaleController.instance.t('not_understood');
    }
  }

  Future<void> _setHandsFree(bool enabled) async {
    if (_handsFreeBusy) return;
    setState(() => _handsFreeBusy = true);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (enabled) {
        final ok = await _voice.enableHandsFree();
        await prefs.setBool(_prefsHandsFree, ok);
        if (!ok && mounted) {
          _snack(_l('A hangfelismerés nem indítható. Ellenőrizd a mikrofon engedélyt.', 'Speech recognition could not start. Check microphone permission.', 'Spracherkennung konnte nicht gestartet werden. Mikrofonberechtigung prüfen.'));
        }
      } else {
        await _voice.disableHandsFree();
        await prefs.setBool(_prefsHandsFree, false);
      }
    } finally {
      if (mounted) setState(() => _handsFreeBusy = false);
    }
  }

  void _snack(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted || _plate.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastResumeRefreshAt;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 10)) {
      return;
    }
    _lastResumeRefreshAt = now;
    unawaited(_refreshAfterResume());
  }

  Future<void> _refreshAfterResume() async {
    try {
      final status = await _tracking.currentStatus();
      if (mounted) setState(() => _trackingStatus = status);
    } catch (_) {
      // Job refresh must still run even if the tracking status is unavailable.
    }
    if (_pendingStopActions.isNotEmpty) {
      await _flushPendingStopActions(refreshAfter: false);
    }
    if (_pendingSignals.isNotEmpty) {
      await _flushPendingSignals();
    }
    await _refreshJobs(showLoading: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshGeneration++;
    _pendingStopRetryTimer?.cancel();
    _pendingStopRetryTimer = null;
    _pendingSignalRetryTimer?.cancel();
    _pendingSignalRetryTimer = null;
    _pushSub?.cancel();
    _trackingSub?.cancel();
    _voiceSub?.cancel();
    _homeScrollController.dispose();
    unawaited(_voice.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF06162A),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: _header(),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _home(),
                _trip(),
                _quickSignal(),
                _documents(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: const Color(0xFF030D16),
        indicatorColor: _blue.withValues(alpha: .18),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: AimsLocaleController.instance.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_shipping_outlined),
            selectedIcon: const Icon(Icons.local_shipping),
            label: AimsLocaleController.instance.t('my_job'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.campaign_outlined),
            selectedIcon: const Icon(Icons.campaign),
            label: AimsLocaleController.instance.t('quick_signal'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.description_outlined),
            selectedIcon: const Icon(Icons.description),
            label: AimsLocaleController.instance.t('docs'),
          ),
        ],
      ),
    );
  }

  Widget _page(
    List<Widget> children, {
    ScrollController? controller,
  }) =>
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _refreshJobs,
            child: ListView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: children,
            ),
          ),
        ),
      );

  Widget _header() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const AimsFlowLogo(width: 42, height: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AIMS FLOW',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _l('SOFŐR', 'DRIVER', 'FAHRER'),
                        if (_plate.isNotEmpty) _displayPlate(_plate),
                        if (_plate.isEmpty && _driverName.isNotEmpty) _driverName,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _status(
                _trackingStatus?.running == true
                    ? _l('GPS AKTÍV', 'GPS ACTIVE', 'GPS AKTIV')
                    : 'GPS',
                _trackingStatus?.running == true ? _green : Colors.white38,
              ),
              const SizedBox(width: 6),
              const AimsLanguageSelector(compact: true),
            ],
          ),
        ],
      );

  Widget _home() {
    final job = _job;
    final stop = _stop;
    final trackingNotice = _driverTrackingNotice();
    final pendingStopNotice = _pendingStopNotice();
    final pendingSignalNotice = _pendingSignalNotice();
    final currentCompany = stop?.company.trim().isNotEmpty == true
        ? stop!.company
        : job == null
            ? _l('Nincs aktív fuvar', 'No active job', 'Kein aktiver Auftrag')
            : stop?.type == 'delivery'
                ? _l('Lerakó', 'Delivery', 'Entladestelle')
                : _l('Felrakó', 'Pickup', 'Ladestelle');

    return _page([
      if (_loading)
        const LinearProgressIndicator(minHeight: 2)
      else
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentCompany,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                job == null
                    ? _l(
                        'Új munka érkezésekor a Flow itt azonnal szól.',
                        'Flow notifies you here immediately when a new job arrives.',
                        'Flow meldet hier sofort einen neuen Auftrag.',
                      )
                    : _l(
                        'AKTÍV FUVAR · ${job.reference} · ${job.stops.length} stop',
                        'ACTIVE JOB · ${job.reference} · ${job.stops.length} stops',
                        'AKTIVER AUFTRAG · ${job.reference} · ${job.stops.length} Stopps',
                      ),
                style: const TextStyle(
                  color: _blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 18),
              if (job == null) ...[
                Text(
                  _l('Nincs teendőd.', 'Nothing to do.', 'Keine Aufgabe.'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _l(
                    'A nyomkövetés és az értesítések a háttérben működnek.',
                    'Tracking and notifications continue in the background.',
                    'Tracking und Benachrichtigungen laufen im Hintergrund.',
                  ),
                  style: const TextStyle(color: Colors.white54, height: 1.35),
                ),
              ] else if (stop == null) ...[
                Text(
                  _l(
                    'A fuvar minden megállója kész.',
                    'All stops on this job are complete.',
                    'Alle Stopps dieses Auftrags sind abgeschlossen.',
                  ),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    _status(
                      stop.type == 'delivery'
                          ? _l('LERAKÓ', 'DELIVERY', 'ENTLADUNG')
                          : _l('FELRAKÓ', 'PICKUP', 'BELADUNG'),
                      _isStopArrived(stop) ? _green : _blue,
                    ),
                    const Spacer(),
                    Text(
                      '#${stop.order}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _l('KÖVETKEZŐ LÉPÉS', 'NEXT STEP', 'NÄCHSTER SCHRITT'),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _isStopArrived(stop)
                      ? (stop.type == 'delivery'
                          ? _l(
                              'Lerakás befejezése',
                              'Finish delivery',
                              'Entladung abschließen',
                            )
                          : _l(
                              'Felrakás befejezése',
                              'Finish pickup',
                              'Beladung abschließen',
                            ))
                      : (stop.type == 'delivery'
                          ? _l(
                              'Indulás a lerakóra',
                              'Go to delivery',
                              'Zur Entladestelle fahren',
                            )
                          : _l(
                              'Indulás a felrakóra',
                              'Go to pickup',
                              'Zur Ladestelle fahren',
                            )),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 9),
                SelectableText(
                  stop.address,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('flow-primary-navigation'),
                  onPressed: _actionBusy ? null : _openMaps,
                  icon: const Icon(Icons.navigation_rounded, size: 26),
                  label: Text(
                    _l(
                      'NAVIGÁCIÓ INDÍTÁSA',
                      'START NAVIGATION',
                      'NAVIGATION STARTEN',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    backgroundColor: _blue,
                    foregroundColor: const Color(0xFF00131F),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: .3,
                    ),
                  ),
                ),
                if (stop.phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    key: const Key('flow-primary-call'),
                    onPressed: _actionBusy
                        ? null
                        : () => unawaited(_callCurrentContactTouch()),
                    icon: const Icon(Icons.call_rounded),
                    label: Text(
                      _l(
                        'KAPCSOLATTARTÓ HÍVÁSA',
                        'CALL CONTACT',
                        'KONTAKT ANRUFEN',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF24557D)),
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                FilledButton.icon(
                  key: const Key('flow-primary-stop-action'),
                  onPressed: _actionBusy
                      ? null
                      : () => unawaited(_runPrimaryStopAction()),
                  icon: Icon(
                    _isStopArrived(stop)
                        ? Icons.task_alt_rounded
                        : Icons.location_on_rounded,
                  ),
                  label: Text(
                    _isStopArrived(stop)
                        ? (stop.type == 'delivery'
                            ? _l(
                                'LERAKÁS KÉSZ',
                                'DELIVERY COMPLETE',
                                'ENTLADUNG FERTIG',
                              )
                            : _l(
                                'FELRAKÁS KÉSZ',
                                'PICKUP COMPLETE',
                                'BELADUNG FERTIG',
                              ))
                        : _l(
                            'MEGÉRKEZTEM',
                            'I HAVE ARRIVED',
                            'ANGEKOMMEN',
                          ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    backgroundColor: _isStopArrived(stop) ? _green : const Color(0xFF0F3852),
                    foregroundColor: _isStopArrived(stop)
                        ? const Color(0xFF001B12)
                        : Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      _l('JÁRMŰ', 'VEHICLE', 'FAHRZEUG'),
                      _plate.isEmpty ? '—' : _plate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metric(
                      'GPS',
                      _trackingQueuedOffline
                          ? _l('OFFLINE', 'OFFLINE', 'OFFLINE')
                          : _trackingStatus?.running == true
                              ? _l('AKTÍV', 'ACTIVE', 'AKTIV')
                              : _l('INDÍTÁS', 'START', 'STARTEN'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (pendingStopNotice != null) ...[
        const SizedBox(height: 10),
        _info(pendingStopNotice),
      ],
      if (pendingSignalNotice != null) ...[
        const SizedBox(height: 10),
        _info(pendingSignalNotice),
      ],
      if (trackingNotice != null) ...[
        const SizedBox(height: 10),
        _info(trackingNotice),
      ],
      const SizedBox(height: 12),
      _jobsShortcut(),
      if (_message != null) ...[
        const SizedBox(height: 10),
        _info(_message!),
      ],
      const SizedBox(height: 12),
      _panel(
        Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: _blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _l(
                  'Új fuvarnál hangos push érkezik. Lezárt képernyőn is jelzi, amíg vissza nem igazolod.',
                  'A new job triggers an audible push. It also appears on the lock screen until you acknowledge it.',
                  'Bei einem neuen Auftrag kommt eine hörbare Push-Meldung. Sie bleibt auch auf dem Sperrbildschirm sichtbar, bis du sie bestätigst.',
                ),
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _voicePanel(),
    ], controller: _homeScrollController);
  }

  Widget _voicePanel() => _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_voiceState.enabled ? _green : _blue)
                        .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (_voiceState.enabled ? _green : _blue)
                          .withValues(alpha: .35),
                    ),
                  ),
                  child: Icon(
                    _voiceState.mode == AimsVoiceMode.speaking
                        ? Icons.graphic_eq_rounded
                        : Icons.mic_rounded,
                    color: _voiceState.enabled ? _green : _blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l(
                          'AIMS VIRTUÁLIS ASSZISZTENS',
                          'AIMS VIRTUAL ASSISTANT',
                          'AIMS VIRTUELLER ASSISTENT',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        switch (_voiceState.mode) {
                          AimsVoiceMode.command => _voiceState.lastHeard.trim().isEmpty
                              ? _l(
                                  'HALLGATLAK — mondd természetesen.',
                                  'LISTENING — speak naturally.',
                                  'ICH HÖRE — sprich ganz natürlich.',
                                )
                              : _l(
                                  'ÉRTETTEM: ${_voiceState.lastHeard}',
                                  'GOT IT: ${_voiceState.lastHeard}',
                                  'VERSTANDEN: ${_voiceState.lastHeard}',
                                ),
                          /* legacy wording kept below unreachable by design */
                          AimsVoiceMode.off => _l(
                              'Érintsd meg és mondd, mit szeretnél.',
                              'Tap and tell me what you need.',
                              'Tippe und sage, was du brauchst.',
                            ),
                          AimsVoiceMode.speaking => _l(
                              'VÁLASZOLOK…',
                              'RESPONDING…',
                              'ICH ANTWORTE…',
                            ),
                          AimsVoiceMode.wakeWord => _l(
                              'KÉSZEN ÁLLOK — mondd: „AIMS”',
                              'READY — say “AIMS”',
                              'BEREIT — sage „AIMS“',
                            ),
                          AimsVoiceMode.error => _l(
                              'NEM HALLOTTALAK — érintsd meg a mikrofont',
                              'I COULD NOT HEAR YOU — tap the microphone',
                              'NICHT VERSTANDEN — tippe auf das Mikrofon',
                            ),
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('aims-assistant-talk'),
              onPressed: _handsFreeBusy
                  ? null
                  : () => unawaited(_voice.triggerAssistant()),
              icon: const Icon(Icons.record_voice_over_rounded, size: 26),
              label: Text(
                _l(
                  'BESZÉLJ AZ AIMS-HEZ',
                  'TALK TO AIMS',
                  'MIT AIMS SPRECHEN',
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF06131F),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF173B54)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _l(
                        'Hands-Free: mondd, hogy „AIMS”, majd a parancsot.',
                        'Hands-Free: say “AIMS”, then your command.',
                        'Hands-Free: sage „AIMS“, dann deinen Befehl.',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('aims-hands-free-toggle'),
                    value: _voiceState.enabled,
                    onChanged: _handsFreeBusy ? null : _setHandsFree,
                  ),
                ],
              ),
            ),
            if (_voiceState.message.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _voiceState.message,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ],
            if (_voiceState.lastHeard.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                _l(
                  'Hallottam: ${_voiceState.lastHeard}',
                  'Heard: ${_voiceState.lastHeard}',
                  'Gehört: ${_voiceState.lastHeard}',
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _assistantExample(
                  _l('Mutasd a fuvarom', 'Show my job', 'Zeige meinen Auftrag'),
                ),
                _assistantExample(
                  _l('Következő cím', 'Next address', 'Nächste Adresse'),
                ),
                _assistantExample(
                  _l(
                    'Navigálj a felrakóra',
                    'Navigate to pickup',
                    'Zur Abholung navigieren',
                  ),
                ),
                _assistantExample(
                  _l(
                    'Hívd a kapcsolattartót',
                    'Call the contact',
                    'Kontakt anrufen',
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _assistantExample(String command) => ActionChip(
        label: Text(command),
        onPressed: () => unawaited(_voice.executeText(command)),
        visualDensity: VisualDensity.compact,
      );

  Widget _jobsShortcut() {
    final current = _job;
    final others = _otherJobs;
    final subtitle = current == null
        ? _l(
            'Nincs kiosztott munka.',
            'No assigned jobs.',
            'Keine zugewiesenen Aufträge.',
          )
        : others.isEmpty
            ? _l(
                'Aktív munka részleteinek megnyitása.',
                'Open the active job details.',
                'Details des aktiven Auftrags öffnen.',
              )
            : _l(
                '${others.length} további kiosztott munka vár rád.',
                '${others.length} more assigned job(s) are waiting.',
                '${others.length} weitere Aufträge warten.',
              );

    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l(
              'KÖVETKEZŐ FELADAT / MUNKÁK',
              'NEXT TASK / JOBS',
              'NÄCHSTE AUFGABE / AUFTRÄGE',
            ),
            style: const TextStyle(
              color: _blue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('flow-next-jobs'),
            onPressed: _jobs.isEmpty ? null : _showJobsBrowser,
            icon: const Icon(Icons.format_list_bulleted_rounded),
            label: Text(
              _l('MUNKÁK MEGNYITÁSA', 'OPEN JOBS', 'AUFTRÄGE ÖFFNEN'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showJobsBrowser() async {
    if (_jobs.isEmpty || !mounted) return;

    final selected = await showModalBottomSheet<DriverJob>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF04101C),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .55,
        maxChildSize: .94,
        builder: (context, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _l('Következő feladatok', 'Assigned jobs', 'Zugewiesene Aufträge'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _l(
                  'Koppints egy munkára a pontos adatokhoz.',
                  'Tap a job to see all exact details.',
                  'Tippe auf einen Auftrag für alle Details.',
                ),
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 14),
              for (final job in _jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(sheetContext, job),
                    child: Ink(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071725),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: job.id == _job?.id
                              ? _green.withValues(alpha: .45)
                              : const Color(0xFF173B54),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  job.reference,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                job.id == _job?.id
                                    ? _l('AKTÍV', 'ACTIVE', 'AKTIV')
                                    : _l('KÖVETKEZŐ', 'NEXT', 'NÄCHSTER'),
                                style: TextStyle(
                                  color: job.id == _job?.id ? _green : _blue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _jobRoute(job),
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _l(
                              '${job.stops.length} megálló',
                              '${job.stops.length} stops',
                              '${job.stops.length} Stopps',
                            ),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _showJobDetails(selected);
    }
  }

  String _jobRoute(DriverJob job) {
    if (job.stops.isEmpty) return '—';
    final first = job.stops.first;
    final last = job.stops.last;
    final from = first.company.trim().isNotEmpty ? first.company : first.address;
    final to = last.company.trim().isNotEmpty ? last.company : last.address;
    return '$from → $to';
  }

  Future<void> _showJobDetails(DriverJob job) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF04101C),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .86,
        minChildSize: .60,
        maxChildSize: .96,
        builder: (context, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Text(
                job.reference,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _jobRoute(job),
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              for (final stop in job.stops)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071725),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF173B54)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${stop.order}. ${stop.type == 'delivery' ? _l('LERAKÓ', 'DELIVERY', 'ENTLADUNG') : _l('FELRAKÓ', 'PICKUP', 'BELADUNG')}",
                        style: const TextStyle(
                          color: _blue,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (stop.company.trim().isNotEmpty)
                        Text(
                          stop.company,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (stop.company.trim().isNotEmpty)
                        const SizedBox(height: 4),
                      SelectableText(
                        stop.address,
                        style: const TextStyle(color: Colors.white70, height: 1.35),
                      ),
                      if (stop.phone.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        SelectableText(
                          stop.phone,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  stop.address.trim().isEmpty &&
                                          !RoamingResilience.validCoordinates(
                                            stop.latitude,
                                            stop.longitude,
                                          )
                                      ? null
                                      : () =>
                                          unawaited(_openMapsForStop(stop)),
                              icon: const Icon(Icons.navigation_rounded),
                              label: Text(
                                _l('NAVIGÁCIÓ', 'NAVIGATION', 'NAVIGATION'),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                              ),
                            ),
                          ),
                          if (stop.phone.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => unawaited(
                                launchUrl(
                                  Uri(scheme: 'tel', path: stop.phone.trim()),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                              icon: const Icon(Icons.call_rounded),
                              iconSize: 24,
                              constraints: const BoxConstraints.tightFor(
                                width: 56,
                                height: 56,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trip() {
    final job = _job;
    return _page([
      Text(
        _l('Fuvarom', 'My job', 'Mein Auftrag'),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        job == null
            ? _l(
                'Nincs aktív fuvar.',
                'There is no active job.',
                'Es gibt keinen aktiven Auftrag.',
              )
            : job.reference,
        style: const TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 14),
      _jobsShortcut(),
      const SizedBox(height: 12),
      if (job == null)
        _panel(
          Text(
            _l(
              'A következő kiosztott fuvar itt jelenik meg.',
              'The next assigned job will appear here.',
              'Der nächste zugewiesene Auftrag erscheint hier.',
            ),
          ),
        )
      else ...[
        ...job.stops.map(
          (stop) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _stopCard(stop),
          ),
        ),
        const SizedBox(height: 4),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _l('Nyomkövetés', 'Tracking', 'Tracking'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                _trackingStatus?.lastPosition == null
                    ? _l(
                        'GPS-pozícióra vár.',
                        'Waiting for GPS position.',
                        'Warte auf GPS-Position.',
                      )
                    : _l(
                        'Útvonal mentve · utolsó pont elküldve a szervernek.',
                        'Route saved · latest point sent to the server.',
                        'Route gespeichert · letzter Punkt an den Server gesendet.',
                      ),
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 10),
              Text(
                _l(
                  '15 és 30 perc hiteles tétlenségnél a főnökség push értesítést kap. A GPS-zaj nem nullázza az időzítőt.',
                  'The office gets a push after 15 and 30 minutes of confirmed inactivity. GPS noise does not reset the timer.',
                  'Die Disposition erhält nach 15 und 30 Minuten bestätigtem Stillstand eine Push-Meldung. GPS-Rauschen setzt den Timer nicht zurück.',
                ),
                style: const TextStyle(color: Colors.white38, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _quickSignal() => _page([
        Text(
          _l('Gyors jelzés', 'Quick signal', 'Schnellmeldung'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          _l(
            'Egy koppintás. A rendszám, fuvar, időpont és GPS-hely automatikusan mellé kerül.',
            'One tap. Plate, job, time and GPS location are attached automatically.',
            'Ein Tippen. Kennzeichen, Auftrag, Zeit und GPS-Position werden automatisch hinzugefügt.',
          ),
          style: const TextStyle(color: Colors.white54, height: 1.4),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.02,
          children: [
            _signal(
              Icons.schedule_rounded,
              _l('Késés', 'Delay', 'Verspätung'),
              _l(
                'Forgalom / csúszás',
                'Traffic / delay',
                'Verkehr / Verzögerung',
              ),
              () => _sendSignal('Késés'),
            ),
            _signal(
              Icons.timer_outlined,
              _l('Várakozás', 'Waiting', 'Warten'),
              _l('Rakodás / telephely', 'Loading / site', 'Beladung / Standort'),
              () => _sendSignal('Várakozás'),
            ),
            _signal(
              Icons.location_off_outlined,
              _l('Cím / rakodás', 'Address / loading', 'Adresse / Beladung'),
              _l(
                'Nem található / nem engednek be',
                'Cannot find it / no entry',
                'Nicht auffindbar / kein Zutritt',
              ),
              () => _sendSignal('Cím / rakodás'),
            ),
            _signal(
              Icons.build_outlined,
              _l('Műszaki hiba', 'Technical issue', 'Technisches Problem'),
              _l('Autó / gumi / motor', 'Vehicle / tyre / engine', 'Fahrzeug / Reifen / Motor'),
              () => _sendSignal('Műszaki hiba'),
            ),
            _signal(
              Icons.sos_outlined,
              _l('Sürgős', 'Urgent', 'Dringend'),
              _l(
                'Baleset / azonnali figyelem',
                'Accident / immediate attention',
                'Unfall / sofortige Aufmerksamkeit',
              ),
              () => _sendSignal('Baleset / sürgős', urgent: true),
              danger: true,
            ),
            _signal(
              Icons.more_horiz_rounded,
              _l('Egyéb', 'Other', 'Sonstiges'),
              _l('Írd le röviden', 'Describe briefly', 'Kurz beschreiben'),
              _otherSignal,
            ),
          ],
        ),
      ]);

  Widget _documents() => _page([
        Text(
          _l('Dokumentum', 'Documents', 'Dokumente'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          _l(
            'Fotózd le, a Flow feldolgozza és továbbítja.',
            'Take a photo. Flow processes and forwards it.',
            'Foto aufnehmen. Flow verarbeitet und leitet es weiter.',
          ),
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _openCmrScanner,
                icon: const Icon(Icons.document_scanner_rounded, size: 26),
                label: Text(
                  _l('CMR / DOKUMENTUM', 'CMR / DOCUMENT', 'CMR / DOKUMENT'),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(62),
                  backgroundColor: _blue,
                  foregroundColor: const Color(0xFF00131F),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openInvoiceScanner,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _l(
                    'SZÁMLA SCANNER',
                    'INVOICE SCANNER',
                    'RECHNUNGSSCANNER',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _blue),
                ),
              ),
            ],
          ),
        ),
      ]);

  Future<void> _otherSignal() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: Text(_l('Egyéb jelzés', 'Other signal', 'Sonstige Meldung')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: _l('Mi történt?', 'What happened?', 'Was ist passiert?')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l('MÉGSE', 'CANCEL', 'ABBRECHEN')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_l('KÜLDÉS', 'SEND', 'SENDEN')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.isNotEmpty) {
      await _sendSignal('Egyéb', message: text);
    }
  }

  Widget _stopCard(DriverStop stop) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: stop.id == _stop?.id
                ? _blue
                : _isStopArrived(stop)
                    ? _green.withValues(alpha: .45)
                    : const Color(0xFF173B54),
            width: stop.id == _stop?.id ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: _isStopArrived(stop)
                  ? _green.withValues(alpha: .13)
                  : _blue.withValues(alpha: .13),
              child: Text(
                '${stop.order}',
                style: TextStyle(
                  color: _isStopArrived(stop) ? _green : _blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.company.isEmpty ? _l('Megálló', 'Stop', 'Stopp') : stop.company,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stop.address,
                    style: const TextStyle(color: Colors.white54, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isStopCompleted(stop)
                        ? _l('KÉSZ', 'DONE', 'FERTIG')
                        : _isStopArrived(stop)
                            ? _l('MEGÉRKEZETT', 'ARRIVED', 'ANGEKOMMEN')
                            : stop.id == _stop?.id
                                ? (stop.type == 'delivery'
                                    ? _l(
                                        'KÖVETKEZŐ • LERAKÓ',
                                        'NEXT • DELIVERY',
                                        'NÄCHSTER • ENTLADUNG',
                                      )
                                    : _l(
                                        'KÖVETKEZŐ • FELRAKÓ',
                                        'NEXT • PICKUP',
                                        'NÄCHSTER • BELADUNG',
                                      ))
                                : (stop.type == 'delivery'
                                    ? _l('LERAKÓ', 'DELIVERY', 'ENTLADUNG')
                                    : _l('FELRAKÓ', 'PICKUP', 'BELADUNG')),
                    style: TextStyle(
                      color: _isStopCompleted(stop) || _isStopArrived(stop) ? _green : _blue,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _signal(
    IconData icon,
    String title,
    String detail,
    VoidCallback onTap, {
    bool danger = false,
  }) =>
      InkWell(
        onTap: _actionBusy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: danger
                ? Colors.redAccent.withValues(alpha: .08)
                : _panelColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: danger
                  ? Colors.redAccent.withValues(alpha: .65)
                  : const Color(0xFF173B54),
              width: danger ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: danger ? Colors.redAccent : _blue, size: 30),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      );

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xCC081725),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF24557D)),
        ),
        child: child,
      );

  Widget _status(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(
          '● $text',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF06131F),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF173B54)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ],
        ),
      );

  Widget _info(String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.withValues(alpha: .28)),
        ),
        child: Text(value, style: const TextStyle(color: Colors.white70)),
      );
}