import 'dart:math' as math;

import 'package:flutter/material.dart';

enum NailFinish { glossy, french, glitter, chrome }

class NailOverlayPainter extends CustomPainter {
  NailOverlayPainter({
    required this.points,
    required this.color,
    required this.shape,
    required this.length,
    required this.finish,
    required this.calibration,
    this.sourceSize,
  });

  final List<Offset> points;
  final Size? sourceSize;
  final Color color;
  final String shape;
  final double length;
  final NailFinish finish;
  final bool calibration;

  @override
  void paint(Canvas canvas, Size size) {
    final mapped = points.take(5).map((point) => _mapPoint(point, size)).toList(growable: false);
    for (var i = 0; i < mapped.length; i++) {
      final p = mapped[i];
      if (calibration) {
        final halo = Paint()
          ..color = const Color(0xFFD27B8F).withValues(alpha: .20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(p, 18, halo);
        canvas.drawCircle(p, 10, Paint()..color = const Color(0xFFD27B8F));
        _drawNumber(canvas, p, i + 1);
      } else {
        drawNail(
          canvas,
          p,
          _adaptiveNailWidth(i, mapped, size),
          color,
          shape,
          length,
          i,
          finish,
        );
      }
    }
  }

  Offset _mapPoint(Offset point, Size viewport) {
    final source = sourceSize;
    if (source == null || source.width <= 0 || source.height <= 0) {
      return Offset(point.dx * viewport.width, point.dy * viewport.height);
    }
    final scale = math.max(viewport.width / source.width, viewport.height / source.height);
    final renderedW = source.width * scale;
    final renderedH = source.height * scale;
    final originX = (viewport.width - renderedW) / 2;
    final originY = (viewport.height - renderedH) / 2;
    return Offset(originX + point.dx * renderedW, originY + point.dy * renderedH);
  }

  double _adaptiveNailWidth(int index, List<Offset> mapped, Size size) {
    if (mapped.length < 2) {
      const fallback = [0.082, 0.062, 0.065, 0.060, 0.052];
      return size.width * fallback[index.clamp(0, fallback.length - 1)];
    }
    var nearest = double.infinity;
    for (var i = 0; i < mapped.length; i++) {
      if (i == index) continue;
      nearest = math.min(nearest, (mapped[index] - mapped[i]).distance);
    }
    final fingerScale = index == 0 ? 1.10 : (index == 4 ? .86 : 1.0);
    return (nearest * .34 * fingerScale).clamp(size.width * .034, size.width * .092).toDouble();
  }

  void _drawNumber(Canvas canvas, Offset p, int n) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant NailOverlayPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.shape != shape ||
      oldDelegate.length != length ||
      oldDelegate.finish != finish ||
      oldDelegate.calibration != calibration ||
      oldDelegate.sourceSize != sourceSize;
}

class DemoHandPainter extends CustomPainter {
  DemoHandPainter({
    required this.color,
    required this.shape,
    required this.length,
    required this.finish,
    this.scanPose = false,
    this.softBackground = true,
  });

  final Color color;
  final String shape;
  final double length;
  final NailFinish finish;
  final bool scanPose;
  final bool softBackground;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    if (scanPose) {
      _paintScanHand(canvas, size);
    } else {
      _paintRelaxedHand(canvas, size);
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: softBackground
            ? const [Color(0xFFF8E8E1), Color(0xFFE8C8BC), Color(0xFFB98D7D)]
            : const [Color(0xFFF2D8CF), Color(0xFFC69A89), Color(0xFF9A6E62)],
        stops: const [0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final light = Paint()
      ..color = Colors.white.withValues(alpha: .34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46);
    canvas.drawCircle(Offset(size.width * .18, size.height * .16), size.width * .35, light);

    final fabric = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .05
      ..color = Colors.white.withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final fabricPath = Path()
      ..moveTo(-size.width * .1, size.height * .88)
      ..cubicTo(
        size.width * .28,
        size.height * .72,
        size.width * .56,
        size.height * .96,
        size.width * 1.1,
        size.height * .72,
      );
    canvas.drawPath(fabricPath, fabric);
  }

  Paint _skinPaint(Size size) {
    return Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF3BEA8), Color(0xFFD99A82), Color(0xFFB87462)],
        stops: [0, .58, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
  }

