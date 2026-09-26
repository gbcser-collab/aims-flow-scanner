import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/models/scan_models.dart';

DocumentCorners _corners() => const DocumentCorners(
      topLeft: DocPoint(0, 0),
      topRight: DocPoint(100, 0),
      bottomRight: DocPoint(100, 140),
      bottomLeft: DocPoint(0, 140),
    );

void main() {
  test('good scan does not suggest retake', () {
    final result = ScanProcessingResult(
      outputPath: '/tmp/good.jpg',
      corners: _corners(),
      quality: const ScanQuality(
        brightness: 145,
        sharpness: 130,
        glareRatio: 0.01,
        documentFillRatio: 0.72,
      ),
      autoCropReliable: true,
      cornerConfidence: 0.88,
    );

    expect(result.quality.score, 100);
    expect(result.shouldSuggestRetake, isFalse);
  });

  test('unreliable crop suggests retake even with readable image', () {
    final result = ScanProcessingResult(
      outputPath: '/tmp/fallback.jpg',
      corners: _corners(),
      quality: const ScanQuality(
        brightness: 150,
        sharpness: 120,
        glareRatio: 0.01,
        documentFillRatio: 0.75,
      ),
      autoCropReliable: false,
      cornerConfidence: 0.25,
    );

    expect(result.shouldSuggestRetake, isTrue);
  });

  test('blur glare or tiny document triggers quality protection', () {
    const blur = ScanQuality(
      brightness: 145,
      sharpness: 40,
      glareRatio: 0.01,
      documentFillRatio: 0.72,
    );
    const glare = ScanQuality(
      brightness: 145,
      sharpness: 120,
      glareRatio: 0.10,
      documentFillRatio: 0.72,
    );
    const tiny = ScanQuality(
      brightness: 145,
      sharpness: 120,
      glareRatio: 0.01,
      documentFillRatio: 0.20,
    );

    expect(blur.isBlurry, isTrue);
    expect(glare.hasTooMuchGlare, isTrue);
    expect(tiny.documentTooSmall, isTrue);
  });
}
