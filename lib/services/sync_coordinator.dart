import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/scan_models.dart';
import 'aims_api_service.dart';
import 'device_identity_service.dart';
import 'scan_repository.dart';

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator._();

  static final SyncCoordinator instance = SyncCoordinator._();

  final ScanRepository _repository = const ScanRepository();
  final DeviceIdentityService _identityService = const DeviceIdentityService();
  final AimsApiService _api = const AimsApiService();

  Timer? _timer;
  bool _initialized = false;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _enrolled = false;
  int _failureCount = 0;
  DateTime? _nextAutomaticAttemptAt;
  String _deviceState = 'unknown';
  int _pendingCount = 0;
  String? _lastError;
  DateTime? _lastSyncAt;

  bool get syncing => _syncing;
  String get deviceState => _deviceState;
  int get pendingCount => _pendingCount;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _repository.pruneExpiredApproved();
    await refreshPendingCount();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(_sync(force: false)));
    unawaited(syncNow());
  }

  Future<void> refreshPendingCount() async {
    final pending = await _repository.pendingForSync();
    _pendingCount = pending.length;
    notifyListeners();
  }

  /// Explicit user/lifecycle syncs bypass retry backoff. Automatic timer calls
  /// use [_sync] directly and back off after repeated network failures.
  Future<void> syncNow() => _sync(force: true);

  Future<void> _sync({required bool force}) async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }

    final next = _nextAutomaticAttemptAt;
    if (!force && next != null && DateTime.now().isBefore(next)) return;

    _syncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final identity = await _identityService.loadOrCreate();
      if (!_enrolled) {
        final enroll = await _api.enroll(identity, label: 'AIMS Flow Smart Scanner');
        _deviceState = enroll['state'] as String? ?? _deviceState;
        _enrolled = true;
      }

      final status = await _api.deviceStatus(identity);
      _deviceState = status['state'] as String? ?? _deviceState;
      if (_deviceState != 'approved') {
        _lastError = _deviceState == 'revoked'
            ? 'A készülék hozzáférését az admin visszavonta.'
            : 'A készülék admin jóváhagyásra vár.';
        _failureCount = 0;
        _nextAutomaticAttemptAt = DateTime.now().add(const Duration(minutes: 2));
        return;
      }

      final pending = await _repository.pendingForSync();
      for (final document in pending) {
        try {
          final response = await _api.syncCmr(identity, document);
          final updated = _applyServerState(document, response);
          await _repository.update(updated);
        } on AimsApiException catch (e) {
          if (e.statusCode == 401 || e.statusCode == 404) _enrolled = false;
          if (e.code == 'device_pending') {
            _deviceState = 'pending';
            _lastError = 'A készülék admin jóváhagyásra vár.';
            break;
          }
          if (e.code == 'device_revoked') {
            _deviceState = 'revoked';
            _lastError = 'A készülék hozzáférését az admin visszavonta.';
            break;
          }
          await _repository.update(document.copyWith(
            syncState: CmrSyncState.failed,
            lastSyncError: e.code,
          ));
          _lastError = 'CMR szinkronhiba: ${e.code}';
        } catch (e) {
          await _repository.update(document.copyWith(
            syncState: CmrSyncState.failed,
            lastSyncError: e.toString(),
          ));
          _lastError = 'Nincs kapcsolat. A dokumentum offline sorban marad.';
        }
      }

      _lastSyncAt = DateTime.now();
      await _repository.pruneExpiredApproved();
      if (_lastError == null) {
        _failureCount = 0;
        _nextAutomaticAttemptAt = null;
      } else {
        _scheduleBackoff();
      }
    } on AimsApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) _enrolled = false;
      if (e.code == 'device_pending') _deviceState = 'pending';
      if (e.code == 'device_revoked') _deviceState = 'revoked';
      _lastError = 'Szinkron várakozik: ${e.code}';
      _scheduleBackoff();
    } catch (_) {
      _lastError = 'Nincs hálózati kapcsolat. Az adatok biztonságosan offline maradnak.';
      _scheduleBackoff();
    } finally {
      final pending = await _repository.pendingForSync();
      _pendingCount = pending.length;
      _syncing = false;
      notifyListeners();

      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_sync(force: true));
      }
    }
  }

  void _scheduleBackoff() {
    _failureCount = min(_failureCount + 1, 6);
    const delays = <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
    ];
    _nextAutomaticAttemptAt = DateTime.now().add(delays[_failureCount - 1]);
  }

  ScannedDocument _applyServerState(ScannedDocument document, Map<String, dynamic> response) {
    DateTime? parseDate(dynamic value) => value is String ? DateTime.tryParse(value) : null;

    final stateText = response['state'] as String? ?? 'uploaded';
    final state = switch (stateText) {
      'approved' => CmrSyncState.approved,
      'emailed' => CmrSyncState.emailed,
      'failed' => CmrSyncState.failed,
      _ => CmrSyncState.uploaded,
    };

    return document.copyWith(
      syncState: state,
      serverDocumentId: response['documentId']?.toString() ?? response['serverDocumentId']?.toString(),
      uploadedAt: parseDate(response['uploadedAt']) ?? (state != CmrSyncState.pending ? DateTime.now() : null),
      emailedAt: parseDate(response['emailedAt']),
      approvedAt: parseDate(response['approvedAt']),
      deleteAfter: parseDate(response['deleteAfter']),
      clearLastSyncError: true,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
