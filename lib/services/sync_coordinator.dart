import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/scan_models.dart';
import 'aims_api_service.dart';
import 'device_identity_service.dart';
import 'flow_account_service.dart';
import 'flow_local_journal.dart';
import 'scan_repository.dart';
import 'smart_document_repository.dart';
import 'smart_document_service.dart';

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({ScanRepository repository = const ScanRepository(),
    SmartDocumentRepository smartRepository = const SmartDocumentRepository(),
    SmartDocumentService smartService = const SmartDocumentService(),
    DeviceIdentityService identityService = const DeviceIdentityService(),
    AimsApiService api = const AimsApiService(),
    Future<FlowAccountSession?> Function()? loadSession,
  }) : _repository = repository, _smartRepository = smartRepository,
       _smartService = smartService, _identityService = identityService, _api = api,
       _loadSession = loadSession ?? FlowSessionStore.instance.load;

  static final SyncCoordinator instance = SyncCoordinator();
  final ScanRepository _repository;
  final SmartDocumentRepository _smartRepository;
  final SmartDocumentService _smartService;
  final DeviceIdentityService _identityService;
  final AimsApiService _api;
  final Future<FlowAccountSession?> Function() _loadSession;

  Timer? _timer;
  bool _initialized = false;
  bool _syncing = false;
  String _deviceState = 'unknown';
  int _cmrPendingCount = 0;
  int _smartPendingCount = 0;
  String? _lastError;
  DateTime? _lastSyncAt;

  bool get syncing => _syncing;
  String get deviceState => _deviceState;
  int get pendingCount => _cmrPendingCount + _smartPendingCount;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(syncNow()));
    // Keep the retry timer alive even if a local index cannot be read initially.
    await syncNow();
  }

  Future<void> refreshPendingCount() async {
    Object? failure;
    await Future.wait([
      () async {
        try { _cmrPendingCount = (await _repository.pendingForSync()).length; }
        catch (error) { failure ??= error; }
      }(),
      () async {
        try { _smartPendingCount = (await _smartRepository.pendingForSync()).length; }
        catch (error) { failure ??= error; }
      }(),
    ]);
    notifyListeners();
    if (failure != null) throw failure!;
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      // The legacy CMR device credential and FLOW session are independent.
      // Neither channel may block the other's queue or authentication.
      final errors = await Future.wait([_syncCmr(), _syncSmart()]);
      final messages = errors.whereType<String>().toList();
      _lastError = messages.isEmpty ? null : messages.join(' • ');
    } finally {
      try { await refreshPendingCount(); }
      catch (_) { _lastError ??= 'A helyi dokumentumsor nem olvasható. Az adatokat megőriztük.'; }
      _syncing = false;
      notifyListeners();
    }
  }

  Future<String?> _syncCmr() async {
    String? error;
    try {
      await _repository.pruneExpiredApproved();
      final pending = await _repository.pendingForSync();
      if (pending.isEmpty) return null;
      final identity = await _identityService.loadOrCreate();
      final enroll = await _api.enroll(identity, label: 'AIMS Flow Smart Scanner');
      _deviceState = enroll['state'] as String? ?? 'unknown';
      final status = await _api.deviceStatus(identity);
      _deviceState = status['state'] as String? ?? 'unknown';
      if (_deviceState != 'approved') {
        return _deviceState == 'revoked'
          ? 'A CMR-készülék hozzáférését az admin visszavonta.'
          : 'A CMR-készülék admin jóváhagyásra vár.';
      }
      for (final document in pending) {
        try {
          final response = await _api.syncCmr(identity, document);
          await _repository.updateIfUnchanged(document, _applyServerState(document, response));
          _lastSyncAt = DateTime.now();
        } on AimsApiException catch (e) {
          if (e.code == 'device_pending' || e.code == 'device_revoked') {
            _deviceState = e.code == 'device_pending' ? 'pending' : 'revoked';
            return 'CMR hozzáférési hiba: ${e.code}';
          }
          await _repository.updateIfUnchanged(document, document.copyWith(
            syncState: CmrSyncState.failed, lastSyncError: e.code));
          error = 'CMR szinkronhiba: ${e.code}';
          if (e.retryable || e.statusCode == 401 || e.statusCode == 403) return error;
        } catch (e) {
          await _repository.updateIfUnchanged(document, document.copyWith(
            syncState: CmrSyncState.failed, lastSyncError: e.toString()));
          if (e is FileSystemException) {
            error = 'A CMR helyi fájlja nem olvasható. A bejegyzés megmaradt.';
          } else {
            return 'Nincs kapcsolat. A CMR offline sorban marad.';
          }
        }
      }
      await _repository.pruneExpiredApproved();
    } on AimsApiException catch (e) {
      if (e.code == 'device_pending') _deviceState = 'pending';
      if (e.code == 'device_revoked') _deviceState = 'revoked';
      return 'CMR szinkron várakozik: ${e.code}';
    } on FileSystemException {
      return 'A CMR helyi naplója nem olvasható. Az eredeti adat megmaradt.';
    } catch (_) {
      return 'A CMR-kapcsolat nem elérhető. A dokumentumok megmaradtak.';
    }
    return error;
  }

  Future<String?> _syncSmart() async {
    String? error;
    try {
      final pending = await _smartRepository.pendingForSync();
      if (pending.isEmpty) return null;
      final session = await _loadSession();
      if (session == null || session.isExpired) return 'A Smart Document küldéshez lépj be a FLOW-fiókba.';
      for (final document in pending) {
        if (!RegExp(r'^\d{6}$').hasMatch(document.flowId) || flowJournalPlate(document.plate).isEmpty) {
          error ??= 'Régi Smart Document azonosításra vár. A helyi példány megmaradt.';
          continue;
        }
        if (document.flowId != session.flowId || flowJournalPlate(document.plate) != flowJournalPlate(session.plate)) continue;
        try {
          final result = await _smartService.send(document);
          await _smartRepository.updateIfUnchanged(document, document.copyWith(
            syncState: SmartDocumentSyncState.uploaded, serverDocumentId: result.documentId,
            uploadedAt: DateTime.now().toUtc(), clearLastError: true));
          _lastSyncAt = DateTime.now();
        } on SmartDocumentUploadException catch (e) {
          await _smartRepository.updateIfUnchanged(document, document.copyWith(
            syncState: SmartDocumentSyncState.failed, lastError: e.code));
          error = 'Smart Document szinkron várakozik: ${e.code}';
          if (e.retryable || e.code == 'invalid_session' || e.code == 'session_changed' ||
              e.code == 'owner_mismatch' || e.statusCode == 401 || e.statusCode == 403) return error;
        } catch (_) {
          return 'A Smart Document küldése nem sikerült. A helyi példány megmaradt.';
        }
      }
    } on FileSystemException {
      return 'A Smart Document helyi naplója nem olvasható. Az eredeti adat megmaradt.';
    } catch (_) {
      return 'A Smart Document állapota nem olvasható. Később újrapróbáljuk.';
    }
    return error;
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

  void _stopAutoSync() {
    _timer?.cancel();
    _timer = null;
    _initialized = false;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stopAutoSync();
  }

  @override
  void dispose() {
    _stopAutoSync();
    super.dispose();
  }
}

