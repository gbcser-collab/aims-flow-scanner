import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class DeviceCredentials {
  const DeviceCredentials({required this.id, required this.secret});

  final String id;
  final String secret;
}

class DeviceIdentityService {
  const DeviceIdentityService();

  Future<DeviceCredentials> getOrCreateCredentials() async {
    final root = await getApplicationSupportDirectory();
    final credentialsFile = File('${root.path}/aims_device_credentials.json');

    try {
      if (await credentialsFile.exists()) {
        final raw = jsonDecode(await credentialsFile.readAsString());
        if (raw is Map) {
          final id = raw['id']?.toString().trim() ?? '';
          final secret = raw['secret']?.toString().trim() ?? '';
          if (id.length >= 40 && secret.length >= 48) {
            return DeviceCredentials(id: id, secret: secret);
          }
        }
      }
    } catch (_) {}

    // Preserve the installation id from earlier AIMS Flow builds when possible.
    var id = '';
    final legacyFile = File('${root.path}/aims_device_id.txt');
    try {
      if (await legacyFile.exists()) {
        final legacy = (await legacyFile.readAsString()).trim();
        if (legacy.length >= 40) id = legacy;
      }
    } catch (_) {}

    final random = Random.secure();
    String token(int byteCount) => List<int>.generate(byteCount, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    if (id.isEmpty) id = token(24);
    final secret = token(32);
    final credentials = DeviceCredentials(id: id, secret: secret);

    final temp = File('${credentialsFile.path}.tmp');
    await temp.writeAsString(jsonEncode({'id': id, 'secret': secret}), flush: true);
    if (await credentialsFile.exists()) await credentialsFile.delete();
    await temp.rename(credentialsFile.path);

    try {
      await legacyFile.writeAsString(id, flush: true);
    } catch (_) {}

    return credentials;
  }

  Future<String> getOrCreateId() async => (await getOrCreateCredentials()).id;
}
