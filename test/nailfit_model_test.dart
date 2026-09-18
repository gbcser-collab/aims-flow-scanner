import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailfit/nailfit_v3_model.dart';

void main() {
  test('BoxFit.cover source coordinates round-trip on portrait photo', () {
    final c = NailFitV3Controller()
      ..photoWidth = 1000
      ..photoHeight = 2000;
    const viewport = Size(398, 430);
    const source = Offset(.23, .67);

    final display = c.viewportPointFromSource(source, viewport);
    final recovered = c.sourcePointFromViewport(display, viewport);

    expect(recovered.dx, closeTo(source.dx, 0.0001));
    expect(recovered.dy, closeTo(source.dy, 0.0001));
  });

  test('BoxFit.cover source coordinates round-trip on landscape photo', () {
    final c = NailFitV3Controller()
      ..photoWidth = 2000
      ..photoHeight = 1000;
    const viewport = Size(398, 445);
    const source = Offset(.74, .31);

    final display = c.viewportPointFromSource(source, viewport);
    final recovered = c.sourcePointFromViewport(display, viewport);

    expect(recovered.dx, closeTo(source.dx, 0.0001));
    expect(recovered.dy, closeTo(source.dy, 0.0001));
  });

  test('personalized match reacts to selected shape instead of staying static', () {
    final c = NailFitV3Controller()
      ..preferredShape = 'Mandula'
      ..preferredStyle = 'Nude'
      ..scan = const ScanResult(
        tone: 'Világos-közepes',
        undertone: 'meleg',
        handShape: 'Arányos kéz · becslés',
        nailBed: 'Közepes · virtuális skála',
        recommendedShape: 'Mandula',
        quality: 'Jó',
        qualityScore: 82,
        brightness: 150,
        contrast: 32,
        resolution: '1200×1600',
        skinCoverage: .35,
        sharpness: 14,
        centerScore: 92,
        hint: 'A kép alkalmas a Try-Onhoz.',
      );

    c.shape = 'Mandula';
    final recommendedScore = c.currentMatchScore;
    c.shape = 'Kocka';
    final otherScore = c.currentMatchScore;

    expect(recommendedScore, greaterThan(otherScore));
  });
}
