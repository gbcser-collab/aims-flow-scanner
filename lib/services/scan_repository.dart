import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scan_models.dart';
import '../models/tracking_models.dart';

class ScanRepository {
  const ScanRepository();

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

  Future<List<ScannedDocument>> loadAll() async {
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
          // One damaged history entry should never make the whole scanner unusable.
        }
      }
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (_) {
      return <ScannedDocument>[];
    }
  }

  Future<List<ScannedDocument>> pendingForSync() async {
    final all = await loadAll();
    return all.where((item) => item.needsSync).toList();
  }

  Future<ScannedDocument> saveNew({
    required String sourceImagePath,
    String? signatureImagePath,
    double signatureConfidence = 0,
    required CmrData cmr,
    required ScanQuality quality,
    LocationStamp? location,
  }) async {
    final directory = await _scanDirectory();
    final createdAt = DateTime.now();
    final id = createdAt.microsecondsSinceEpoch.toString();
    final destination = File('${directory.path}/cmr_$id.jpg');
    final pdfDestination = File('${directory.path}/cmr_$id.pdf');
    final signatureDestination = signatureImagePath == null
        ? null
        : File('${directory.path}/cmr_${id}_signature.jpg');
    final source = File(sourceImagePath);

    if (!await source.exists()) {
      throw const FileSystemException('A feldolgozott CMR-kép nem található.');
    }
    if (source.absolute.path != destination.absolute.path) {
      await source.copy(destination.path);
    }

    if (signatureDestination != null) {
      final signatureSource = File(signatureImagePath!);
      if (await signatureSource.exists()) {
        if (signatureSource.absolute.path != signatureDestination.absolute.path) {
          await signatureSource.copy(signatureDestination.path);
        }
      }
    }

    final documentPdf = pw.Document(compress: true);
    final pageImage = pw.MemoryImage(await destination.readAsBytes());
    documentPdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14),
        build: (_) => pw.Center(
          child: pw.Image(pageImage, fit: pw.BoxFit.contain),
        ),
      ),
    );
    await pdfDestination.writeAsBytes(await documentPdf.save(), flush: true);

    final document = ScannedDocument(
      id: id,
      createdAt: createdAt,
      imagePath: destination.path,
      pdfPath: pdfDestination.path,
      signatureImagePath: signatureDestination != null &&
              await signatureDestination.exists()
          ? signatureDestination.path
          : null,
      signatureConfidence: signatureConfidence,
      cmr: cmr,
      quality: quality,
      location: location,
    );
    final all = await loadAll();
    all.insert(0, document);
    await _writeAll(all);
    return document;
  }

  Future<void> update(ScannedDocument document) async {
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

  Future<void> delete(ScannedDocument document) async {
    final all = await loadAll();
    all.removeWhere((item) => item.id == document.id);
    await _writeAll(all);
    try {
      final image = File(document.imagePath);
      if (await image.exists()) await image.delete();
      final pdfPath = document.pdfPath;
      if (pdfPath != null) {
        final pdf = File(pdfPath);
        if (await pdf.exists()) await pdf.delete();
      }
      final signaturePath = document.signatureImagePath;
      if (signaturePath != null) {
        final signature = File(signaturePath);
        if (await signature.exists()) await signature.delete();
      }
    } catch (_) {
      // The index is already clean even if the old image cannot be deleted.
    }
  }

  Future<int> pruneExpiredApproved() async {
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
        final pdfPath = document.pdfPath;
        if (pdfPath != null) {
          final pdf = File(pdfPath);
          if (await pdf.exists()) await pdf.delete();
        }
        final signaturePath = document.signatureImagePath;
        if (signaturePath != null) {
          final signature = File(signaturePath);
          if (await signature.exists()) await signature.delete();
        }
      } catch (_) {}
    }
    all.removeWhere((item) => expired.any((expiredItem) => expiredItem.id == item.id));
    await _writeAll(all);
    return expired.length;
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
