import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smart_document_classifier.dart';

class PendingSmartDocument {
  const PendingSmartDocument({
    required this.id,
    required this.type,
    required this.imagePath,
    required this.rawText,
    required this.confidence,
    required this.createdAt,
  });

  final String id;
  final SmartDocumentType type;
  final String imagePath;
  final String rawText;
  final double confidence;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'imagePath': imagePath,
        'rawText': rawText,
        'confidence': confidence,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static PendingSmartDocument? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString() ?? '';
    final wire = value['type']?.toString() ?? '';
    final imagePath = value['imagePath']?.toString() ?? '';
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    final type = SmartDocumentType.values.where((t) => t.wire == wire).firstOrNull;
    if (id.isEmpty || imagePath.isEmpty || createdAt == null || type == null) {
      return null;
    }
    return PendingSmartDocument(
      id: id,
      type: type,
      imagePath: imagePath,
      rawText: value['rawText']?.toString() ?? '',
      confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt.toUtc(),
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
      return decoded
          .map(PendingSmartDocument.fromJson)
          .whereType<PendingSmartDocument>()
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<PendingSmartDocument> savePending({
    required String sourceImagePath,
    required SmartDocumentType type,
    required String rawText,
    required double confidence,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'smart_${now.microsecondsSinceEpoch}';
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/aims_smart_documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = '${dir.path}/$id.jpg';
    await File(sourceImagePath).copy(target);

    final item = PendingSmartDocument(
      id: id,
      type: type,
      imagePath: target,
      rawText: rawText,
      confidence: confidence,
      createdAt: now,
    );
    final all = await loadAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([item.toJson(), for (final old in all) old.toJson()]),
    );
    return item;
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
