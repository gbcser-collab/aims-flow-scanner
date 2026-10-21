import 'dart:convert';

import 'package:http/http.dart' as http;

import 'flow_auth_service.dart';

/// One transport for JSON and multipart driver calls. No embedded fleet-wide key.
class FlowHttpClient extends http.BaseClient {
  FlowHttpClient({http.Client? inner, FlowAuthService? auth})
    : _inner = inner ?? http.Client(),
      _auth = auth ?? FlowAuthService.instance;
  static final instance = FlowHttpClient();
  final http.Client _inner;
  final FlowAuthService _auth;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.scheme != 'https' ||
        request.url.origin != _auth.endpoint.origin ||
        !request.url.path.startsWith('/api/aims-tracking/')) {
      throw const FlowAuthException('permission_denied', 403);
    }
    final token = await _auth.accessToken();
    final session = _auth.session!;
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-Flow-Device'] = session.deviceId;
    if (request is http.Request &&
        request.body.isNotEmpty &&
        (request.headers['content-type'] ?? '').contains('application/json')) {
      final data = jsonDecode(request.body);
      if (data is Map && data.containsKey('deviceId')) {
        data['deviceId'] = session.deviceId;
        request.body = jsonEncode(data);
      }
    }
    final response = await _inner.send(request);
    // Never replay mutations implicitly. The existing idempotent offline queues retry later.
    if (response.statusCode == 401) await _auth.rejectAccessToken(token);
    return response;
  }

  @override
  void close() => _inner.close();
}
