import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('flow-device-test-');
  });
  tearDown(() async => root.delete(recursive: true));

  test('parallel login and tracking initialization use one durable identity', () async {
    final identities = await Future.wait(List.generate(30, (_) =>
      DeviceIdentityService(supportDirectory: () async => root).loadOrCreate()));
    expect(identities.map((item) => item.deviceId).toSet().length, 1);
    expect(identities.map((item) => item.secret).toSet().length, 1);
    final stored = jsonDecode(await File('${root.path}/aims_flow_private/device_identity.json').readAsString());
    expect(stored['deviceId'], identities.first.deviceId);
    expect((await SharedPreferences.getInstance()).getString('aims_tracking_device_id'), identities.first.deviceId);
  });

  test('corrupt identity is preserved rather than silently replacing the device', () async {
    final file = File('${root.path}/aims_flow_private/device_identity.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('broken-original');
    final service = DeviceIdentityService(supportDirectory: () async => root);
    await expectLater(service.loadOrCreate(), throwsFormatException);
    expect(await file.readAsString(), 'broken-original');
    await file.writeAsString(jsonEncode({'deviceId': 'a' * 64, 'secret': 'b' * 64}));
    expect((await service.loadOrCreate()).deviceId, 'a' * 64);
  });
}
