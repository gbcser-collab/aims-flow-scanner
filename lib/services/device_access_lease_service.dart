import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cmr_sync_service.dart';

class DeviceAccessLease {
  const DeviceAccessLease({
    required this.state,
    required this.confirmedAt,
  });

  final AimsDeviceState state;
  final DateTime confirmedAt;

  bool isExpired(DateTime now, Duration validity) => now.difference(confirmedAt) >= validity;
}

class DeviceAccessLeaseService {
  const DeviceAccessLeaseService();

  static const validity = Duration(hours: 24);

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    return File('${root.path}/aims_device_access_lease.json');
  }

  Future<DeviceAccessLease?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final stateText = decoded['state']?.toString();
      final confirmedAt = DateTime.tryParse(decoded['confirmedAt']?.toString() ?? '');
      if (stateText == null || confirmedAt == null) return null;
      final state = AimsDeviceState.values.firstWhere(
        (item) => item.name == stateText,
        orElse: () => AimsDeviceState.unknown,
      );
      if (state == AimsDeviceState.unknown || state == AimsDeviceState.unreachable) return null;
      return DeviceAccessLease(state: state, confirmedAt: confirmedAt.toLocal());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AimsDeviceState state, {DateTime? confirmedAt}) async {
    if (state == AimsDeviceState.unknown || state == AimsDeviceState.unreachable) return;
    final file = await _file();
    final temp = File('${file.path}.tmp');
    final payload = jsonEncode({
      'state': state.name,
      'confirmedAt': (confirmedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
