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

  test('calibration drag stays locked to the point that was grabbed', () {
    final c = NailFitV3Controller()
      ..photoWidth = 1000
      ..photoHeight = 1600;
    c.points.addAll(const <Offset>[Offset(.20, .20), Offset(.40, .20), Offset(.60, .20), Offset(.80, .20), Offset(.90, .40)]);
    const viewport = Size(400, 430);

    final firstDisplay = c.viewportPointFromSource(c.points.first, viewport);
    final secondBefore = c.points[1];
    expect(c.beginPointDrag(firstDisplay, viewport), isTrue);

    final nearSecond = c.viewportPointFromSource(const Offset(.39, .21), viewport);
    c.updatePointDrag(nearSecond, viewport);
    c.endPointDrag();

    expect(c.points.first.dx, closeTo(.39, .02));
    expect(c.points.first.dy, closeTo(.21, .02));
    expect(c.points[1], secondBefore);
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
