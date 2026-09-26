import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/scan_models.dart';

class FrameCropSpec {
  const FrameCropSpec({
    required this.viewportAspect,
    this.left = 0.075,
    this.top = 0.105,
    this.width = 0.85,
    this.height = 0.69,
  });

  final double viewportAspect;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// AIMS-owned document scanner core.
///
/// The capture is first restricted to the exact visible scanner frame. Edge
/// detection and perspective correction then run only inside that region, so
/// objects/background outside the UI frame cannot leak into the final CMR.
class AimsScanEngine {
  const AimsScanEngine();

  Future<ScanProcessingResult> process({
    required String inputPath,
    required String outputPath,
    String? signatureOutputPath,
    FrameCropSpec? frameCrop,
  }) {
    return Isolate.run(() => const AimsScanEngine()._processSync(
          inputPath: inputPath,
          outputPath: outputPath,
          signatureOutputPath: signatureOutputPath,
          frameCrop: frameCrop,
        ));
  }

  ScanProcessingResult _processSync({
    required String inputPath,
    required String outputPath,
    String? signatureOutputPath,
    FrameCropSpec? frameCrop,
  }) {
    final bytes = File(inputPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('A kép nem dekódolható.');

    var source = img.bakeOrientation(decoded);
    if (frameCrop != null) source = _cropToVisibleFrame(source, frameCrop);

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

    final detection = _detectDocument(source);
    final corners = detection.corners;
    final fillRatio = _polygonArea(corners) / (source.width * source.height);
    final warped = _warpToRectangle(source, corners);
    final enhanced = _enhanceDocument(warped);
    final quality = _measureQuality(enhanced, fillRatio);

    File(outputPath).writeAsBytesSync(
      img.encodeJpg(enhanced, quality: 94),
      flush: true,
    );

    String? signaturePath;
    double signatureConfidence = 0;
    if (signatureOutputPath != null && signatureOutputPath.trim().isNotEmpty) {
      final signature = _extractSignatureZone(enhanced);
      signatureConfidence = signature.$2;
      File(signatureOutputPath).writeAsBytesSync(
        img.encodeJpg(signature.$1, quality: 96),
        flush: true,
      );
      signaturePath = signatureOutputPath;
    }

    return ScanProcessingResult(
      outputPath: outputPath,
      corners: corners,
      quality: quality,
      autoCropReliable: detection.reliable,
      cornerConfidence: detection.confidence,
      signatureImagePath: signaturePath,
      signatureConfidence: signatureConfidence,
    );
  }

  img.Image _cropToVisibleFrame(img.Image source, FrameCropSpec spec) {
    final sourceAspect = source.width / source.height;
    final viewportAspect = spec.viewportAspect <= 0 ? sourceAspect : spec.viewportAspect;

    double visibleX = 0;
    double visibleY = 0;
    double visibleWidth = source.width.toDouble();
    double visibleHeight = source.height.toDouble();

    // Camera preview uses BoxFit.cover. Reproduce the same center-crop mapping
    // from the phone viewport back into the captured, orientation-corrected image.
    if (sourceAspect > viewportAspect) {
      visibleWidth = source.height * viewportAspect;
      visibleX = (source.width - visibleWidth) / 2;
    } else if (sourceAspect < viewportAspect) {
      visibleHeight = source.width / viewportAspect;
      visibleY = (source.height - visibleHeight) / 2;
    }

    final rawX = visibleX + visibleWidth * spec.left;
    final rawY = visibleY + visibleHeight * spec.top;
    final rawW = visibleWidth * spec.width;
    final rawH = visibleHeight * spec.height;

    final x = rawX.round().clamp(0, max(0, source.width - 2)).toInt();
    final y = rawY.round().clamp(0, max(0, source.height - 2)).toInt();
    final width = rawW.round().clamp(2, source.width - x).toInt();
    final height = rawH.round().clamp(2, source.height - y).toInt();
    return img.copyCrop(source, x: x, y: y, width: width, height: height);
  }

  _DocumentDetection _detectDocument(img.Image source) {
    const targetWidth = 720;
    final scale = source.width > targetWidth ? targetWidth / source.width : 1.0;
    final work = scale < 1
        ? img.copyResize(
            source,
            width: targetWidth,
            interpolation: img.Interpolation.average,
          )
        : img.Image.from(source);

    final w = work.width;
    final h = work.height;
    final luminance = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = work.getPixel(x, y);
        luminance[y * w + x] =
            0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      }
    }

