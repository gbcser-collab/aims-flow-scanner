import 'dart:math' as math;

import 'package:flutter/material.dart';

class AimsFlowSkin {
  static const background = Color(0xFF020813);
  static const background2 = Color(0xFF061B2D);
  static const panel = Color(0xCC071A2C);
  static const panelSolid = Color(0xFF081A2B);
  static const cyan = Color(0xFF22D9FF);
  static const blue = Color(0xFF0B76FF);
  static const paleBlue = Color(0xFF9EDBFF);
  static const green = Color(0xFF62F3B0);

  static BoxDecoration glass({double radius = 20, double alpha = .78}) {
    return BoxDecoration(
      color: panelSolid.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: cyan.withValues(alpha: .58), width: 1.1),
      boxShadow: [
        BoxShadow(color: cyan.withValues(alpha: .10), blurRadius: 26, spreadRadius: 1),
        BoxShadow(color: blue.withValues(alpha: .08), blurRadius: 50, spreadRadius: -10),
      ],
    );
  }

  static ButtonStyle primaryButton() => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        foregroundColor: Colors.white,
        backgroundColor: blue,
        shadowColor: cyan,
        elevation: 8,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cyan.withValues(alpha: .92), width: 1.2),
        ),
      );
}

class AimsFlowBackground extends StatelessWidget {
  const AimsFlowBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08234B), Color(0xFF03101E), Color(0xFF020813)],
          stops: [0, .45, 1],
        ),
      ),
      child: CustomPaint(
        painter: const _AimsArcPainter(),
        child: child,
      ),
    );
  }
}

class AimsFlowBrand extends StatelessWidget {
  const AimsFlowBrand({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlutterLogo(size: 42),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AIMS FLOW', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
              SizedBox(height: 2),
              Text('DRIVER OPERATIONS', style: TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 3.2)),
            ],
          ),
        ],
      );
    }

    return const Column(
      children: [
        FlutterLogo(size: 102),
        SizedBox(height: 10),
        Text('AIMS Flow Smart Scanner', style: TextStyle(color: Color(0xFFC9EAFF), fontSize: 22, fontWeight: FontWeight.w400)),
      ],
    );
  }
}

class AimsGlowButton extends StatelessWidget {
  const AimsGlowButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.trailing = true,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool trailing;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(colors: [Color(0xFF1CD7FF), Color(0xFF0B76FF)]),
        boxShadow: [BoxShadow(color: AimsFlowSkin.cyan.withValues(alpha: .30), blurRadius: 24)],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
            side: const BorderSide(color: AimsFlowSkin.cyan, width: 1.25),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Icon(icon, color: Colors.white, size: 28),
              ),
            ),
            Expanded(
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            ),
            SizedBox(width: 52, child: trailing ? const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 29) : null),
          ],
        ),
      ),
    );
  }
}

class _AimsArcPainter extends CustomPainter {
  const _AimsArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = const LinearGradient(colors: [AimsFlowSkin.cyan, AimsFlowSkin.blue, Colors.transparent]).createShader(Offset.zero & size);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AimsFlowSkin.blue.withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    final r1 = Rect.fromCircle(center: Offset(size.width * .16, size.height * .08), radius: size.width * .78);
    canvas.drawArc(r1, .2, math.pi * 1.18, false, glow);
    canvas.drawArc(r1, .2, math.pi * 1.18, false, soft);

    final r2 = Rect.fromCircle(center: Offset(size.width * 1.02, size.height * .43), radius: size.width * .62);
    canvas.drawArc(r2, math.pi * .76, math.pi * 1.03, false, glow);
    canvas.drawArc(r2, math.pi * .76, math.pi * 1.03, false, soft);

    final r3 = Rect.fromCircle(center: Offset(size.width * .12, size.height * 1.06), radius: size.width * .58);
    canvas.drawArc(r3, math.pi * 1.05, math.pi * 1.10, false, soft);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
