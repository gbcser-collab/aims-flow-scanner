import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/scan_models.dart';

class ScanRepository {
  const ScanRepository();

  static const retentionAfterApproval = Duration(days: 15);

  Future<Directory> _scanDirectory() async {
    // ApplicationSupport is private app storage on Android/iOS. Files are not
    // written to Gallery, Downloads or a public Documents folder.
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/aims_private_scans');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _indexFile() async {
    final directory = await _scanDirectory();
    return File('${directory.path}/index.json');
  }

  Future<File> _auditFile() async {
    final directory = await _scanDirectory();
    return File('${directory.path}/audit.json');
  }

  Future<List<ScannedDocument>> loadAll() async {
    await purgeExpiredApproved();
    return _loadAllInternal();
  }

  Future<List<ScannedDocument>> _loadAllInternal() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return <ScannedDocument>[];

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <ScannedDocument>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ScannedDocument>[];

      final documents = <ScannedDocument>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final document = ScannedDocument.fromJson(Map<String, dynamic>.from(item));
          if (await File(document.imagePath).exists()) {
            documents.add(document);
          }
        } catch (_) {
          // One damaged history entry must never make the whole scanner unusable.
        }
      }
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (_) {
      return <ScannedDocument>[];
    }
  }

  Future<ScannedDocument> saveNew({
    required String sourceImagePath,
    required CmrData cmr,
    required ScanQuality quality,
  }) async {
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
      try {
        await source.delete();
      } catch (_) {
        // Temporary source cleanup is best-effort. The private copy is authoritative.
      }
    }

    final document = ScannedDocument(
      id: id,
      createdAt: createdAt,
      imagePath: destination.path,
      cmr: cmr,
      quality: quality,
      deliveryState: CmrDeliveryState.queued,
    );
    final all = await _loadAllInternal();
    all.insert(0, document);
    await _writeAll(all);
    return document;
  }

  Future<void> update(ScannedDocument document) async {
    final all = await _loadAllInternal();
    final index = all.indexWhere((item) => item.id == document.id);
    if (index >= 0) {
      all[index] = document;
    } else {
      all.insert(0, document);
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeAll(all);
  }

  Future<ScannedDocument?> findById(String id) async {
    final all = await _loadAllInternal();
    for (final document in all) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<List<ScannedDocument>> documentsNeedingServerSync() async {
    final all = await _loadAllInternal();
    return all.where((document) {
      return document.deliveryState == CmrDeliveryState.queued ||
          document.deliveryState == CmrDeliveryState.syncError ||
          document.deliveryState == CmrDeliveryState.uploaded ||
          document.deliveryState == CmrDeliveryState.emailed;
    }).toList();
  }

  Future<ScannedDocument> markUploaded(
    String id, {
    required String serverDocumentId,
    DateTime? uploadedAt,
  }) async {
    return _mutate(id, (document) {
      return document.copyWith(
        deliveryState: CmrDeliveryState.uploaded,
        serverDocumentId: serverDocumentId,
        uploadedAt: uploadedAt ?? DateTime.now(),
        lastSyncAttemptAt: DateTime.now(),
        clearLastSyncError: true,
      );
    });
  }

  Future<ScannedDocument> markEmailed(String id, {DateTime? emailedAt}) async {
    return _mutate(id, (document) {
      return document.copyWith(
        deliveryState: CmrDeliveryState.emailed,
        emailedAt: emailedAt ?? DateTime.now(),
        lastSyncAttemptAt: DateTime.now(),
        clearLastSyncError: true,
      );
    });
  }

  Future<ScannedDocument> markApproved(String id, {DateTime? approvedAt}) async {
    return _mutate(id, (document) {
      final approved = approvedAt ?? DateTime.now();
      return document.copyWith(
        deliveryState: CmrDeliveryState.approved,
        approvedAt: approved,
        deleteAfter: approved.add(retentionAfterApproval),
        lastSyncAttemptAt: DateTime.now(),
        clearLastSyncError: true,
      );
    });
  }

  Future<ScannedDocument> markSyncError(String id, Object error) async {
    return _mutate(id, (document) {
      return document.copyWith(
        deliveryState: CmrDeliveryState.syncError,
        lastSyncAttemptAt: DateTime.now(),
        lastSyncError: error.toString(),
      );
    });
  }

  Future<ScannedDocument> _mutate(
    String id,
    ScannedDocument Function(ScannedDocument document) transform,
  ) async {
    final all = await _loadAllInternal();
    final index = all.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw StateError('A CMR nem található: $id');
    }
    final updated = transform(all[index]);
    all[index] = updated;
    await _writeAll(all);
    return updated;
  }

  Future<int> purgeExpiredApproved({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final all = await _loadAllInternal();
    if (all.isEmpty) return 0;

    final keep = <ScannedDocument>[];
    final deleted = <CmrAuditRecord>[];

    for (final document in all) {
      final due = document.deleteAfter;
      if (document.isApproved && due != null && !due.isAfter(current)) {
        try {
          final image = File(document.imagePath);
          if (await image.exists()) await image.delete();
        } catch (_) {
          // The lifecycle state still advances; audit makes the action traceable.
        }
        deleted.add(
          CmrAuditRecord(
            documentId: document.id,
            cmrNumber: document.cmr.cmrNumber,
            plate: document.cmr.plate,
            serverDocumentId: document.serverDocumentId,
            createdAt: document.createdAt,
            emailedAt: document.emailedAt,
            approvedAt: document.approvedAt,
            deletedAt: current,
          ),
        );
      } else {
        keep.add(document);
      }
    }

    if (deleted.isEmpty) return 0;
    await _writeAll(keep);
    await _appendAudit(deleted);
    return deleted.length;
  }

  Future<List<Map<String, dynamic>>> loadAudit() async {
    try {
      final file = await _auditFile();
      if (!await file.exists()) return <Map<String, dynamic>>[];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _appendAudit(List<CmrAuditRecord> records) async {
    final existing = await loadAudit();
    existing.addAll(records.map((item) => item.toJson()));
    final file = await _auditFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(existing), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<void> _writeAll(List<ScannedDocument> documents) async {
    final file = await _indexFile();
    final temp = File('${file.path}.tmp');
    final payload = jsonEncode(documents.map((item) => item.toJson()).toList());
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
