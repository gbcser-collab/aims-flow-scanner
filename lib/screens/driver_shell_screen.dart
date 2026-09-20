[Reading 1000 lines from start (total: 3155 lines, 2155 remaining)]

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
          if (job!.orderData.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Future.microtask(() => _showOrderDetails(job!));
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

[executed on device: GABOR-PC (4f5060cc-3a10-4200-947d-55b7a0fc1e22)]