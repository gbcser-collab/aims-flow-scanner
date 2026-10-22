import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/models/scan_models.dart';
import 'package:aims_flow_scanner/services/aims_api_service.dart';
import 'package:aims_flow_scanner/services/device_identity_service.dart';
import 'package:aims_flow_scanner/services/scan_repository.dart';
import 'package:aims_flow_scanner/services/sync_coordinator.dart';

class TestIdentity extends DeviceIdentityService {
  @override
  Future<DeviceIdentity> loadOrCreate() async => const DeviceIdentity(deviceId: 'test', secret: 'test');
}
class TestApi extends AimsApiService {
  int requests = 0;
  int uploads = 0;
  Object? failure;
  Map<String, dynamic> response = {'state': 'uploaded', 'documentId': 'server-1'};
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<Map<String, dynamic>> enroll(DeviceIdentity identity, {required String label}) async {
    requests++; return {'state': 'approved'};
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
}
