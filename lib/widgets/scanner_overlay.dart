import 'package:flutter/material.dart';

import 'aims_skin.dart';

class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key, this.hint = 'Tartsd a teljes CMR-t a kereten belül'});
  final String hint;

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
                color: const Color(0xE0061A35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: aimsCyan.withValues(alpha: .45)),
                boxShadow: [BoxShadow(color: aimsCyan.withValues(alpha: .16), blurRadius: 16)],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
    final frame = Rect.fromLTWH(size.width * 0.075, size.height * 0.105, size.width * 0.85, size.height * 0.69);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.46);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, shade);

    final glow = Paint()
      ..color = aimsCyan.withValues(alpha: .25)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final paint = Paint()
      ..color = aimsCyan
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    final pts = [frame.topLeft, frame.topRight, frame.bottomRight, frame.bottomLeft];

    for (final p in [glow, paint]) {
      canvas.drawLine(pts[0], pts[0] + const Offset(l, 0), p);
      canvas.drawLine(pts[0], pts[0] + const Offset(0, l), p);
      canvas.drawLine(pts[1], pts[1] + const Offset(-l, 0), p);
      canvas.drawLine(pts[1], pts[1] + const Offset(0, l), p);
      canvas.drawLine(pts[2], pts[2] + const Offset(-l, 0), p);
      canvas.drawLine(pts[2], pts[2] + const Offset(0, -l), p);
      canvas.drawLine(pts[3], pts[3] + const Offset(l, 0), p);
      canvas.drawLine(pts[3], pts[3] + const Offset(0, -l), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
