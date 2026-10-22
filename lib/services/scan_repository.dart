import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scan_models.dart';
import '../models/tracking_models.dart';
import 'local_serial_executor.dart';

class ScanRepository {
  const ScanRepository({this.directory, this.beforeReplace});
  final Future<Directory> Function()? directory;
  final Future<void> Function(File temporary)? beforeReplace;
  static final _serial = LocalSerialExecutor();

  Future<Directory> _scanDirectory() async {
    final root = await (this.directory ?? getApplicationDocumentsDirectory)();
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

  Future<List<ScannedDocument>> loadAll() => _serial.run(_loadAll);

  Future<List<ScannedDocument>> _loadAll() async {
    final file = await _indexFile();
    if (!await file.exists()) return <ScannedDocument>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) throw const FormatException('Invalid CMR index');
      final documents = <ScannedDocument>[];
      for (final item in decoded) {
        if (item is! Map) throw const FormatException('Invalid CMR record');
        // Missing image files remain visible and pending, never silently erased.
        documents.add(ScannedDocument.fromJson(Map<String, dynamic>.from(item)));
      }
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (_) {
      throw const FileSystemException('A CMR-napló nem olvasható. Az eredeti adat megmaradt; kérj irodai segítséget.');
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
  }) => _serial.run(() async {
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
    final all = await _loadAll();
    all.insert(0, document);
    await _writeAll(all);
    return document;
  });

  Future<bool> updateIfUnchanged(ScannedDocument original, ScannedDocument updated) => _serial.run(() async {
    if (original.id != updated.id) throw ArgumentError('Document identity changed');
    final all = await _loadAll();
    final index = all.indexWhere((item) => item.id == original.id);
    if (index < 0 || jsonEncode(all[index].toJson()) != jsonEncode(original.toJson())) return false;
    all[index] = updated;
    await _writeAll(all);
    return true;
  });

  Future<void> update(ScannedDocument document) => _serial.run(() async {
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

  Future<void> delete(ScannedDocument document) => _serial.run(() async {
    final all = await _loadAll();
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
  });

  Future<int> pruneExpiredApproved() => _serial.run(() async {
    final now = DateTime.now().toUtc();
    final all = await _loadAll();
    final expired = all.where((item) {
      final deadline = item.deleteAfter?.toUtc();
      return item.syncState == CmrSyncState.approved && deadline != null && !deadline.isAfter(now);
    }).toList();
    if (expired.isEmpty) return 0;

    all.removeWhere((item) => expired.any((expiredItem) => expiredItem.id == item.id));
    await _writeAll(all); // Commit removal before deleting any retained image.
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
    return expired.length;
  });

  Future<void> _writeAll(List<ScannedDocument> documents) async {
    final file = await _indexFile();
    final temp = File('${file.path}.tmp');
    final payload = jsonEncode(documents.map((item) => item.toJson()).toList());
    await temp.writeAsString(payload, flush: true);
    await beforeReplace?.call(temp);
    await temp.rename(file.path);
  }
}