    final magnitudes = <double>[];
    final candidates = <_EdgePoint>[];
    for (var y = 1; y < h - 1; y += 2) {
      for (var x = 1; x < w - 1; x += 2) {
        final gx =
            -luminance[(y - 1) * w + (x - 1)] +
            luminance[(y - 1) * w + (x + 1)] -
            2 * luminance[y * w + (x - 1)] +
            2 * luminance[y * w + (x + 1)] -
            luminance[(y + 1) * w + (x - 1)] +
            luminance[(y + 1) * w + (x + 1)];
        final gy =
            -luminance[(y - 1) * w + (x - 1)] -
            2 * luminance[(y - 1) * w + x] -
            luminance[(y - 1) * w + (x + 1)] +
            luminance[(y + 1) * w + (x - 1)] +
            2 * luminance[(y + 1) * w + x] +
            luminance[(y + 1) * w + (x + 1)];
        final mag = sqrt(gx * gx + gy * gy);
        magnitudes.add(mag);
        candidates.add(_EdgePoint(x.toDouble(), y.toDouble(), mag));
      }
    }

    _DocumentDetection fallback([double confidence = .18]) =>
        _DocumentDetection(
          _fallbackCorners(source.width, source.height),
          reliable: false,
          confidence: confidence,
        );

    if (magnitudes.isEmpty) return fallback();
    magnitudes.sort();
    final threshold = magnitudes[(magnitudes.length * 0.88).floor()];
    final marginX = w * 0.02;
    final marginY = h * 0.02;
    final strong = candidates.where((p) {
      return p.magnitude >= threshold &&
          p.x > marginX &&
          p.x < w - marginX &&
          p.y > marginY &&
          p.y < h - marginY;
    }).toList();

    if (strong.length < 40) return fallback(.22);

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
      return fallback(.20);
    }

    final inv = 1 / scale;
    final result = DocumentCorners(
      topLeft: DocPoint(tl.x * inv, tl.y * inv),
      topRight: DocPoint(tr.x * inv, tr.y * inv),
      bottomRight: DocPoint(br.x * inv, br.y * inv),
      bottomLeft: DocPoint(bl.x * inv, bl.y * inv),
    );

    final fillRatio = _polygonArea(result) / (source.width * source.height);
    if (fillRatio < 0.28 || fillRatio > 0.995) return fallback(.28);

    double distance(DocPoint a, DocPoint b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return sqrt(dx * dx + dy * dy);
    }

    final top = distance(result.topLeft, result.topRight);
    final bottom = distance(result.bottomLeft, result.bottomRight);
    final left = distance(result.topLeft, result.bottomLeft);
    final right = distance(result.topRight, result.bottomRight);
    final minSide = min(min(top, bottom), min(left, right));
    final maxSide = max(max(top, bottom), max(left, right));
    final sideHealth = maxSide <= 0 ? 0.0 : (minSide / maxSide).clamp(0.0, 1.0);
    final horizontalBalance =
        max(top, bottom) <= 0 ? 0.0 : (min(top, bottom) / max(top, bottom)).clamp(0.0, 1.0);
    final verticalBalance =
        max(left, right) <= 0 ? 0.0 : (min(left, right) / max(left, right)).clamp(0.0, 1.0);

    final edgeDensity = (strong.length / max(1, candidates.length))
        .clamp(0.0, 0.25) /
        0.25;
    final fillHealth = ((fillRatio - .28) / .50).clamp(0.0, 1.0);
    final confidence = (
      edgeDensity * .28 +
      horizontalBalance * .24 +
      verticalBalance * .24 +
      fillHealth * .18 +
      sideHealth * .06
    ).clamp(0.0, 1.0).toDouble();

    final reliable = confidence >= .52 &&
        horizontalBalance >= .42 &&
        verticalBalance >= .42 &&
        fillRatio >= .34;

