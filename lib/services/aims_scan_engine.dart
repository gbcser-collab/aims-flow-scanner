import 'dart:io';
import 'dart:math';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/scan_models.dart';

/// AIMS-owned document scanner core.
///
/// This code performs document-edge estimation, perspective correction,
/// contrast enhancement and quality scoring without a document-scanner SDK.
class AimsScanEngine {
  const AimsScanEngine();

  Future<ScanProcessingResult> process({
    required String inputPath,
    required String outputPath,
  }) {
    return Isolate.run(() => const AimsScanEngine()._processSync(inputPath: inputPath, outputPath: outputPath));
  }

  ScanProcessingResult _processSync({
    required String inputPath,
    required String outputPath,
  }) {
    final bytes = File(inputPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('A kép nem dekódolható.');
    }

    var source = img.bakeOrientation(decoded);
    const maxWidth = 2400;
    const maxHeight = 3400;
    final scale = min(1.0, min(maxWidth / source.width, maxHeight / source.height));
    if (scale < 0.999) {
      source = img.copyResize(
        source,
        width: max(1, (source.width * scale).round()),
        height: max(1, (source.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    final corners = _detectDocument(source);
    final fillRatio = _polygonArea(corners) / (source.width * source.height);
    final warped = _warpToRectangle(source, corners);
    final enhanced = _enhanceDocument(warped);
    final quality = _measureQuality(enhanced, fillRatio);

    File(outputPath).writeAsBytesSync(img.encodeJpg(enhanced, quality: 90), flush: true);
    return ScanProcessingResult(outputPath: outputPath, corners: corners, quality: quality);
  }

  DocumentCorners _detectDocument(img.Image source) {
    const targetWidth = 720;
    final scale = source.width > targetWidth ? targetWidth / source.width : 1.0;
    final work = scale < 1
        ? img.copyResize(source, width: targetWidth, interpolation: img.Interpolation.average)
        : img.Image.from(source);

    final w = work.width;
    final h = work.height;
    final luminance = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = work.getPixel(x, y);
        luminance[y * w + x] = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      }
    }

    final magnitudes = <double>[];
    final candidates = <_EdgePoint>[];
    for (var y = 1; y < h - 1; y += 2) {
      for (var x = 1; x < w - 1; x += 2) {
        final gx =
            -luminance[(y - 1) * w + (x - 1)] + luminance[(y - 1) * w + (x + 1)] -
            2 * luminance[y * w + (x - 1)] + 2 * luminance[y * w + (x + 1)] -
            luminance[(y + 1) * w + (x - 1)] + luminance[(y + 1) * w + (x + 1)];
        final gy =
            -luminance[(y - 1) * w + (x - 1)] - 2 * luminance[(y - 1) * w + x] - luminance[(y - 1) * w + (x + 1)] +
            luminance[(y + 1) * w + (x - 1)] + 2 * luminance[(y + 1) * w + x] + luminance[(y + 1) * w + (x + 1)];
        final mag = sqrt(gx * gx + gy * gy);
        magnitudes.add(mag);
        candidates.add(_EdgePoint(x.toDouble(), y.toDouble(), mag));
      }
    }

    if (magnitudes.isEmpty) return _fallbackCorners(source.width, source.height);
    magnitudes.sort();
    final threshold = magnitudes[(magnitudes.length * 0.88).floor()];
    final marginX = w * 0.025;
    final marginY = h * 0.025;
    final strong = candidates.where((p) {
      return p.magnitude >= threshold && p.x > marginX && p.x < w - marginX && p.y > marginY && p.y < h - marginY;
    }).toList();

    if (strong.length < 40) return _fallbackCorners(source.width, source.height);

    _EdgePoint? tl;
    _EdgePoint? tr;
    _EdgePoint? br;
    _EdgePoint? bl;
    for (final p in strong) {
      if (tl == null || p.x + p.y < tl.x + tl.y) tl = p;
      if (br == null || p.x + p.y > br.x + br.y) br = p;
      if (tr == null || p.x - p.y > tr.x - tr.y) tr = p;
      if (bl == null || p.x - p.y < bl.x - bl.y) bl = p;
    }

    if (tl == null || tr == null || br == null || bl == null) {
      return _fallbackCorners(source.width, source.height);
    }

    final inv = 1 / scale;
    final result = DocumentCorners(
      topLeft: DocPoint(tl.x * inv, tl.y * inv),
      topRight: DocPoint(tr.x * inv, tr.y * inv),
      bottomRight: DocPoint(br.x * inv, br.y * inv),
      bottomLeft: DocPoint(bl.x * inv, bl.y * inv),
    );

    final ratio = _polygonArea(result) / (source.width * source.height);
    if (ratio < 0.28 || ratio > 0.995) return _fallbackCorners(source.width, source.height);
    return result;
  }

  DocumentCorners _fallbackCorners(int width, int height) {
    final mx = width * 0.045;
    final my = height * 0.045;
    return DocumentCorners(
      topLeft: DocPoint(mx, my),
      topRight: DocPoint(width - mx, my),
      bottomRight: DocPoint(width - mx, height - my),
      bottomLeft: DocPoint(mx, height - my),
    );
  }

  double _polygonArea(DocumentCorners c) {
    final p = c.ordered;
    var area = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      area += a.x * b.y - b.x * a.y;
    }
    return area.abs() / 2;
  }

  img.Image _warpToRectangle(img.Image source, DocumentCorners c) {
    double distance(DocPoint a, DocPoint b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return sqrt(dx * dx + dy * dy);
    }

    final width = max(distance(c.topLeft, c.topRight), distance(c.bottomLeft, c.bottomRight)).round().clamp(320, 1800).toInt();
    final height = max(distance(c.topLeft, c.bottomLeft), distance(c.topRight, c.bottomRight)).round().clamp(420, 2600).toInt();

    final output = img.Image(width: width, height: height, numChannels: 3);
    final q = c.ordered;
    final p0 = q[0];
    final p1 = q[1];
    final p2 = q[2];
    final p3 = q[3];

    final dx1 = p1.x - p2.x;
    final dx2 = p3.x - p2.x;
    final dx3 = p0.x - p1.x + p2.x - p3.x;
    final dy1 = p1.y - p2.y;
    final dy2 = p3.y - p2.y;
    final dy3 = p0.y - p1.y + p2.y - p3.y;
    final denom = dx1 * dy2 - dx2 * dy1;

    double g = 0;
    double h = 0;
    if (denom.abs() > 1e-9) {
      g = (dx3 * dy2 - dx2 * dy3) / denom;
      h = (dx1 * dy3 - dx3 * dy1) / denom;
    }
    final a = p1.x - p0.x + g * p1.x;
    final b = p3.x - p0.x + h * p3.x;
    final cc = p0.x;
    final d = p1.y - p0.y + g * p1.y;
    final e = p3.y - p0.y + h * p3.y;
    final f = p0.y;

    for (var y = 0; y < height; y++) {
      final v = y / max(1, height - 1);
      for (var x = 0; x < width; x++) {
        final u = x / max(1, width - 1);
        final z = g * u + h * v + 1;
        final sx = (a * u + b * v + cc) / z;
        final sy = (d * u + e * v + f) / z;
        final rgb = _sampleBilinear(source, sx, sy);
        output.setPixelRgb(x, y, rgb.$1, rgb.$2, rgb.$3);
      }
    }
    return output;
  }

  (int, int, int) _sampleBilinear(img.Image source, double x, double y) {
    final sx = x.clamp(0.0, source.width - 1.001);
    final sy = y.clamp(0.0, source.height - 1.001);
    final x0 = sx.floor();
    final y0 = sy.floor();
    final x1 = min(x0 + 1, source.width - 1);
    final y1 = min(y0 + 1, source.height - 1);
    final tx = sx - x0;
    final ty = sy - y0;
    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);

    int mix(num a, num b, num c, num d) {
      final top = a * (1 - tx) + b * tx;
      final bottom = c * (1 - tx) + d * tx;
      return (top * (1 - ty) + bottom * ty).round().clamp(0, 255).toInt();
    }

    return (
      mix(p00.r, p10.r, p01.r, p11.r),
      mix(p00.g, p10.g, p01.g, p11.g),
      mix(p00.b, p10.b, p01.b, p11.b),
    );
  }

