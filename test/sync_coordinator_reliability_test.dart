import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/models/scan_models.dart';
import 'package:aims_flow_scanner/services/aims_api_service.dart';
import 'package:aims_flow_scanner/services/device_identity_service.dart';
import 'package:aims_flow_scanner/services/scan_repository.dart';
import 'package:aims_flow_scanner/services/sync_coordinator.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/smart_document_repository.dart';
import 'package:aims_flow_scanner/services/smart_document_service.dart';
import 'package:aims_flow_scanner/services/smart_document_classifier.dart';

class TestIdentity extends DeviceIdentityService {
  @override
  Future<DeviceIdentity> loadOrCreate() async => const DeviceIdentity(deviceId: 'test', secret: 'test');
}
class TestApi extends AimsApiService {
  int requests = 0;
  int uploads = 0;
  Object? failure;
  Completer<void>? enrollGate;
  Object? enrollFailure;
  Map<String, dynamic> response = {'state': 'uploaded', 'documentId': 'server-1'};
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<Map<String, dynamic>> enroll(DeviceIdentity identity, {required String label}) async {
    requests++;
    if (enrollGate != null) await enrollGate!.future;
    if (enrollFailure != null) throw enrollFailure!;
    return {'state': 'approved'};
  }
  @override
  Future<Map<String, dynamic>> deviceStatus(DeviceIdentity identity) async {
    requests++; return {'state': 'approved'};
  }
  @override
  Future<Map<String, dynamic>> syncCmr(DeviceIdentity identity, ScannedDocument document) async {
    requests++; uploads++;
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return response;
  }
}
class TestSmartService extends SmartDocumentService {
  final sent = <String>[];
  final entered = Completer<void>();
  @override
  Future<SmartDocumentUploadResult> send(PendingSmartDocument document) async {
    sent.add(document.id); if (!entered.isCompleted) entered.complete();
    return const SmartDocumentUploadResult(documentId: 'smart-server', state: 'uploaded');
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ScanRepository repository;
  late TestApi api;
  late SyncCoordinator sync;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('flow-sync-test-');
    repository = ScanRepository(directory: () async => root);
    api = TestApi();
    sync = SyncCoordinator(repository: repository, api: api, identityService: TestIdentity());
  });
  tearDown(() async { sync.dispose(); await root.delete(recursive: true); });
  ScannedDocument doc(String id) => ScannedDocument(id: id, createdAt: DateTime.utc(2026),
    imagePath: '${root.path}/$id.jpg', cmr: CmrData(),
    quality: const ScanQuality(brightness: 100, sharpness: 100, glareRatio: 0, documentFillRatio: 1));
  test('empty queues make no server requests', () async {
    await sync.syncNow(); await sync.syncNow();
    expect(api.requests, 0); expect(sync.pendingCount, 0); expect(sync.syncing, isFalse);
  });
  test('a network outage stops a whole backlog after the first upload and unlocks retry', () async {
    for (var i = 0; i < 12; i++) { await repository.update(doc('$i')); }
    api.failure = const SocketException('offline');
    await sync.syncNow();
    expect(api.uploads, 1); expect(sync.pendingCount, 12); expect(sync.syncing, isFalse);
    api.failure = null;
    await sync.syncNow();
    expect(api.uploads, 13);
    expect((await repository.loadAll()).every((d) => d.syncState == CmrSyncState.uploaded), isTrue);
  });
  test('server overload does not trigger an upload for every queued CMR', () async {
    await repository.update(doc('a')); await repository.update(doc('b'));
    api.failure = const AimsApiException('http_503', 503);
    await sync.syncNow(); expect(api.uploads, 1); expect(sync.pendingCount, 2);
  });
  test('an invalid acknowledgement cannot display uploaded or set a deletion deadline', () async {
    await repository.update(doc('a'));
    api.response = {'state': 'approved', 'deleteAfter': '2020-01-01T00:00:00Z'};
    await sync.syncNow();
    final retained = (await repository.loadAll()).single;
    expect(retained.syncState, CmrSyncState.failed);
    expect(retained.deleteAfter, isNull); expect(sync.pendingCount, 1);
  });
  test('late upload reply cannot resurrect a deleted document', () async {
    final original = doc('a'); await repository.update(original);
    api.gate = Completer<void>();
    final uploading = sync.syncNow(); await api.entered.future;
    await repository.delete(original); api.gate!.complete(); await uploading;
    expect(await repository.loadAll(), isEmpty); expect(sync.pendingCount, 0);
  });
  test('late upload reply cannot overwrite a document edited during upload', () async {
    final original = doc('a'); await repository.update(original);
    api.gate = Completer<void>();
    final uploading = sync.syncNow(); await api.entered.future;
    await repository.update(original.copyWith(cmr: const CmrData(cmrNumber: 'corrected')));
    api.gate!.complete(); await uploading;
    final retained = (await repository.loadAll()).single;
    expect(retained.cmr.cmrNumber, 'corrected'); expect(retained.syncState, CmrSyncState.pending);
  });
  test('overlapping sync calls never upload the same document twice concurrently', () async {
    await repository.update(doc('a')); api.gate = Completer<void>();
    final uploading = sync.syncNow(); await api.entered.future;
    await sync.syncNow(); expect(api.uploads, 1);
    api.gate!.complete(); await uploading; expect(sync.syncing, isFalse);
  });
  final owner = FlowAccountSession(flowId: '123456', sessionToken: 'a' * 64,
    expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: 'ABC123');
  PendingSmartDocument smart(String id, {String flowId = '123456', String plate = 'ABC123'}) =>
    PendingSmartDocument(id: id, flowId: flowId, plate: plate, type: SmartDocumentType.pod,
      imagePath: '${root.path}/$id.jpg', rawText: 'POD', confidence: 1, createdAt: DateTime.utc(2026));
  SyncCoordinator withSmart(TestSmartService service) => SyncCoordinator(repository: repository,
    api: api, identityService: TestIdentity(), smartService: service, loadSession: () async => owner);

  test('Smart-only queue does not contact the legacy device API', () async {
    final service = TestSmartService(); sync.dispose(); sync = withSmart(service);
    await const SmartDocumentRepository().update(smart('own'));
    api.enrollFailure = const AimsApiException('device_revoked', 403);
    await sync.syncNow();
    expect(api.requests, 0); expect(service.sent, ['own']); expect(sync.pendingCount, 0);
  });
  test('stalled legacy enrollment cannot delay an independent FLOW document', () async {
    final service = TestSmartService(); sync.dispose(); sync = withSmart(service);
    await repository.update(doc('cmr'));
    await const SmartDocumentRepository().update(smart('own'));
    api.enrollGate = Completer<void>();
    final pass = sync.syncNow();
    await service.entered.future.timeout(const Duration(seconds: 2));
    expect(api.enrollGate!.isCompleted, isFalse);
    api.enrollGate!.complete(); await pass;
    expect((await const SmartDocumentRepository().loadAll()).single.syncState, SmartDocumentSyncState.uploaded);
  });
  test('corrupt CMR index remains intact while Smart Document still uploads', () async {
    final service = TestSmartService(); sync.dispose(); sync = withSmart(service);
    await repository.update(doc('cmr'));
    final index = File('${root.path}/aims_scans/index.json'); await index.writeAsString('{broken');
    await const SmartDocumentRepository().update(smart('own'));
    await sync.syncNow();
    expect(service.sent, ['own']); expect(await index.readAsString(), '{broken');
    expect(sync.lastError, contains('CMR')); expect(sync.syncing, isFalse);
  });
  test('corrupt Smart index cannot block CMR upload or become an empty stored index', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_pending_smart_documents_v1', '{broken');
    await repository.update(doc('cmr')); await sync.syncNow();
    expect(api.uploads, 1); expect((await repository.loadAll()).single.syncState, CmrSyncState.uploaded);
    expect(prefs.getString('aims_pending_smart_documents_v1'), '{broken');
    expect(sync.lastError, contains('Smart Document'));
  });
  test('foreign, unassigned and blank-plate documents stay held without blocking own upload', () async {
    final service = TestSmartService(); sync.dispose(); sync = withSmart(service);
    const repo = SmartDocumentRepository();
    await repo.update(smart('old', flowId: ''));
    await repo.update(smart('foreign', flowId: '654321'));
    await repo.update(smart('blank', plate: ''));
    await repo.update(smart('own'));
    await sync.syncNow();
    expect(service.sent, ['own']); expect(sync.pendingCount, 3);
    final summary = await repo.queueSummary(owner);
    expect(summary.unidentified, 2); expect(summary.other, 1); expect(summary.pending, 0);
  });

}
