import 'package:http/http.dart' as http;

/// Own the client for this request so an upload or response-body stall can be
/// cancelled. The deadline covers both the upload and the complete response.
Future<http.Response> sendFlowMultipart(
  http.BaseRequest request, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final transport = client ?? http.Client();
  try {
    return await (() async {
      final streamed = await transport.send(request);
      return http.Response.fromStream(streamed);
    })().timeout(timeout);
  } finally {
    transport.close();
  }
}