  img.Image _enhanceDocument(img.Image source) {
    final result = img.Image.from(source);
    var minL = 255.0;
    var maxL = 0.0;
    for (final p in result) {
      final l = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      minL = min(minL, l);
      maxL = max(maxL, l);
    }
    final spread = max(32.0, maxL - minL);
    for (final p in result) {
      int adjust(num value) {
        final normalized = ((value - minL) / spread * 255).clamp(0, 255).toDouble();
        final contrasted = (normalized - 128) * 1.12 + 128;
        return contrasted.round().clamp(0, 255).toInt();
      }
      p
        ..r = adjust(p.r)
        ..g = adjust(p.g)
        ..b = adjust(p.b);
    }
    return result;
  }

  ScanQuality _measureQuality(img.Image source, double fillRatio) {
    final work = source.width > 700 ? img.copyResize(source, width: 700, interpolation: img.Interpolation.average) : source;
    final w = work.width;
    final h = work.height;
    final luma = Float64List(w * h);
    var brightnessSum = 0.0;
    var glare = 0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = work.getPixel(x, y);
        final l = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
        luma[y * w + x] = l;
        brightnessSum += l;
        if (l > 248 && p.r > 246 && p.g > 246 && p.b > 246) glare++;
      }
    }

    final lap = <double>[];
    for (var y = 1; y < h - 1; y += 2) {
      for (var x = 1; x < w - 1; x += 2) {
        final center = luma[y * w + x];
        final value = luma[(y - 1) * w + x] + luma[(y + 1) * w + x] + luma[y * w + x - 1] + luma[y * w + x + 1] - 4 * center;
        lap.add(value);
      }
    }
    final mean = lap.isEmpty ? 0.0 : lap.reduce((a, b) => a + b) / lap.length;
    var variance = 0.0;
    for (final v in lap) {
      final diff = v - mean;
      variance += diff * diff;
    }
    variance = lap.isEmpty ? 0 : variance / lap.length;

    return ScanQuality(
      brightness: brightnessSum / max(1, w * h),
      sharpness: variance,
      glareRatio: glare / max(1, w * h),
      documentFillRatio: fillRatio,
    );
  }
}

class _EdgePoint {
  const _EdgePoint(this.x, this.y, this.magnitude);
  final double x;
  final double y;
  final double magnitude;
}
