import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/tracking_models.dart';

class TrackingRepository {
  const TrackingRepository();

  Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/aims_tracking');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _currentFile() async {
    final root = await _root();
    return File('${root.path}/current_trip.json');
  }

  Future<Directory> _pendingDirectory() async {
    final root = await _root();
    final directory = Directory('${root.path}/pending_sessions');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<TrackingSession?> load() async {
    final file = await _currentFile();
    return _readSession(file);
  }

  Future<List<TrackingSession>> loadPending() async {
    final directory = await _pendingDirectory();
    final result = <TrackingSession>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final session = await _readSession(entity);
      if (session != null) result.add(session);
    }
    result.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return result;
  }

  Future<void> save(TrackingSession session) async {
    final file = await _currentFile();
    await _writeAtomic(file, jsonEncode(session.toJson()));
  }

  Future<void> archive(TrackingSession session) async {
    final directory = await _pendingDirectory();
    final safeId = session.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File('${directory.path}/$safeId.json');
    await _writeAtomic(file, jsonEncode(session.toJson()));
  }

  Future<void> removeArchived(String sessionId) async {
    final directory = await _pendingDirectory();
    final safeId = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File('${directory.path}/$safeId.json');
    if (await file.exists()) await file.delete();
  }

  Future<void> clear() async {
    final file = await _currentFile();
    if (await file.exists()) await file.delete();
  }

  Future<TrackingSession?> _readSession(File file) async {
    try {
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

  Future<void> _writeAtomic(File file, String contents) async {
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(contents, flush: true);

    if (!await file.exists()) {
      await temp.rename(file.path);
      return;
    }

    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
  }
}
