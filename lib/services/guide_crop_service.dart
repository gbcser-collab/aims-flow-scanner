import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:image/image.dart' as img;

/// Crops the captured camera image to exactly the area represented by the
/// on-screen scanner guide. The preview is rendered with BoxFit.cover, so the
/// same cover transform is reversed here before cropping the full-resolution
/// photo.
class GuideCropService {
  const GuideCropService();

  Future<String> crop({
    required String inputPath,
    required String outputPath,
    required double viewportWidth,
    required double viewportHeight,
    required double frameLeft,
    required double frameTop,
    required double frameWidth,
    required double frameHeight,
  }) {
    return Isolate.run(() => _cropSync(
          inputPath: inputPath,
          outputPath: outputPath,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
          frameLeft: frameLeft,
          frameTop: frameTop,
          frameWidth: frameWidth,
          frameHeight: frameHeight,
        ));
  }

  String _cropSync({
    required String inputPath,
    required String outputPath,
    required double viewportWidth,
    required double viewportHeight,
    required double frameLeft,
    required double frameTop,
    required double frameWidth,
    required double frameHeight,
  }) {
    final decoded = img.decodeImage(File(inputPath).readAsBytesSync());
    if (decoded == null) throw const FormatException('A kamera képe nem dekódolható.');
    final source = img.bakeOrientation(decoded);

    final iw = source.width.toDouble();
    final ih = source.height.toDouble();
    final vw = max(1.0, viewportWidth);
    final vh = max(1.0, viewportHeight);

    // Reverse BoxFit.cover.
    final scale = max(vw / iw, vh / ih);
    final displayedWidth = iw * scale;
    final displayedHeight = ih * scale;
    final overflowX = max(0.0, (displayedWidth - vw) / 2);
    final overflowY = max(0.0, (displayedHeight - vh) / 2);

    final guideX = frameLeft * vw;
    final guideY = frameTop * vh;
    final guideW = frameWidth * vw;
    final guideH = frameHeight * vh;

    final left = ((guideX + overflowX) / scale).floor().clamp(0, source.width - 2).toInt();
    final top = ((guideY + overflowY) / scale).floor().clamp(0, source.height - 2).toInt();
    final right = ((guideX + guideW + overflowX) / scale).ceil().clamp(left + 1, source.width).toInt();
    final bottom = ((guideY + guideH + overflowY) / scale).ceil().clamp(top + 1, source.height).toInt();

    final cropped = img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    File(outputPath).writeAsBytesSync(img.encodeJpg(cropped, quality: 94), flush: true);
    return outputPath;
  }
}