  void _paintRelaxedHand(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.save();
    canvas.translate(size.width * .025, size.height * .025);
    _drawRelaxedMass(canvas, size, shadow);
    canvas.restore();

    _drawRelaxedMass(canvas, size, _skinPaint(size));
    _drawSkinDetails(canvas, size, false);

    final points = <Offset>[
      Offset(size.width * .245, size.height * .49),
      Offset(size.width * .36, size.height * .23),
      Offset(size.width * .49, size.height * .16),
      Offset(size.width * .62, size.height * .21),
      Offset(size.width * .735, size.height * .31),
    ];
    final widths = [0.076, 0.058, 0.061, 0.057, 0.050];
    for (var i = 0; i < 5; i++) {
      drawNail(
        canvas,
        points[i],
        size.width * widths[i],
        color,
        shape,
        length,
        i,
        finish,
      );
    }

    _drawRing(canvas, size);
  }

  void _drawRelaxedMass(Canvas canvas, Size size, Paint paint) {
    void finger(double x, double y, double w, double h, double angle) {
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.rotate(angle);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size.width * w,
        height: size.height * h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * w * .48)),
        paint,
      );
      canvas.restore();
    }

    finger(.355, .37, .115, .405, -.035);
    finger(.49, .32, .118, .50, 0);
    finger(.62, .36, .11, .445, .025);
    finger(.735, .425, .099, .35, .055);
    finger(.242, .57, .112, .31, -.73);

    final palm = Path()
      ..moveTo(size.width * .294, size.height * .445)
      ..cubicTo(size.width * .36, size.height * .40, size.width * .68, size.height * .405, size.width * .755, size.height * .495)
      ..cubicTo(size.width * .80, size.height * .575, size.width * .744, size.height * .81, size.width * .66, size.height * .88)
      ..cubicTo(size.width * .585, size.height * .945, size.width * .414, size.height * .94, size.width * .338, size.height * .86)
      ..cubicTo(size.width * .273, size.height * .785, size.width * .25, size.height * .565, size.width * .294, size.height * .445)
      ..close();
    canvas.drawPath(palm, paint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .365, size.height * .81, size.width * .31, size.height * .25),
        Radius.circular(size.width * .12),
      ),
      paint,
    );
  }

  void _paintScanHand(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.save();
    canvas.translate(size.width * .018, size.height * .02);
    _drawScanMass(canvas, size, shadow);
    canvas.restore();
    _drawScanMass(canvas, size, _skinPaint(size));
    _drawSkinDetails(canvas, size, true);

    final points = scanNailPoints(size);
    final widths = [0.054, 0.050, 0.052, 0.049, 0.043];
    for (var i = 0; i < 5; i++) {
      drawNail(
        canvas,
        points[i],
        size.width * widths[i],
        color,
        shape,
        math.min(length, 1.06),
        i == 0 ? 0 : i,
        finish,
        rotationOverride: i == 0 ? -.15 : 0,
      );
    }
  }

  List<Offset> scanNailPoints(Size size) => [
        Offset(size.width * .79, size.height * .57),
        Offset(size.width * .30, size.height * .27),
        Offset(size.width * .45, size.height * .18),
        Offset(size.width * .60, size.height * .24),
        Offset(size.width * .72, size.height * .34),
      ];

  void _drawScanMass(Canvas canvas, Size size, Paint paint) {
    void finger(double x, double y, double w, double h, double angle) {
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: size.width * w,
            height: size.height * h,
          ),
          Radius.circular(size.width * w * .50),
        ),
        paint,
      );
      canvas.restore();
    }

    finger(.30, .42, .102, .46, -.06);
    finger(.45, .36, .106, .56, -.015);
    finger(.60, .405, .101, .49, .035);
    finger(.72, .47, .091, .39, .07);
    finger(.79, .62, .095, .30, .72);

    final palm = Path()
      ..moveTo(size.width * .265, size.height * .49)
      ..cubicTo(size.width * .34, size.height * .44, size.width * .67, size.height * .45, size.width * .76, size.height * .55)
      ..cubicTo(size.width * .83, size.height * .64, size.width * .76, size.height * .86, size.width * .64, size.height * .92)
      ..cubicTo(size.width * .52, size.height * .98, size.width * .34, size.height * .94, size.width * .28, size.height * .82)
      ..cubicTo(size.width * .23, size.height * .72, size.width * .22, size.height * .57, size.width * .265, size.height * .49)
      ..close();
    canvas.drawPath(palm, paint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .36, size.height * .84, size.width * .30, size.height * .23),
        Radius.circular(size.width * .12),
      ),
      paint,
    );
  }

  void _drawSkinDetails(Canvas canvas, Size size, bool scan) {
    final blush = Paint()
      ..color = const Color(0xFF9C5548).withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .52, size.height * (scan ? .66 : .60)),
        width: size.width * .36,
        height: size.height * .18,
      ),
      blush,
    );

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: .14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .405,
          size.height * (scan ? .45 : .44),
          size.width * .09,
          size.height * .34,
        ),
        Radius.circular(size.width * .04),
      ),
      highlight,
    );
  }

  void _drawRing(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width * .008)
      ..color = const Color(0xFFD8AF65);
    canvas.save();
    canvas.translate(size.width * .335, size.height * .455);
    canvas.rotate(-.03);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .10,
        height: size.height * .025,
      ),
      ring,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DemoHandPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.shape != shape ||
      oldDelegate.length != length ||
      oldDelegate.finish != finish ||
      oldDelegate.scanPose != scanPose ||
      oldDelegate.softBackground != softBackground;
}

