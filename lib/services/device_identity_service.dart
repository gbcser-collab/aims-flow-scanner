import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.secret});

  final String deviceId;
  final String secret;

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'secret': secret};

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
        deviceId: json['deviceId'] as String,
        secret: json['secret'] as String,
      );
}

class DeviceIdentityService {
  const DeviceIdentityService();

  static const _trackingDeviceKey = 'aims_tracking_device_id';

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/aims_flow_private');
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}/device_identity.json');
  }

  String _randomHex(int byteCount) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < byteCount; index++) {
      buffer.write(
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      );
    }
    return buffer.toString();
  }

  bool _valid(DeviceIdentity identity) =>
      identity.deviceId.length >= 32 && identity.secret.length >= 32;

  Future<void> _publishDeviceId(DeviceIdentity identity) async {
    // Tracking, push and login must identify the same physical installation.
    // The ID is not a credential; the secret and session token remain in the
    // private file / secure storage.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trackingDeviceKey, identity.deviceId);
  }

  Future<DeviceIdentity> loadOrCreate() async {
    final file = await _file();
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final identity = DeviceIdentity.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (_valid(identity)) {
            await _publishDeviceId(identity);
            return identity;
          }
        }
      } catch (_) {}
    }

    final identity = DeviceIdentity(
      deviceId: _randomHex(32),
      secret: _randomHex(32),
    );
    await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
    await _publishDeviceId(identity);
    return identity;
  }
}
