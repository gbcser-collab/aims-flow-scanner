import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/tracking_models.dart';

class TrackingRepository {
  const TrackingRepository();

  Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/aims_tracking');
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}/current_trip.json');
  }

  Future<TrackingSession?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return TrackingSession.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TrackingSession session) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(session.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