class ScanOverlayPainter extends CustomPainter {
  const ScanOverlayPainter({this.complete = false});

  final bool complete;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .88);

    const inset = 18.0;
    const arm = 28.0;
    for (final top in [true, false]) {
      for (final left in [true, false]) {
        final x = left ? inset : size.width - inset;
        final y = top ? inset : size.height - inset;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + (left ? arm : -arm), y),
          line,
        );
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + (top ? arm : -arm)),
          line,
        );
      }
    }

    final handGuide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: .55);
    final guide = Path()
      ..moveTo(size.width * .22, size.height * .83)
      ..cubicTo(size.width * .16, size.height * .66, size.width * .18, size.height * .48, size.width * .26, size.height * .44)
      ..cubicTo(size.width * .27, size.height * .20, size.width * .34, size.height * .11, size.width * .40, size.height * .18)
      ..cubicTo(size.width * .43, size.height * .07, size.width * .51, size.height * .07, size.width * .55, size.height * .18)
      ..cubicTo(size.width * .60, size.height * .10, size.width * .67, size.height * .17, size.width * .67, size.height * .28)
      ..cubicTo(size.width * .75, size.height * .24, size.width * .79, size.height * .34, size.width * .77, size.height * .48)
      ..cubicTo(size.width * .90, size.height * .57, size.width * .83, size.height * .77, size.width * .71, size.height * .87)
      ..cubicTo(size.width * .58, size.height * .98, size.width * .34, size.height * .97, size.width * .22, size.height * .83);
    canvas.drawPath(guide, handGuide);

    final points = [
      Offset(size.width * .79, size.height * .57),
      Offset(size.width * .30, size.height * .27),
      Offset(size.width * .45, size.height * .18),
      Offset(size.width * .60, size.height * .24),
      Offset(size.width * .72, size.height * .34),
    ];
    final nail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = complete ? const Color(0xFFFFE9EE) : Colors.white.withValues(alpha: .80);
    for (var i = 0; i < points.length; i++) {
      final w = size.width * (i == 0 ? .060 : .050);
      final h = w * 1.55;
      canvas.drawOval(
        Rect.fromCenter(center: points[i], width: w, height: h),
        nail,
      );
      canvas.drawCircle(
        points[i],
        2.6,
        Paint()..color = const Color(0xFFFFF7F8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) => oldDelegate.complete != complete;
}

class NailSwatchPainter extends CustomPainter {
  NailSwatchPainter({
    required this.color,
    required this.shape,
    required this.finish,
  });

  final Color color;
  final String shape;
  final NailFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFF2EE), Color(0xFFE5C2B5)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final skin = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF1B9A0), Color(0xFFD59177)],
      ).createShader(Offset.zero & size);

    for (var i = 0; i < 4; i++) {
      final x = size.width * (.18 + i * .21);
      final y = size.height * (.62 - (i == 1 || i == 2 ? .08 : 0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((i - 1.5) * .05);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: size.width * .16,
            height: size.height * .62,
          ),
          Radius.circular(size.width * .08),
        ),
        skin,
      );
      canvas.restore();
      drawNail(
        canvas,
        Offset(x, y - size.height * .21),
        size.width * .12,
        color,
        shape,
        .95,
        i + 1,
        finish,
        rotationOverride: (i - 1.5) * .05,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NailSwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.shape != shape ||
      oldDelegate.finish != finish;
}

