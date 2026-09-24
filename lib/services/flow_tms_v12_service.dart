import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FlowTmsV12Service {
  FlowTmsV12Service._();

  static final FlowTmsV12Service instance = FlowTmsV12Service._();

  static const _baseUrl = String.fromEnvironment(
    'AIMS_FLOW_V12_BASE_URL',
    defaultValue: '',
  );
  static const _apiKey = String.fromEnvironment(
    'AIMS_FLOW_V12_API_KEY',
    defaultValue: '',
  );

  static const _sessionIdKey = 'aims_flow_v12_session_id';
  static const _sessionPlateKey = 'aims_flow_v12_session_plate';
  static const _sessionLoadKey = 'aims_flow_v12_session_load';
  static const _sessionDriverKey = 'aims_flow_v12_session_driver';

  Future<void> _ioTail = Future<void>.value();
  bool _flushingGps = false;

  bool get enabled => _baseUrl.trim().isNotEmpty && _apiKey.trim().isNotEmpty;

  String _base() => _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'X-Flow-Api-Key': _apiKey,
      };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse('${_base()}$path'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        body['error']?.toString() ?? 'Flow API HTTP ${response.statusCode}',
      );
    }
    return body;
  }

  Future<int?> startSession({
    required String plate,
    required String driverId,
    required String loadId,
  }) async {
    if (!enabled) return null;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getInt(_sessionIdKey);
    if (existing != null &&
        prefs.getString(_sessionPlateKey) == plate &&
        prefs.getString(_sessionLoadKey) == loadId) {
      return existing;
    }

    if (existing != null) {
      try {
        await _post('/api/v1/sessions/end', <String, dynamic>{
          'session_id': existing,
        });
      } catch (_) {}
    }

    final body = await _post('/api/v1/sessions/start', <String, dynamic>{
      'plate': plate,
      'driver_id': driverId,
      'load_id': loadId,
    });
    final sessionId = (body['session_id'] as num?)?.toInt();
    if (sessionId == null) {
      throw const FormatException('Flow session_id missing');
    }
    await prefs.setInt(_sessionIdKey, sessionId);
    await prefs.setString(_sessionPlateKey, plate);
    await prefs.setString(_sessionLoadKey, loadId);
    await prefs.setString(_sessionDriverKey, driverId);
    unawaited(flushGpsQueue());
    return sessionId;
  }

  Future<void> endSession({String? expectedLoadId}) async {
    if (!enabled) return;
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt(_sessionIdKey);
    if (sessionId == null) return;
    final currentLoad = prefs.getString(_sessionLoadKey) ?? '';
    if (expectedLoadId != null &&
        expectedLoadId.isNotEmpty &&
        currentLoad.isNotEmpty &&
        currentLoad != expectedLoadId) {
      return;
    }
    await flushGpsQueue();
    await _post('/api/v1/sessions/end', <String, dynamic>{
      'session_id': sessionId,
    });
    await prefs.remove(_sessionIdKey);
    await prefs.remove(_sessionPlateKey);
    await prefs.remove(_sessionLoadKey);
    await prefs.remove(_sessionDriverKey);
  }

  Future<bool> hasActiveSession() async {
    if (!enabled) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sessionIdKey) != null;
  }

  Future<void> sendEvent({
    required String eventId,
    required String type,
    required String plate,
    required String driverId,
    required String loadId,
    double? latitude,
    double? longitude,
    Map<String, dynamic> payload = const <String, dynamic>{},
    DateTime? createdAt,
  }) async {
    if (!enabled) return;
    await _post('/api/v1/events', <String, dynamic>{
      'event_id': eventId,
      'type': type,
      'plate': plate,
      'driver_id': driverId,
      'load_id': loadId,
      'lat': latitude,
      'lon': longitude,
      'payload': payload,
      'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  Future<void> registerDevice({
    required String token,
    required String plate,
    required String userId,
  }) async {
    if (!enabled || token.trim().isEmpty) return;
    await _post('/api/v1/devices/register', <String, dynamic>{
      'platform': 'android',
      'token': token,
      'plate': plate,
      'user_id': userId,
    });
  }

  Future<File> _gpsQueueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/aims_flow_v12_gps_queue.jsonl');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  Future<T> _withIo<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _ioTail = _ioTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> enqueueGps({
    required String pointId,
    required String plate,
    required String driverId,
    required String loadId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
    required DateTime capturedAt,
  }) async {
    if (!enabled) return;
    final row = <String, dynamic>{
      'point_id': pointId,
      'plate': plate,
      'driver_id': driverId,
      'load_id': loadId,
      'lat': latitude,
      'lon': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'captured_at': capturedAt.toUtc().toIso8601String(),
    };
    await _withIo(() async {
      final file = await _gpsQueueFile();
      await file.writeAsString(
        '${jsonEncode(row)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    unawaited(flushGpsQueue());
  }

  Future<void> flushGpsQueue() async {
    if (!enabled || _flushingGps) return;
    if (!await hasActiveSession()) return;
    _flushingGps = true;
    try {
      final lines = await _withIo(() async {
        final file = await _gpsQueueFile();
        return (await file.readAsLines())
            .where((line) => line.trim().isNotEmpty)
            .take(50)
            .toList();
      });
      if (lines.isEmpty) return;

      var consumed = 0;
      for (final line in lines) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) {
            consumed++;
            continue;
          }
          await _post(
            '/api/v1/gps',
            Map<String, dynamic>.from(decoded),
          );
          consumed++;
        } catch (_) {
          break;
        }
      }

      if (consumed > 0) {
        await _withIo(() async {
          final file = await _gpsQueueFile();
          final all = (await file.readAsLines())
              .where((line) => line.trim().isNotEmpty)
              .toList();
          final remaining = all.skip(consumed).toList();
          await file.writeAsString(
            remaining.isEmpty ? '' : '${remaining.join('\n')}\n',
            flush: true,
          );
        });
      }
    } finally {
      _flushingGps = false;
    }
  }
}
