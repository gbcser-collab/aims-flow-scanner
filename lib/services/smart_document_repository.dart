import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smart_document_classifier.dart';

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
  const SmartDocumentRepository();

  static const _prefsKey = 'aims_pending_smart_documents_v1';

  Future<List<PendingSmartDocument>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final documents = decoded
          .map(PendingSmartDocument.fromJson)
          .whereType<PendingSmartDocument>()
          .toList();
      final existing = <PendingSmartDocument>[];
      for (final document in documents) {
        if (await File(document.imagePath).exists()) existing.add(document);
      }
      existing.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return existing;
    } catch (_) {
      return const [];
    }
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
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'smart_${now.microsecondsSinceEpoch}';
    final root = await getApplicationDocumentsDirectory();
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
    final all = await loadAll();
    all.insert(0, item);
    await _writeAll(all);
    return item;
  }

  Future<void> update(PendingSmartDocument document) async {
    final all = await loadAll();
    final index = all.indexWhere((item) => item.id == document.id);
    if (index >= 0) {
      all[index] = document;
    } else {
      all.insert(0, document);
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeAll(all);
  }

  Future<void> _writeAll(List<PendingSmartDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final document in documents) document.toJson()]),
    );
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
