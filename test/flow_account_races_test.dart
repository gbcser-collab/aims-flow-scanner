import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/services/flow_account_service.dart';

FlowAccountSession driver(String id, String token) => FlowAccountSession(
  flowId: id, sessionToken: token * 64, expiresAt: DateTime.utc(2099),
  onboardingComplete: true, plate: 'ABC-123');

http.Response response(FlowAccountSession session, {String name = ''}) =>
  http.Response(jsonEncode({'ok': true, 'sessionToken': session.sessionToken,
    'sessionExpiresAt': session.expiresAt.toIso8601String(),
    'profile': {'flowId': session.flowId, 'plate': session.plate,
      'driverName': name, 'onboardingComplete': true}}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlowSessionStore store;
  final a = driver('123456', 'a');
  final b = driver('654321', 'b');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FlowSessionStore(preferencesOnly: true);
  });

  test('late validation cannot resurrect a logged-out session', () async {
    await store.save(a);
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    final api = FlowAccountService(store: store, client: MockClient((_) {
      entered.complete(); return gate.future;
    }));
    final pending = api.validateSession(a);
    final rejected = expectLater(pending, throwsA(isA<FlowSessionChanged>()));
    await entered.future;
    await store.clear();
    gate.complete(response(a));
    await rejected;
    expect(await store.load(), isNull);
  });

  test('logout clears locally before HTTP and cannot erase the next login', () async {
    await store.save(a);
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    final api = FlowAccountService(store: store, client: MockClient((_) {
      entered.complete(); return gate.future;
    }));
    final pending = api.logout(a);
    await entered.future;
    expect(await store.load(), isNull);
    await store.save(b);
    gate.complete(http.Response('{"ok":true}', 200));
    await pending;
    expect((await store.load())?.flowId, b.flowId);
  });

  test('stale and null logout requests preserve a different active account', () async {
    await store.save(b);
    final api = FlowAccountService(store: store,
      client: MockClient((_) async => http.Response('{"ok":true}', 200)));
    await api.logout(a);
    await api.logout(null);
    expect((await store.load())?.sessionToken, b.sessionToken);
  });

  test('late onboarding cannot overwrite a switched account', () async {
    await store.save(a);
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    final api = FlowAccountService(store: store, client: MockClient((_) {
      entered.complete(); return gate.future;
    }));
    final pending = api.completeOnboarding(session: a, driverName: 'A',
      odometerKm: 20, plate: 'ABC-123');
    final rejected = expectLater(pending, throwsA(isA<FlowSessionChanged>()));
    await entered.future;
    await store.save(b);
    gate.complete(response(a));
    await rejected;
    expect((await store.load())?.flowId, b.flowId);
  });

  test('old validation cannot revert a newer profile of the same session', () async {
    await store.save(a);
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    final api = FlowAccountService(store: store, client: MockClient((request) {
      if (jsonDecode(request.body)['action'] == 'validate') {
        entered.complete(); return gate.future;
      }
      return Future.value(response(a, name: 'Updated'));
    }));
    final pending = api.validateSession(a);
    final rejected = expectLater(pending, throwsA(isA<FlowSessionChanged>()));
    await entered.future;
    await api.completeOnboarding(session: a, driverName: 'Updated',
      odometerKm: 50, plate: 'ABC-123');
    gate.complete(response(a, name: 'Old'));
    await rejected;
    expect((await store.load())?.driverName, 'Updated');
  });

  test('two login responses keep the most recently started login', () async {
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    final api = FlowAccountService(store: store, loadDeviceId: () async => 'test-device',
      client: MockClient((request) {
        if (jsonDecode(request.body)['flowId'] == a.flowId) {
          entered.complete(); return gate.future;
        }
        return Future.value(response(b));
      }));
    final pending = api.login(flowId: a.flowId, pin: '1234');
    final rejected = expectLater(pending, throwsA(isA<FlowSessionChanged>()));
    await entered.future;
    await api.login(flowId: b.flowId, pin: '1234');
    gate.complete(response(a));
    await rejected;
    expect((await store.load())?.flowId, b.flowId);
  });

  test('secure write failure never falls back to plaintext token', () async {
    final secure = FlowSessionStore(preferencesOnly: false,
      writeSecure: (_) async => throw StateError('keystore unavailable'));
    await expectLater(secure.save(a), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('aims_flow_driver_session_v2'), isNull);
    expect(await secure.load(), isNull);
  });

  test('durable logout marker blocks an undeleted token after restart', () async {
    String? raw;
    final secure = FlowSessionStore(preferencesOnly: false,
      readSecure: () async => raw, writeSecure: (value) async { raw = value; },
      deleteSecure: () async => throw StateError('locked'));
    await secure.save(a);
    await secure.clear();
    expect(raw, isNotNull);
    final restarted = FlowSessionStore(preferencesOnly: false,
      readSecure: () async => raw, writeSecure: (value) async { raw = value; });
    expect(await restarted.load(), isNull);
    await restarted.save(b);
    expect((await restarted.load())?.flowId, b.flowId);
  });

  test('secure read error does not load the plaintext migration copy', () async {
    SharedPreferences.setMockInitialValues({
      'aims_flow_driver_session_v2': jsonEncode(a.toJson()),
    });
    final secure = FlowSessionStore(preferencesOnly: false,
      readSecure: () async => throw StateError('locked'));
    await expectLater(secure.load(), throwsStateError);
  });

  test('401 validation reports an expired session rather than a bad PIN', () async {
    await store.save(a);
    final api = FlowAccountService(store: store, client: MockClient((_) async =>
      http.Response('{"error":"invalid_session"}', 401)));
    await expectLater(api.validateSession(a), throwsA(isA<StateError>()
      .having((e) => e.message, 'message', contains('munkamenet lejárt'))));
  });
}
