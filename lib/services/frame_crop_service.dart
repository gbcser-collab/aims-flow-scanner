import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Crops a captured camera image to the same normalized area shown by the
/// scanner overlay. The surrounding table/dashboard/background never enters
/// the OCR/document-processing pipeline.
class FrameCropService {
  const FrameCropService();

  Future<String> crop({required String inputPath, required String outputPath}) {
    return Isolate.run(() {
      final bytes = File(inputPath).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('A kamera képe nem dekódolható.');

      final source = img.bakeOrientation(decoded);
      final left = (source.width * .075).round().clamp(0, source.width - 2);
      final top = (source.height * .105).round().clamp(0, source.height - 2);
      final right = (source.width * .925).round().clamp(left + 1, source.width);
      final bottom = (source.height * .795).round().clamp(top + 1, source.height);

      final cropped = img.copyCrop(
        source,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
      File(outputPath).writeAsBytesSync(img.encodeJpg(cropped, quality: 94), flush: true);
      return outputPath;
    });
  }
}
