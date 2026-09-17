import 'dart:math' as math;

import 'package:flutter/material.dart';

const aimsCyan = Color(0xFF21D6FF);
const aimsBlue = Color(0xFF0B76FF);
const aimsDeepBlue = Color(0xFF06224A);
const aimsNavy = Color(0xFF021126);
const aimsPanel = Color(0xB50A2447);
const aimsMint = Color(0xFF65F0B6);

class AimsBackdrop extends StatelessWidget {
  const AimsBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF062C61), Color(0xFF031A3A), Color(0xFF010A17)],
          stops: [0, .44, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _AimsArcPainter()),
          child,
        ],
      ),
    );
  }
}

class _AimsArcPainter extends CustomPainter {
  const _AimsArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = const LinearGradient(
        colors: [Color(0x0021D6FF), Color(0xFF1ACBFF), Color(0x001ACBFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final soft = Paint()
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        colors: [Color(0x542ED8FF), Color(0x000B76FF)],
      ).createShader(Rect.fromCircle(center: Offset(size.width * .85, size.height * .25), radius: size.width * .42));
    canvas.drawCircle(Offset(size.width * .85, size.height * .25), size.width * .42, soft);

    final rect1 = Rect.fromLTWH(-size.width * .36, -size.width * .10, size.width * 1.35, size.width * 1.35);
    canvas.drawArc(rect1, math.pi * .05, math.pi * 1.12, false, glow);

    final rect2 = Rect.fromLTWH(size.width * .42, size.height * .29, size.width * .95, size.width * .95);
    canvas.drawArc(rect2, math.pi * .83, math.pi * 1.04, false, glow);

    final rect3 = Rect.fromLTWH(-size.width * .45, size.height * .78, size.width * .9, size.width * .9);
    canvas.drawArc(rect3, math.pi * 1.25, math.pi * .95, false, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AimsFlowMark extends StatelessWidget {
  const AimsFlowMark({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AimsMarkPainter()),
    );
  }
}

class _AimsMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Path poly(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      return path..close();
    }

    final cyan = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF4DEBFF), Color(0xFF18BFF7)]).createShader(Offset.zero & size);
    final blue = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF25C7FF), Color(0xFF006DFF)]).createShader(Offset.zero & size);

    canvas.drawPath(poly(const [Offset(.18, .30), Offset(.58, .05), Offset(.82, .05), Offset(.39, .39)]), cyan);
    canvas.drawPath(poly(const [Offset(.34, .52), Offset(.60, .33), Offset(.79, .33), Offset(.50, .58)]), cyan);
    canvas.drawPath(poly(const [Offset(.48, .58), Offset(.77, .86), Offset(.52, .86), Offset(.34, .66)]), blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AimsFakeStatusBar extends StatelessWidget {
  const AimsFakeStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('9:41', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        Spacer(),
        Icon(Icons.signal_cellular_alt_rounded, color: Colors.white, size: 20),
        SizedBox(width: 7),
        Icon(Icons.wifi_rounded, color: Colors.white, size: 21),
        SizedBox(width: 7),
        Icon(Icons.battery_full_rounded, color: Colors.white, size: 23),
      ],
    );
  }
}

class AimsGlassCard extends StatelessWidget {
  const AimsGlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: aimsPanel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: aimsCyan.withValues(alpha: .68), width: 1.2),
        boxShadow: [
          BoxShadow(color: aimsBlue.withValues(alpha: .15), blurRadius: 24, spreadRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class AimsNeonButton extends StatelessWidget {
  const AimsNeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing = const Icon(Icons.arrow_forward_rounded, color: Colors.white),
    this.height = 62,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final double height;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: secondary
              ? const LinearGradient(colors: [Color(0xD1113B67), Color(0xD10A2D57)])
              : const LinearGradient(colors: [Color(0xFF22DAFF), Color(0xFF0B76FF)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF63E9FF), width: 1.15),
          boxShadow: [BoxShadow(color: aimsCyan.withValues(alpha: secondary ? .10 : .34), blurRadius: secondary ? 10 : 22)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  SizedBox(width: 34, child: Center(child: leading)),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: secondary ? 18 : 20,
                        fontWeight: secondary ? FontWeight.w500 : FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 34, child: Center(child: trailing)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AimsSectionTitle extends StatelessWidget {
  const AimsSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

InputDecoration aimsInputDecoration(String label, {Widget? prefix, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFFAAD8FF)),
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xAA10345F),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF6ADFFF))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF58CFFF))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: aimsCyan, width: 1.6)),
  );
}