    return _DocumentDetection(
      reliable ? result : _fallbackCorners(source.width, source.height),
      reliable: reliable,
      confidence: confidence,
    );
  }

  DocumentCorners _fallbackCorners(int width, int height) {
    final mx = width * 0.018;
    final my = height * 0.018;
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

    // Percentile-based contrast is much less sensitive to a single black stamp
    // or white glare pixel than min/max stretching.
    final histogram = List<int>.filled(256, 0);
    var samples = 0;
    for (var y = 0; y < result.height; y += 2) {
      for (var x = 0; x < result.width; x += 2) {
        final p = result.getPixel(x, y);
        final l = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
            .round()
            .clamp(0, 255);
        histogram[l]++;
        samples++;
      }
    }

    int percentile(double p) {
      final target = max(1, (samples * p).round());
      var seen = 0;
      for (var i = 0; i < histogram.length; i++) {
        seen += histogram[i];
        if (seen >= target) return i;
      }
      return 255;
    }

    final low = percentile(.03).toDouble();
    final high = percentile(.97).toDouble();
    final spread = max(40.0, high - low);

    for (final p in result) {
      int adjust(num value) {
        final normalized =
            ((value - low) / spread * 255).clamp(0, 255).toDouble();
        final contrasted = (normalized - 128) * 1.10 + 128;
        final whitened = contrasted > 178
            ? contrasted + (255 - contrasted) * 0.20
            : contrasted;
        return whitened.round().clamp(0, 255).toInt();
      }

      p
        ..r = adjust(p.r)
        ..g = adjust(p.g)
        ..b = adjust(p.b);
    }
    return result;
  }

  (img.Image, double) _extractSignatureZone(img.Image source) {
    final x = (source.width * 0.48).round().clamp(0, source.width - 2).toInt();
    final y = (source.height * 0.62).round().clamp(0, source.height - 2).toInt();
    final width = max(2, (source.width * 0.50).round()).clamp(2, source.width - x).toInt();
    final height = max(2, (source.height * 0.36).round()).clamp(2, source.height - y).toInt();
    final zone = img.copyCrop(source, x: x, y: y, width: width, height: height);

    var ink = 0;
    var total = 0;
    var minX = zone.width;
    var minY = zone.height;
    var maxX = 0;
    var maxY = 0;

    final edgePadX = max(3, (zone.width * 0.025).round());
    final edgePadY = max(3, (zone.height * 0.025).round());

    for (var yy = edgePadY; yy < zone.height - edgePadY; yy += 2) {
      for (var xx = edgePadX; xx < zone.width - edgePadX; xx += 2) {
        final p = zone.getPixel(xx, yy);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final maxC = max(r, max(g, b));
        final minC = min(r, min(g, b));
        final saturation = maxC <= 0 ? 0.0 : (maxC - minC) / maxC;
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;

        // Dark handwriting and coloured stamps should count as evidence.
        final isInk = luma < 170 || (saturation > 0.18 && luma < 235);
        total++;
        if (!isInk) continue;
        ink++;
        if (xx < minX) minX = xx;
        if (yy < minY) minY = yy;
        if (xx > maxX) maxX = xx;
        if (yy > maxY) maxY = yy;
      }
    }

    final density = total == 0 ? 0.0 : ink / total;
    final hasInkBounds = ink > 20 && maxX > minX && maxY > minY;
    img.Image result = zone;

    if (hasInkBounds) {
      final padX = max(18, ((maxX - minX) * 0.18).round());
      final padY = max(18, ((maxY - minY) * 0.22).round());
      final sx = max(0, minX - padX);
      final sy = max(0, minY - padY);
      final ex = min(zone.width - 1, maxX + padX);
      final ey = min(zone.height - 1, maxY + padY);
      if (ex - sx > zone.width * 0.30 && ey - sy > zone.height * 0.20) {
        result = img.copyCrop(
          zone,
          x: sx,
          y: sy,
          width: ex - sx + 1,
          height: ey - sy + 1,
        );
      }
    }

    // Whitening pass: preserve dark/coloured ink but clean the paper background.
    for (final p in result) {
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final maxC = max(r, max(g, b));
      final minC = min(r, min(g, b));
      final saturation = maxC <= 0 ? 0.0 : (maxC - minC) / maxC;
      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      if (luma > 185 && saturation < 0.16) {
        final amount = ((luma - 185) / 70).clamp(0.0, 1.0) * 0.72;
        p
          ..r = (r + (255 - r) * amount).round().clamp(0, 255)
          ..g = (g + (255 - g) * amount).round().clamp(0, 255)
          ..b = (b + (255 - b) * amount).round().clamp(0, 255);
      }
    }

    final confidence = (density * 18).clamp(0.0, 1.0).toDouble();
    return (result, confidence);
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

class _DocumentDetection {
  const _DocumentDetection(
    this.corners, {
    required this.reliable,
    required this.confidence,
  });

  final DocumentCorners corners;
  final bool reliable;
  final double confidence;
}
