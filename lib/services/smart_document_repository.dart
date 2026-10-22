import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smart_document_classifier.dart';
import 'local_serial_executor.dart';

enum SmartDocumentSyncState { pending, uploaded, failed }

class PendingSmartDocument {
  const PendingSmartDocument({
    required this.id,
    required this.type,
    required this.imagePath,
    required this.rawText,
    required this.confidence,
    required this.createdAt,
    required this.plate,
    this.syncState = SmartDocumentSyncState.pending,
    this.serverDocumentId,
    this.uploadedAt,
    this.lastError,
  });

  final String id;
  final SmartDocumentType type;
  final String imagePath;
  final String rawText;
  final double confidence;
  final DateTime createdAt;
  final String plate;
  final SmartDocumentSyncState syncState;
  final String? serverDocumentId;
  final DateTime? uploadedAt;
  final String? lastError;

  bool get needsSync =>
      syncState == SmartDocumentSyncState.pending ||
      syncState == SmartDocumentSyncState.failed;

  PendingSmartDocument copyWith({
    SmartDocumentSyncState? syncState,
    String? serverDocumentId,
    DateTime? uploadedAt,
    String? lastError,
    bool clearLastError = false,
  }) =>
      PendingSmartDocument(
        id: id,
        type: type,
        imagePath: imagePath,
        rawText: rawText,
        confidence: confidence,
        createdAt: createdAt,
        plate: plate,
        syncState: syncState ?? this.syncState,
        serverDocumentId: serverDocumentId ?? this.serverDocumentId,
        uploadedAt: uploadedAt ?? this.uploadedAt,
        lastError: clearLastError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'imagePath': imagePath,
        'rawText': rawText,
        'confidence': confidence,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'plate': plate,
        'syncState': syncState.name,
        'serverDocumentId': serverDocumentId,
        'uploadedAt': uploadedAt?.toUtc().toIso8601String(),
        'lastError': lastError,
      };

  static PendingSmartDocument? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final wire = value['type']?.toString() ?? '';
    final imagePath = value['imagePath']?.toString() ?? '';
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    final type =
        SmartDocumentType.values.where((t) => t.wire == wire).firstOrNull;
    if (id.isEmpty || imagePath.isEmpty || createdAt == null || type == null) {
      return null;
    }
    final syncName = value['syncState']?.toString() ?? 'pending';
    final syncState = SmartDocumentSyncState.values
            .where((state) => state.name == syncName)
            .firstOrNull ??
        SmartDocumentSyncState.pending;
    return PendingSmartDocument(
      id: id,
      type: type,
      imagePath: imagePath,
      rawText: value['rawText']?.toString() ?? '',
      confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt.toUtc(),
      plate: value['plate']?.toString().trim().toUpperCase() ?? '',
      syncState: syncState,
      serverDocumentId: value['serverDocumentId']?.toString(),
      uploadedAt:
          DateTime.tryParse(value['uploadedAt']?.toString() ?? '')?.toUtc(),
      lastError: value['lastError']?.toString(),
    );
  }
}

class SmartDocumentRepository {
  const SmartDocumentRepository({this.directory});
  final Future<Directory> Function()? directory;
  static final _serial = LocalSerialExecutor();

  static const _prefsKey = 'aims_pending_smart_documents_v1';
  static const _backupPrefsKey = 'aims_pending_smart_documents_v1_backup';

  Future<List<PendingSmartDocument>?> _decodeIndex(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final documents = <PendingSmartDocument>[];
      for (final value in decoded) {
        final document = PendingSmartDocument.fromJson(value);
        if (document == null) return null;
        documents.add(document);
      }
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (_) {
      return null;
    }
  }

  Future<List<PendingSmartDocument>> loadAll() => _serial.run(_loadAll);

  Future<List<PendingSmartDocument>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final primaryRaw = prefs.getString(_prefsKey);
    final backupRaw = prefs.getString(_backupPrefsKey);
    if (primaryRaw == null && backupRaw == null) return <PendingSmartDocument>[];
    final primary = await _decodeIndex(primaryRaw);
    if (primary != null) return primary;

    final backup = await _decodeIndex(backupRaw);
    if (backup != null) {
      if (backupRaw != null && backupRaw.trim().isNotEmpty) {
        // Preserve the damaged primary before recovery for manual inspection.
        if (primaryRaw != null && !await prefs.setString('${_prefsKey}_damaged', primaryRaw)) {
          throw const FileSystemException('A hibás dokumentumnapló mentése nem sikerült.');
        }
        if (!await prefs.setString(_prefsKey, backupRaw)) {
          throw const FileSystemException('A dokumentumnapló helyreállítása nem sikerült.');
        }
      }
      return backup;
    }
    throw const FileSystemException('A dokumentumnapló sérült. Az eredeti adat megmaradt; kérj irodai segítséget.');
  }

  Future<List<PendingSmartDocument>> pendingForSync() async {
    final all = await loadAll();
    return all
        .where((item) => item.needsSync && item.plate.trim().isNotEmpty)
        .toList();
  }

  Future<PendingSmartDocument> savePending({
    required String sourceImagePath,
    required SmartDocumentType type,
    required String rawText,
    required double confidence,
    required String plate,
  }) => _serial.run(() async {
    final now = DateTime.now().toUtc();
    final id = 'smart_${now.microsecondsSinceEpoch}';
    final root = await (directory ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${root.path}/aims_smart_documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = '${dir.path}/$id.jpg';
    final source = File(sourceImagePath);
    if (!await source.exists()) {
      throw const FileSystemException('A dokumentum képe nem található.');
    }
    await source.copy(target);

    final item = PendingSmartDocument(
      id: id,
      type: type,
      imagePath: target,
      rawText: rawText,
      confidence: confidence,
      createdAt: now,
      plate: plate.trim().toUpperCase(),
    );
    final all = await _loadAll();
    all.insert(0, item);
    await _writeAll(all);
    return item;
  });

  Future<void> update(PendingSmartDocument document) => _serial.run(() async {
    final all = await _loadAll();
    final index = all.indexWhere((item) => item.id == document.id);
    if (index >= 0) {
      all[index] = document;
    } else {
      all.insert(0, document);
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeAll(all);
  });

  Future<void> _writeAll(List<PendingSmartDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    final payload =
        jsonEncode([for (final document in documents) document.toJson()]);
    final current = prefs.getString(_prefsKey);
    if (current != null && current.trim().isNotEmpty) {
      if (!await prefs.setString(_backupPrefsKey, current)) {
        throw const FileSystemException('A dokumentumnapló biztonsági mentése nem sikerült.');
      }
    }
    final saved = await prefs.setString(_prefsKey, payload);
    if (!saved) {
      throw const FileSystemException(
        'A Smart Document index mentése nem sikerült.',
      );
    }
    await prefs.setString(_backupPrefsKey, payload);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
