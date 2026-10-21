import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aims_flow_scanner/services/flow_auth_service.dart';
import 'package:aims_flow_scanner/services/flow_http_client.dart';

class MemoryTokens implements FlowTokenStore {
  String? value;
  final writes = <String>[];
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
    writes.add(v);
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

Map<String, dynamic> response({String access = 'a', String refresh = 'b'}) => {
  'ok': true,
  'tokenType': 'Bearer',
  'accessToken': access * 64,
  'refreshToken': refresh * 64,
  'accessExpiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 15))
      .toIso8601String(),
  'refreshExpiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(days: 30))
      .toIso8601String(),
  'principal': {
    'role': 'driver',
    'subjectId': 'driver-a',
    'tenantId': 'tenant-a',
    'flowId': '004271',
    'displayName': 'Teszt Sofőr',
    'language': 'hu',
  },
  'assignment': {'assignmentId': 'assignment-a', 'plate': 'DEV9001'},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('strict credentials preserve leading zeros', () {
    expect(FlowAuthService.credentialsValid('004271', '03816'), isTrue);
    for (final pair in [
      ['4271', '03816'],
      ['004271', '3816'],
      ['004271', '038160'],
      ['004271', '１２３４５'],
      ['004271', 'abc12'],
      ['004271', '03816\n'],
    ]) {
      expect(FlowAuthService.credentialsValid(pair[0], pair[1]), isFalse);
    }
  });
  test('PIN and access token never enter persistent storage', () async {
    final store = MemoryTokens();
    final auth = FlowAuthService(
      store: store,
      deviceId: () async => 'd' * 64,
      client: MockClient((r) async {
        final data = jsonDecode(r.body) as Map;
        expect(data['flowId'], '004271');
        expect(data['pin'], '03816');
        expect(r.followRedirects, isFalse);
        return http.Response(
          jsonEncode(response()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final session = await auth.login('004271', '03816');
    expect(session.flowId, '004271');
    expect(store.writes.single.contains('03816'), isFalse);
    expect(store.writes.single.contains('a' * 64), isFalse);
    expect(store.writes.single.contains('b' * 64), isTrue);
    await auth.clear();
    expect(auth.authenticated, isFalse);
    expect(store.value, isNull);
  });
  test(
    'parallel refresh uses one request and atomically saves rotated token',
    () async {
      var refreshes = 0;
      final store = MemoryTokens();
      final auth = FlowAuthService(
        store: store,
        deviceId: () async => 'd' * 64,
        client: MockClient((r) async {
          if ((jsonDecode(r.body) as Map)['action'] == 'refresh') {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(
              jsonEncode(response(access: 'c', refresh: 'd')),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode(response()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await auth.login('004271', '03816');
      await Future.wait(List.generate(10, (_) => auth.refresh()));
      expect(refreshes, 1);
      expect(await auth.accessToken(), 'c' * 64);
      expect((jsonDecode(store.value!) as Map)['refreshToken'], 'd' * 64);
    },
  );
  test('revoked refresh clears secure storage and session', () async {
    final store = MemoryTokens();
    final auth = FlowAuthService(
      store: store,
      deviceId: () async => 'd' * 64,
      client: MockClient(
        (r) async => (jsonDecode(r.body) as Map)['action'] == 'login'
            ? http.Response(
                jsonEncode(response()),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response('{"ok":false,"error":"session_revoked"}', 401),
      ),
    );
    await auth.login('004271', '03816');
    await expectLater(auth.refresh(), throwsA(isA<FlowAuthException>()));
    expect(store.value, isNull);
    expect(auth.authenticated, isFalse);
  });
  test('missing secure token cannot restore from local profile', () async {
    var calls = 0;
    final auth = FlowAuthService(
      store: MemoryTokens(),
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 500);
      }),
    );
    expect(await auth.restore(), isFalse);
    expect(calls, 0);
  });
  test('late refresh cannot resurrect logged-out session', () async {
    final store = MemoryTokens();
    final auth = FlowAuthService(
      store: store,
      deviceId: () async => 'd' * 64,
      client: MockClient((r) async {
        if ((jsonDecode(r.body) as Map)['action'] == 'refresh') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode(response(access: 'c', refresh: 'd')),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode(response()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await auth.login('004271', '03816');
    final refreshing = auth.refresh();
    final assertion = expectLater(
      refreshing,
      throwsA(isA<FlowAuthException>()),
    );
    await auth.clear();
    await assertion;
    expect(auth.authenticated, isFalse);
    expect(store.value, isNull);
  });
  test(
    'transport blocks other origins, adds bearer, and never replays a mutation',
    () async {
      final auth = FlowAuthService(
        store: MemoryTokens(),
        deviceId: () async => 'd' * 64,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(response()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await auth.login('004271', '03816');
      var calls = 0;
      final client = FlowHttpClient(
        auth: auth,
        inner: MockClient((r) async {
          calls++;
          expect(r.headers['authorization'], 'Bearer ${'a' * 64}');
          expect(r.headers['x-flow-device'], 'd' * 64);
          expect((jsonDecode(r.body) as Map)['deviceId'], 'd' * 64);
          return http.Response('{"ok":false,"error":"session_revoked"}', 401);
        }),
      );
      await expectLater(
        client.get(
          Uri.parse('https://other.invalid/api/aims-tracking/driver_jobs.php'),
        ),
        throwsA(isA<FlowAuthException>()),
      );
      expect(calls, 0);
      final r = await client.post(
        Uri.parse('https://logistic-aims.hu/api/aims-tracking/ingest.php'),
        headers: {'Content-Type': 'application/json'},
        body: '{"deviceId":"old-metadata-id"}',
      );
      expect(r.statusCode, 401);
      expect(calls, 1);
      expect(auth.authenticated, isFalse);
    },
  );
}
