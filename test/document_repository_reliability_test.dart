import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/models/scan_models.dart';
import 'package:aims_flow_scanner/services/scan_repository.dart';
import 'package:aims_flow_scanner/services/smart_document_repository.dart';
import 'package:aims_flow_scanner/services/smart_document_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ScanRepository scans;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('flow-doc-test-');
    scans = ScanRepository(directory: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));
  ScannedDocument scan(String id) => ScannedDocument(id: id, createdAt: DateTime.utc(2026),
    imagePath: '${root.path}/$id.jpg', cmr: CmrData(),
    quality: const ScanQuality(brightness: 100, sharpness: 100, glareRatio: 0, documentFillRatio: 1));
  PendingSmartDocument smart(String id) => PendingSmartDocument(id: id,
    type: SmartDocumentType.values.first, imagePath: '${root.path}/$id.jpg',
    rawText: 'CMR', confidence: 1, createdAt: DateTime.utc(2026), plate: 'ABC123');

  test('concurrent CMR writes across instances retain every document, including missing images', () async {
    final second = ScanRepository(directory: () async => root);
    await Future.wait(List.generate(20, (i) => (i.isEven ? scans : second).update(scan('$i'))));
    expect((await scans.loadAll()).length, 20);
    expect((await scans.pendingForSync()).length, 20);
  });
  test('failed CMR replacement preserves previous index byte for byte', () async {
    await scans.update(scan('old'));
    final file = File('${root.path}/aims_scans/index.json');
    final original = await file.readAsString();
    final failing = ScanRepository(directory: () async => root,
      beforeReplace: (_) async => throw const FileSystemException('disk full'));
    await expectLater(failing.update(scan('new')), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), original);
    expect((await scans.loadAll()).single.id, 'old');
  });
  test('corrupt CMR index cannot be overwritten by a new sync result', () async {
    await scans.update(scan('old'));
    final file = File('${root.path}/aims_scans/index.json');
    await file.writeAsString('{broken');
    await expectLater(scans.update(scan('new')), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), '{broken');
  });
  test('CMR cleanup cannot delete an image before its index transaction commits', () async {
    final doc = scan('approved').copyWith(syncState: CmrSyncState.approved, deleteAfter: DateTime.utc(2020));
    await File(doc.imagePath).writeAsString('original');
    await scans.update(doc);
    final failing = ScanRepository(directory: () async => root,
      beforeReplace: (_) async => throw const FileSystemException('disk full'));
    await expectLater(failing.pruneExpiredApproved(), throwsA(isA<FileSystemException>()));
    expect(await File(doc.imagePath).exists(), isTrue);
    expect((await scans.loadAll()).single.id, doc.id);
  });
  test('parallel smart document updates keep all pending records, even without images', () async {
    const repo = SmartDocumentRepository();
    await Future.wait(List.generate(20, (i) => repo.update(smart('$i'))));
    expect((await repo.pendingForSync()).length, 20);
  });
  test('smart index corruption uses backup and preserves damaged source', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_pending_smart_documents_v1', '{broken');
    await prefs.setString('aims_pending_smart_documents_v1_backup', jsonEncode([smart('backup').toJson()]));
    expect((await const SmartDocumentRepository().loadAll()).single.id, 'backup');
    expect(prefs.getString('aims_pending_smart_documents_v1_damaged'), '{broken');
  });
  test('missing backup never makes a corrupt smart index look like an empty queue', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aims_pending_smart_documents_v1', '{broken');
    await expectLater(const SmartDocumentRepository().update(smart('new')), throwsA(isA<FileSystemException>()));
    expect(prefs.getString('aims_pending_smart_documents_v1'), '{broken');
  });
}
