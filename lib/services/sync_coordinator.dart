import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/scan_models.dart';
import 'aims_api_service.dart';
import 'device_identity_service.dart';
import 'scan_repository.dart';
import 'smart_document_repository.dart';
import 'smart_document_service.dart';

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({ScanRepository repository = const ScanRepository(),
    SmartDocumentRepository smartRepository = const SmartDocumentRepository(),
    SmartDocumentService smartService = const SmartDocumentService(),
    DeviceIdentityService identityService = const DeviceIdentityService(),
    AimsApiService api = const AimsApiService(),
  }) : _repository = repository, _smartRepository = smartRepository,
       _smartService = smartService, _identityService = identityService, _api = api;

  static final SyncCoordinator instance = SyncCoordinator();
  final ScanRepository _repository;
  final SmartDocumentRepository _smartRepository;
  final SmartDocumentService _smartService;
  final DeviceIdentityService _identityService;
  final AimsApiService _api;

  Timer? _timer;
  bool _initialized = false;
  bool _syncing = false;
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
    try {
      await _repository.pruneExpiredApproved();
      await refreshPendingCount();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => unawaited(syncNow()),
      );
      unawaited(syncNow());
    } catch (_) {
      // Allow a later retry instead of getting stuck in a half-initialized state.
      _initialized = false;
      rethrow;
    }
  }

  Future<void> refreshPendingCount() async {
    final cmrPending = await _repository.pendingForSync();
    final smartPending = await _smartRepository.pendingForSync();
    _pendingCount = cmrPending.length + smartPending.length;
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final pending = await _repository.pendingForSync();
      final smartPending = await _smartRepository.pendingForSync();
      // An empty queue needs no enrollment/status round-trip or mobile radio wakeup.
      if (pending.isEmpty && smartPending.isEmpty) return;
      final identity = await _identityService.loadOrCreate();
      final enroll = await _api.enroll(identity, label: 'AIMS Flow Smart Scanner');
      _deviceState = enroll['state'] as String? ?? _deviceState;

      final status = await _api.deviceStatus(identity);
      _deviceState = status['state'] as String? ?? _deviceState;
      if (_deviceState != 'approved') {
        _lastError = _deviceState == 'revoked'
            ? 'A készülék hozzáférését az admin visszavonta.'
            : 'A készülék admin jóváhagyásra vár.';
        return;
      }

      for (final document in pending) {
        try {
          final response = await _api.syncCmr(identity, document);
          final updated = _applyServerState(document, response);
          await _repository.updateIfUnchanged(document, updated);
        } on AimsApiException catch (e) {
          if (e.code == 'device_pending') {
            _deviceState = 'pending';
            _lastError = 'A készülék admin jóváhagyásra vár.';
            return;
          }
          if (e.code == 'device_revoked') {
            _deviceState = 'revoked';
            _lastError = 'A készülék hozzáférését az admin visszavonta.';
            return;
          }
          await _repository.updateIfUnchanged(document, document.copyWith(
            syncState: CmrSyncState.failed,
            lastSyncError: e.code,
          ));
          _lastError = 'CMR szinkronhiba: ${e.code}';
          if (e.retryable || e.statusCode == 401 || e.statusCode == 403) return;
        } catch (e) {
          await _repository.updateIfUnchanged(document, document.copyWith(
            syncState: CmrSyncState.failed,
            lastSyncError: e.toString(),
          ));
          if (e is FileSystemException) {
            _lastError = 'A dokumentum helyi fájlja nem olvasható. A bejegyzés megmaradt.';
          } else {
            _lastError = 'Nincs kapcsolat. A dokumentum offline sorban marad.';
            return;
          }
        }
      }
      for (final document in smartPending) {
        try {
          final result = await _smartService.send(document);
          await _smartRepository.updateIfUnchanged(document,
            document.copyWith(
              syncState: SmartDocumentSyncState.uploaded,
              serverDocumentId: result.documentId,
              uploadedAt: DateTime.now().toUtc(),
              clearLastError: true,
            ),
          );
        } on SmartDocumentUploadException catch (e) {
          await _smartRepository.updateIfUnchanged(document,
            document.copyWith(
              syncState: SmartDocumentSyncState.failed,
              lastError: e.code,
            ),
          );
          _lastError = e.retryable
              ? 'Nincs stabil kapcsolat. A Smart Document offline sorban marad.'
              : 'Smart Document hiba: ${e.code}';
          if (e.retryable) {
            // Do not hammer the same broken mobile connection with every
            // queued document. The next sync cycle will retry safely.
            break;
          }
        } catch (e) {
          await _smartRepository.updateIfUnchanged(document,
            document.copyWith(
              syncState: SmartDocumentSyncState.failed,
              lastError: e.toString(),
            ),
          );
          _lastError =
              'Smart Document szinkron várakozik. A fájl biztonságosan a telefonon marad.';
          break;
        }
      }

      _lastSyncAt = DateTime.now();
      await _repository.pruneExpiredApproved();
    } on AimsApiException catch (e) {
      if (e.code == 'device_pending') _deviceState = 'pending';
      if (e.code == 'device_revoked') _deviceState = 'revoked';
      _lastError = 'Szinkron várakozik: ${e.code}';
    } catch (_) {
      _lastError = 'Nincs hálózati kapcsolat. Az adatok biztonságosan offline maradnak.';
    } finally {
      try {
        final cmrPending = await _repository.pendingForSync();
        final smartPending = await _smartRepository.pendingForSync();
        _pendingCount = cmrPending.length + smartPending.length;
      } catch (_) {
        // Pending-count refresh is informational only. Never leave sync locked.
      }
      _syncing = false;
      notifyListeners();
    }
  }

  ScannedDocument _applyServerState(ScannedDocument document, Map<String, dynamic> response) {
    DateTime? parseDate(dynamic value) => value is String ? DateTime.tryParse(value) : null;

    AimsApiService.validateCmrAcknowledgement(response, document.id);
    final stateText = response['state'] as String;
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
      lastSyncError: state == CmrSyncState.failed ? 'server_document_failed' : null,
      clearLastSyncError: state != CmrSyncState.failed,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

