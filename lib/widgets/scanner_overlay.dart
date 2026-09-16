import 'package:flutter/material.dart';

class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key, this.hint = 'Tartsd a teljes CMR-t a kereten belül'});

  static const double frameLeft = 0.075;
  static const double frameTop = 0.105;
  static const double frameWidth = 0.85;
  static const double frameHeight = 0.69;

  final String hint;

  static Rect frameFor(Size size) => Rect.fromLTWH(
        size.width * frameLeft,
        size.height * frameTop,
        size.width * frameWidth,
        size.height * frameHeight,
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _ScannerFramePainter()),
          Positioned(
            left: 24,
            right: 24,
            bottom: 118,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.64),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = ScannerOverlay.frameFor(size);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.48);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, shade);

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    final pts = [frame.topLeft, frame.topRight, frame.bottomRight, frame.bottomLeft];
    canvas.drawLine(pts[0], pts[0] + const Offset(l, 0), paint);
    canvas.drawLine(pts[0], pts[0] + const Offset(0, l), paint);
    canvas.drawLine(pts[1], pts[1] + const Offset(-l, 0), paint);
    canvas.drawLine(pts[1], pts[1] + const Offset(0, l), paint);
    canvas.drawLine(pts[2], pts[2] + const Offset(-l, 0), paint);
    canvas.drawLine(pts[2], pts[2] + const Offset(0, -l), paint);
    canvas.drawLine(pts[3], pts[3] + const Offset(l, 0), paint);
    canvas.drawLine(pts[3], pts[3] + const Offset(0, -l), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