void drawNail(
  Canvas canvas,
  Offset center,
  double width,
  Color color,
  String shape,
  double length,
  int index,
  NailFinish finish, {
  double? rotationOverride,
}) {
  final height = width * (1.55 + (length - 1) * 1.25);
  final rotations = [-.70, -.04, 0.0, .035, .075, .10];
  final rotation = rotationOverride ?? rotations[index.clamp(0, rotations.length - 1)];
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);

  final path = nailPath(width, height, shape);
  final cuticleShadow = Paint()
    ..color = const Color(0xFF78483F).withValues(alpha: .26)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
  canvas.save();
  canvas.translate(0, height * .11);
  canvas.scale(1.08, .42);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: width * .94, height: width * .46),
    cuticleShadow,
  );
  canvas.restore();

  canvas.drawShadow(path, Colors.black.withValues(alpha: .35), 4, false);
  final polishRect = Rect.fromLTWH(-width / 2, -height, width, height * 1.22);
  final polish = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.white, .24)!,
        color,
        Color.lerp(color, Colors.black, .10)!,
      ],
      stops: const [0, .52, 1],
    ).createShader(polishRect);
  canvas.drawPath(path, polish);

  canvas.save();
  canvas.clipPath(path);

  if (finish == NailFinish.french) {
    final tipPaint = Paint()..color = const Color(0xFFFFFCF8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-width * .55, -height * .88, width * 1.1, height * .25),
        Radius.circular(width * .22),
      ),
      tipPaint,
    );
  }

  if (finish == NailFinish.glitter) {
    final rnd = math.Random(index * 941 + color.toARGB32());
    final glitter = Paint()..color = Colors.white.withValues(alpha: .72);
    for (var i = 0; i < 22; i++) {
      canvas.drawCircle(
        Offset(
          -width * .40 + rnd.nextDouble() * width * .80,
          -height * .68 + rnd.nextDouble() * height * .70,
        ),
        .6 + rnd.nextDouble() * 1.2,
        glitter,
      );
    }
  }

  if (finish == NailFinish.chrome) {
    final chrome = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: .15),
          Colors.white.withValues(alpha: .62),
          Colors.transparent,
          Colors.white.withValues(alpha: .34),
        ],
        stops: const [0, .34, .62, 1],
      ).createShader(polishRect);
    canvas.drawRect(polishRect, chrome);
  }

  final gloss = Paint()
    ..color = Colors.white.withValues(alpha: finish == NailFinish.chrome ? .42 : .30)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.1, width * .075)
    ..strokeCap = StrokeCap.round;
  final glossPath = Path()
    ..moveTo(-width * .18, -height * .66)
    ..cubicTo(-width * .28, -height * .38, -width * .22, -height * .08, -width * .10, height * .02);
  canvas.drawPath(glossPath, gloss);
  canvas.restore();

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = Colors.white.withValues(alpha: .18),
  );
  canvas.restore();
}

Path nailPath(double w, double h, String shape) {
  final path = Path();
  final top = -h * .80;
  final bottom = h * .18;

  switch (shape) {
    case 'Kocka':
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(-w / 2, top, w / 2, bottom),
          Radius.circular(w * .13),
        ),
      );
      break;
    case 'Coffin':
      path
        ..moveTo(-w * .28, top)
        ..lineTo(w * .28, top)
        ..lineTo(w * .50, bottom)
        ..quadraticBezierTo(0, bottom + h * .045, -w * .50, bottom)
        ..close();
      break;
    case 'Stiletto':
      path
        ..moveTo(0, top - h * .15)
        ..cubicTo(w * .40, top + h * .16, w * .51, -h * .05, w * .47, bottom)
        ..quadraticBezierTo(0, bottom + h * .045, -w * .47, bottom)
        ..cubicTo(-w * .51, -h * .05, -w * .40, top + h * .16, 0, top - h * .15)
        ..close();
      break;
    case 'Ovális':
      path.addOval(Rect.fromLTRB(-w / 2, top, w / 2, bottom));
      break;
    default:
      path
        ..moveTo(0, top)
        ..cubicTo(w * .28, top + h * .025, w * .50, -h * .08, w * .48, bottom)
        ..quadraticBezierTo(0, bottom + h * .045, -w * .48, bottom)
        ..cubicTo(-w * .50, -h * .08, -w * .28, top + h * .025, 0, top)
        ..close();
  }
  return path;
}
