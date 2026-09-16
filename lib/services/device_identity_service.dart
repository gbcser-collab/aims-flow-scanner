import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class DeviceIdentityService {
  const DeviceIdentityService();

  Future<String> getOrCreateId() async {
    final root = await getApplicationSupportDirectory();
    final file = File('${root.path}/aims_device_id.txt');
    try {
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.length >= 20) return existing;
      }
    } catch (_) {}

    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final id = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await file.writeAsString(id, flush: true);
    return id;
  }
}
