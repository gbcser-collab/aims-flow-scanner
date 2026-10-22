import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';
import 'package:aims_flow_scanner/services/smart_document_classifier.dart';
import 'package:aims_flow_scanner/services/smart_document_repository.dart';
import 'package:aims_flow_scanner/services/smart_document_service.dart';

class BodyStallClient extends http.BaseClient {
  final body = StreamController<List<int>>(); bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(body.stream, 200);
  @override
  void close() { closed = true; unawaited(body.close()); }
}
void main() {
  late Directory root; late File image;
  final owner = FlowAccountSession(flowId: '123456', sessionToken: 'a' * 64,
    expiresAt: DateTime.utc(2099), onboardingComplete: true, plate: 'ABC123');
  setUp(() async { root = await Directory.systemTemp.createTemp('flow-smart-');
    image = File('${root.path}/image.jpg'); await image.writeAsBytes(List.filled(2048, 1)); });
  tearDown(() async => root.delete(recursive: true));
  PendingSmartDocument doc({String flowId = '123456', String plate = 'ABC-123'}) => PendingSmartDocument(
    id: 'stable-id', type: SmartDocumentType.pod, imagePath: image.path, rawText: 'POD',
    confidence: 1, createdAt: DateTime.utc(2026), plate: plate, flowId: flowId);
  Matcher code(String value) => isA<SmartDocumentUploadException>().having((e) => e.code, 'code', value);

  test('unknown owner, another driver on same plate, and another plate send no request', () async {
    var calls = 0;
    final service = SmartDocumentService(loadSession: () async => owner,
      clientFactory: () => MockClient((_) async { calls++; return http.Response('{}', 200); }));
    await expectLater(service.send(doc(flowId: '')), throwsA(code('owner_unidentified')));
    await expectLater(service.send(doc(flowId: '654321')), throwsA(code('owner_mismatch')));
    await expectLater(service.send(doc(plate: 'XYZ987')), throwsA(code('owner_mismatch')));
    expect(calls, 0);
  });
  test('session change while preparing the image prevents transmission with new credentials', () async {
    var reads = 0; var calls = 0;
    final service = SmartDocumentService(loadSession: () async => ++reads == 1 ? owner : owner.copyWith(sessionToken: 'b' * 64),
      clientFactory: () => MockClient((_) async { calls++; return http.Response('{}', 200); }));
    await expectLater(service.send(doc()), throwsA(code('session_changed'))); expect(calls, 0);
  });
  test('logout before acknowledgement leaves the original document retryable locally', () async {
    FlowAccountSession? current = owner;
    final service = SmartDocumentService(loadSession: () async => current, clientFactory: () => MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer ${owner.sessionToken}');
      current = null; return http.Response('{"ok":true,"documentId":"1","state":"uploaded"}', 200);
    }));
    await expectLater(service.send(doc()), throwsA(code('invalid_session')));
  });
  test('HTTP 503 has one attempt per queue cycle and reports retryable failure', () async {
    var calls = 0;
    final service = SmartDocumentService(loadSession: () async => owner, clientFactory: () => MockClient((_) async {
      calls++; return http.Response('Unavailable', 503);
    }));
    await expectLater(service.send(doc()), throwsA(isA<SmartDocumentUploadException>().having((e) => e.retryable, 'retryable', true)));
    expect(calls, 1);
  });
  test('incomplete or unrelated success cannot acknowledge the document', () async {
    for (final body in ['<html>Login</html>', '{"ok":true}',
      '{"ok":true,"documentId":"1","state":"uploaded","localId":"other"}',
      '{"ok":true,"documentId":false,"state":"uploaded"}']) {
      final service = SmartDocumentService(loadSession: () async => owner,
        clientFactory: () => MockClient((_) async => http.Response(body, 200)));
      await expectLater(service.send(doc()), throwsA(isA<SmartDocumentUploadException>()));
    }
  });
  test('successful send preserves original owner and idempotency key', () async {
    final service = SmartDocumentService(loadSession: () async => owner, clientFactory: () => MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['flowId'], owner.flowId); expect(body['localId'], 'stable-id');
      expect(request.headers['X-AIMS-Idempotency-Key'], 'stable-id');
      return http.Response('{"ok":true,"documentId":"7","state":"uploaded"}', 200);
    }));
    expect((await service.send(doc())).documentId, '7');
  });
  test('stalled response body closes its HTTP client at the deadline', () async {
    final client = BodyStallClient();
    final service = SmartDocumentService(loadSession: () async => owner, clientFactory: () => client,
      requestTimeout: const Duration(milliseconds: 20));
    await expectLater(service.send(doc()), throwsA(code('upload_timeout'))); expect(client.closed, isTrue);
  });
  test('oversized image is rejected before network or base64 allocation', () async {
    final handle = await image.open(mode: FileMode.write); await handle.truncate(12 * 1024 * 1024 + 1); await handle.close();
    var calls = 0;
    final service = SmartDocumentService(loadSession: () async => owner,
      clientFactory: () { calls++; throw StateError('must not allocate client'); });
    await expectLater(service.send(doc()), throwsA(code('invalid_image_size'))); expect(calls, 0);
  });
}
