import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aims_flow_scanner/services/flow_multipart_transport.dart';

class ControlledClient extends http.BaseClient {
  ControlledClient(this.respond);
  final Future<http.StreamedResponse> Function() respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => respond();
  @override
  void close() { closed = true; }
}

http.Request request() => http.Request('POST', Uri.parse('https://example.test/upload'));

void main() {
  test('response-body stall has a deadline even after headers arrived', () async {
    final body = StreamController<List<int>>();
    final client = ControlledClient(() async => http.StreamedResponse(body.stream, 200));
    await expectLater(sendFlowMultipart(request(), client: client,
      timeout: const Duration(milliseconds: 20)), throwsA(isA<TimeoutException>()));
    expect(client.closed, isTrue);
    await body.close();
  });

  test('upload/header stall also expires and closes its client', () async {
    final stalled = Completer<http.StreamedResponse>();
    final client = ControlledClient(() => stalled.future);
    await expectLater(sendFlowMultipart(request(), client: client,
      timeout: const Duration(milliseconds: 20)), throwsA(isA<TimeoutException>()));
    expect(client.closed, isTrue);
    stalled.complete(http.StreamedResponse(const Stream<List<int>>.empty(), 200));
  });

  test('complete response is preserved and transport resources are closed', () async {
    final client = ControlledClient(() async => http.StreamedResponse(
      Stream<List<int>>.value('{"ok":true}'.codeUnits), 200));
    final response = await sendFlowMultipart(request(), client: client);
    expect(response.statusCode, 200);
    expect(response.body, '{"ok":true}');
    expect(client.closed, isTrue);
  });

  test('transport failures also close the connection', () async {
    final client = ControlledClient(() async { throw http.ClientException('offline'); });
    await expectLater(sendFlowMultipart(request(), client: client), throwsA(isA<http.ClientException>()));
    expect(client.closed, isTrue);
  });
}
