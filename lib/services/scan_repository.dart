import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/scan_models.dart';
import '../models/tracking_models.dart';

class ScanRepository {
  const ScanRepository();

  // All repository instances share the same mutation queue. The UI, background
  // sync and lifecycle callbacks may otherwise perform read-modify-write cycles
  // at the same time and silently overwrite each other's index changes.
  static Future<void> _mutationTail = Future<void>.value();

  Future<Directory> _scanDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/aims_scans');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _indexFile() async {
    final directory = await _scanDirectory();
    return File('${directory.path}/index.json');
  }

  Future<File> _backupFile() async {
    final index = await _indexFile();
    return File('${index.path}.bak');
  }

  Future<List<ScannedDocument>> loadAll() async {
    final file = await _indexFile();
    final backup = await _backupFile();

    final primary = await _readIndex(file);
    if (primary != null) return primary;

    // If Android or the process stopped between the two rename operations of an
    // atomic update, the last complete index is still available here.
    final recovered = await _readIndex(backup);
    return recovered ?? <ScannedDocument>[];
  }

  Future<List<ScannedDocument>?> _readIndex(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final documents = <ScannedDocument>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final document = ScannedDocument.fromJson(Map<String, dynamic>.from(item));
          if (await File(document.imagePath).exists()) documents.add(document);
        } catch (_) {
          // One damaged history entry must not make the whole scanner unusable.
        }
      }
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (_) {
      return null;
    }
  }

  Future<List<ScannedDocument>> pendingForSync() async {
    final all = await loadAll();
    return all.where((item) => item.needsSync).toList();
  }

  Future<ScannedDocument> saveNew({
    required String sourceImagePath,
    required CmrData cmr,
    required ScanQuality quality,
    LocationStamp? location,
  }) {
    return _mutate(() async {
      final directory = await _scanDirectory();
      final createdAt = DateTime.now();
      final id = createdAt.microsecondsSinceEpoch.toString();
      final destination = File('${directory.path}/cmr_$id.jpg');
      final source = File(sourceImagePath);

      if (!await source.exists()) {
        throw const FileSystemException('A feldolgozott CMR-kép nem található.');
      }
      if (source.absolute.path != destination.absolute.path) {
        await source.copy(destination.path);
      }

      final document = ScannedDocument(
        id: id,
        createdAt: createdAt,
        imagePath: destination.path,
        cmr: cmr,
        quality: quality,
        location: location,
      );
      final all = await loadAll();
      all.removeWhere((item) => item.id == document.id);
      all.insert(0, document);
      await _writeAll(all);
      return document;
    });
  }

  Future<void> update(ScannedDocument document) {
    return _mutate(() async {
      final all = await loadAll();
      final index = all.indexWhere((item) => item.id == document.id);
      if (index >= 0) {
        all[index] = document;
      } else {
        all.insert(0, document);
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _writeAll(all);
    });
  }

  Future<void> delete(ScannedDocument document) {
    return _mutate(() async {
      final all = await loadAll();
      all.removeWhere((item) => item.id == document.id);
      await _writeAll(all);
      try {
        final image = File(document.imagePath);
        if (await image.exists()) await image.delete();
      } catch (_) {
        // The index is already clean even if the old image cannot be deleted.
      }
    });
  }

  Future<int> pruneExpiredApproved() {
    return _mutate(() async {
      final now = DateTime.now().toUtc();
      final all = await loadAll();
      final expired = all.where((item) {
        final deadline = item.deleteAfter?.toUtc();
        return item.syncState == CmrSyncState.approved && deadline != null && !deadline.isAfter(now);
      }).toList();
      if (expired.isEmpty) return 0;

      for (final document in expired) {
        try {
          final image = File(document.imagePath);
          if (await image.exists()) await image.delete();
        } catch (_) {}
      }
      final expiredIds = expired.map((item) => item.id).toSet();
      all.removeWhere((item) => expiredIds.contains(item.id));
      await _writeAll(all);
      return expired.length;
    });
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _writeAll(List<ScannedDocument> documents) async {
    final file = await _indexFile();
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');
    final payload = jsonEncode(documents.map((item) => item.toJson()).toList());

    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(payload, flush: true);

    if (!await file.exists()) {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
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
