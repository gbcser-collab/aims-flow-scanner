import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aims_flow_scanner/models/scan_models.dart';
import 'package:aims_flow_scanner/services/aims_api_service.dart';
import 'package:aims_flow_scanner/services/device_identity_service.dart';

class StalledClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(body.stream, 200);
  @override
  void close() { closed = true; unawaited(body.close()); }
}

void main() {
  late Directory root;
  late ScannedDocument document;
  const identity = DeviceIdentity(deviceId: 'device', secret: 'secret');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flow-api-test-');
    final file = File('${root.path}/image.jpg');
    await file.writeAsBytes([1, 2, 3]);
    document = ScannedDocument(id: 'local-1', createdAt: DateTime.utc(2026), imagePath: file.path,
      cmr: CmrData(), quality: const ScanQuality(brightness: 100, sharpness: 100, glareRatio: 0, documentFillRatio: 1));
  });
  tearDown(() async => root.delete(recursive: true));
  AimsApiService api(String body, [int status = 200]) => AimsApiService(
    clientFactory: () => MockClient((_) async => http.Response(body, status)));

  test('HTML, empty, scalar and incomplete success bodies never acknowledge a CMR', () async {
    for (final body in ['', '<html>Login</html>', '[]', 'true', '{}', '{"ok":true}',
      '{"state":"approved"}', '{"state":"invented","documentId":"1"}',
      '{"state":"approved","documentId":""}',
      '{"state":"approved","documentId":"1","localId":"another"}',
      '{"ok":false,"state":"approved","documentId":"1"}']) {
      await expectLater(api(body).syncCmr(identity, document), throwsA(isA<AimsApiException>()), reason: body);
    }
  });
  test('valid acknowledgement preserves the local identity and accepted state', () async {
    for (final idKey in ['documentId', 'serverDocumentId']) {
      final response = await api(jsonEncode({'state': 'uploaded', idKey: 'server-1', 'localId': document.id}))
        .syncCmr(identity, document);
      expect(response[idKey], 'server-1');
    }
  });
  test('application rejection inside HTTP 200 is not successful enrollment', () async {
    await expectLater(api('{"ok":false,"error":"device_revoked"}').enroll(identity, label: 'test'),
      throwsA(isA<AimsApiException>().having((e) => e.code, 'code', 'device_revoked')));
    await expectLater(api('{"ok":true}').deviceStatus(identity), throwsA(isA<AimsApiException>()));
  });
  test('non-JSON server outage retains HTTP retry classification', () async {
    await expectLater(api('<html>Unavailable</html>', 503).syncCmr(identity, document),
      throwsA(isA<AimsApiException>().having((e) => e.retryable, 'retryable', true)
        .having((e) => e.statusCode, 'status', 503)));
  });
  test('CMR response-body timeout closes the request transport', () async {
    final client = StalledClient();
    await expectLater(AimsApiService(clientFactory: () => client,
      requestTimeout: const Duration(milliseconds: 20)).syncCmr(identity, document),
      throwsA(isA<TimeoutException>()));
    expect(client.closed, isTrue);
  });
}
