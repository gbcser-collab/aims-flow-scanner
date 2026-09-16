import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/freight_models.dart';

class DriverFlowRepository {
  const DriverFlowRepository();

  Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/aims_flow_driver_state.json');
    } catch (_) {
      return null;
    }
  }

  Future<FreightOperationState?> load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return FreightOperationState.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(FreightOperationState state) async {
    try {
      final file = await _file();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(state.encode(), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // Keep the driver workflow usable in memory if storage is unavailable.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}
