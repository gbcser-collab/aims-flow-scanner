import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NailFitApp());
}

class NailFitApp extends StatelessWidget {
  const NailFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const rose = Color(0xFFEBA6B4);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAILFIT',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: rose,
          brightness: Brightness.dark,
          surface: const Color(0xFF171217),
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0B0E),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'sans-serif'),
        ),
      ),
      home: const NailFitHome(),
    );
  }
}

class NailFitHome extends StatefulWidget {
  const NailFitHome({super.key});

  @override
  State<NailFitHome> createState() => _NailFitHomeState();
}

class _NailFitHomeState extends State<NailFitHome> {
  final ImagePicker _picker = ImagePicker();
  final List<Offset> _points = [];

  XFile? _photo;
  String _shape = 'Mandula';
  Color _color = const Color(0xFFC98384);
  double _length = .98;
  bool _demo = true;

  static const _colors = <Color>[
    Color(0xFFC98384),
    Color(0xFFE7C2B7),
    Color(0xFFF0E7E0),
    Color(0xFFB96A78),
    Color(0xFF7A263B),
    Color(0xFF241A1D),
    Color(0xFFB0A0BA),
    Color(0xFF687866),
    Color(0xFFB88855),
    Color(0xFF809AAA),
  ];

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2000,
    );
    if (!mounted || image == null) return;
    setState(() {
      _photo = image;
      _points.clear();
      _demo = false;
    });
  }

  void _useDemo() {
    setState(() {
      _photo = null;
      _points.clear();
      _demo = true;
    });
  }

  void _addPoint(Offset local, Size size) {
    if (_demo || _points.length >= 5) return;
    setState(() {
      _points.add(Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      ));
    });
  }

  int get _match {
    final base = switch (_shape) {
      'Mandula' => 97,
      'Ovális' => 95,
      'Kocka' => 89,
      'Coffin' => 92,
      _ => 87,
    };
    return (base - ((_length - 1).abs() * 12)).round().clamp(79, 98);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _header(),
                  const SizedBox(height: 18),
                  _preview(),
                  const SizedBox(height: 14),
                  _sourceButtons(),
                  const SizedBox(height: 24),
                  _shapeSelector(),
                  const SizedBox(height: 20),
                  _colorSelector(),
                  const SizedBox(height: 20),
                  _lengthSelector(),
                  const SizedBox(height: 20),
                  _matchCard(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'NAIL',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.8,
                fontSize: 16,
              ),
            ),
            const Text(
              'FIT',
              style: TextStyle(
                color: Color(0xFFEBA6B4),
                fontWeight: FontWeight.w900,
                letterSpacing: 2.8,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .045),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFFEBA6B4)),
                  SizedBox(width: 5),
                  Text('BEAUTY AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Próbáld fel.\nMielőtt elkészül.',
          style: TextStyle(
            fontSize: 40,
            height: .96,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.9,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          _demo
              ? 'Lásd a formát, a színt és a hosszt még a szalon előtt. Ezután próbáld ki a saját kezeden.'
              : _points.length < 5
                  ? 'Jelöld meg sorban az öt körmöt. ${_points.length}/5 kész.'
                  : 'Kész. Most válts formát, színt és hosszt a saját kezeden.',
          style: const TextStyle(
            color: Color(0xFFB9B0B6),
            height: 1.45,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171217),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 38,
            offset: Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AspectRatio(
          aspectRatio: .78,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (event) => _addPoint(event.localPosition, size),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_demo)
                      CustomPaint(
                        painter: DemoHandPainter(
                          color: _color,
                          shape: _shape,
                          length: _length,
                        ),
                      )
                    else if (_photo != null)
                      Image.file(File(_photo!.path), fit: BoxFit.cover)
                    else
                      const ColoredBox(color: Color(0xFF151116)),
                    if (!_demo)
                      CustomPaint(
                        painter: NailOverlayPainter(
                          points: _points,
                          color: _color,
                          shape: _shape,
                          length: _length,
                          calibration: _points.length < 5,
                        ),
                      ),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: _chip(_demo ? 'STUDIO DEMO' : 'SAJÁT KÉZ'),
                    ),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: _chip('$_shape · $_match%'),
                    ),
                    if (_demo)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xCC171217),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: .08)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEBA6B4),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2C171D), size: 18),
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Élő stíluspróba', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                    SizedBox(height: 2),
                                    Text('Válts formát, színt és hosszt lent.', style: TextStyle(color: Color(0xFFAFA5AC), fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_demo && _points.length < 5)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xDC171217),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white.withValues(alpha: .09)),
                          ),
                          child: Text(
                            'Koppints a ${['hüvelyk', 'mutató', 'középső', 'gyűrűs', 'kisujj'][_points.length]} köröm közepére',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xB8171217),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .25),
        ),
      );

  Widget _sourceButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded, size: 19),
                label: const Text('Saját kéz fotózása'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEBA6B4),
                  foregroundColor: const Color(0xFF251318),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 56,
              height: 54,
              child: OutlinedButton(
                onPressed: () => _pick(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: Colors.white.withValues(alpha: .12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: const Icon(Icons.photo_library_outlined, size: 21),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _useDemo,
              icon: const Icon(Icons.auto_awesome_rounded, size: 17),
              label: const Text('Demó visszaállítása'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFBDB3BA)),
            ),
            if (!_demo) ...[
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () => setState(_points.clear),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Újrajelölés'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _shapeSelector() {
    const shapes = ['Mandula', 'Ovális', 'Kocka', 'Coffin', 'Stiletto'];
    return _section(
      'Forma',
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: shapes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final shape = shapes[index];
            final selected = _shape == shape;
            return ChoiceChip(
              selected: selected,
              label: Text(shape),
              onSelected: (_) => setState(() => _shape = shape),
              selectedColor: const Color(0xFF3B292F),
              backgroundColor: const Color(0xFF171217),
              checkmarkColor: const Color(0xFFEBA6B4),
              labelStyle: TextStyle(
                color: selected ? const Color(0xFFF7E8ED) : const Color(0xFFAAA0A7),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
              side: BorderSide(
                color: selected ? const Color(0xFF8D626C) : Colors.white.withValues(alpha: .08),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            );
          },
        ),
      ),
    );
  }

  Widget _colorSelector() {
    return _section(
      'Árnyalat',
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _colors.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final c = _colors[i];
            final selected = c.toARGB32() == _color.toARGB32();
            return GestureDetector(
              onTap: () => setState(() => _color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? const Color(0xFFF4EAE8) : Colors.white.withValues(alpha: .18),
                    width: selected ? 3 : 1,
                  ),
                  boxShadow: selected
                      ? const [BoxShadow(color: Color(0x558F5865), blurRadius: 12, spreadRadius: 1)]
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _lengthSelector() {
    return _section(
      'Hossz',
      Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF171217),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFEBA6B4),
                inactiveTrackColor: const Color(0xFF3A3035),
                thumbColor: const Color(0xFFF6E8E6),
                overlayColor: const Color(0x33EBA6B4),
                trackHeight: 3,
              ),
              child: Slider(
                value: _length,
                min: .75,
                max: 1.45,
                divisions: 14,
                onChanged: (v) => setState(() => _length = v),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Természetes', style: TextStyle(fontSize: 10, color: Color(0xFF948A91))),
                  Text('Extra hosszú', style: TextStyle(fontSize: 10, color: Color(0xFF948A91))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchCard() {
    final label = _match >= 94
        ? 'Kiemelkedő összhang'
        : _match >= 90
            ? 'Nagyon jó választás'
            : 'Karakteres választás';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241A1F), Color(0xFF151115)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEBA6B4).withValues(alpha: .13),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEBA6B4), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nail Match', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('$label · $_shape', style: const TextStyle(color: Color(0xFF9F949B), fontSize: 11)),
              ],
            ),
          ),
          Text(
            '$_match%',
            style: const TextStyle(color: Color(0xFFEBC6A6), fontSize: 27, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -.1),
          ),
        ),
        child,
      ],
    );
  }
}

class NailOverlayPainter extends CustomPainter {
  NailOverlayPainter({
    required this.points,
    required this.color,
    required this.shape,
    required this.length,
    required this.calibration,
  });

  final List<Offset> points;
  final Color color;
  final String shape;
  final double length;
  final bool calibration;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (calibration) {
        final halo = Paint()
          ..color = const Color(0xFFEBA6B4).withValues(alpha: .28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
        canvas.drawCircle(p, 17, halo);
        final marker = Paint()..color = const Color(0xFFEBA6B4);
        canvas.drawCircle(p, 10, marker);
        _drawNumber(canvas, p, i + 1);
      } else {
        final widths = [0.078, 0.061, 0.064, 0.060, 0.052];
        _drawNail(canvas, p, size.width * widths[i], color, shape, length, i);
      }
    }
  }

  void _drawNumber(Canvas canvas, Offset p, int n) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: const TextStyle(color: Color(0xFF2A171D), fontSize: 10, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant NailOverlayPainter oldDelegate) => true;
}

class DemoHandPainter extends CustomPainter {
  DemoHandPainter({required this.color, required this.shape, required this.length});

  final Color color;
  final String shape;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    _paintHand(canvas, size);
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF684853), Color(0xFF32242B), Color(0xFF171217)],
        stops: [0, .48, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final glowA = Paint()
      ..color = const Color(0xFFE9B6B7).withValues(alpha: .20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55);
    canvas.drawCircle(Offset(size.width * .18, size.height * .16), size.width * .28, glowA);

    final glowB = Paint()
      ..color = const Color(0xFFB98D78).withValues(alpha: .15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 62);
    canvas.drawCircle(Offset(size.width * .88, size.height * .70), size.width * .36, glowB);

    final silk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .035
      ..color = Colors.white.withValues(alpha: .025)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    final silkPath = Path()
      ..moveTo(-size.width * .1, size.height * .78)
      ..cubicTo(size.width * .22, size.height * .58, size.width * .55, size.height * .92, size.width * 1.08, size.height * .62);
    canvas.drawPath(silkPath, silk);
  }

  void _paintHand(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    canvas.save();
    canvas.translate(size.width * .018, size.height * .022);
    _drawHandMass(canvas, size, shadowPaint, shadowOnly: true);
    canvas.restore();

    final skinRect = Rect.fromLTWH(size.width * .18, size.height * .08, size.width * .66, size.height * .92);
    final skinPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0B89E), Color(0xFFD69478), Color(0xFFB9705C)],
        stops: [0, .58, 1],
      ).createShader(skinRect);
    _drawHandMass(canvas, size, skinPaint, shadowOnly: false);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF7D4438).withValues(alpha: .24);
    _drawHandMass(canvas, size, edge, shadowOnly: false, outlineOnly: true);

    _drawSkinDetails(canvas, size);

    final points = <Offset>[
      Offset(size.width * .247, size.height * .485),
      Offset(size.width * .358, size.height * .226),
      Offset(size.width * .490, size.height * .153),
      Offset(size.width * .620, size.height * .205),
      Offset(size.width * .735, size.height * .302),
    ];
    final widths = [0.074, 0.057, 0.061, 0.057, 0.049];
    for (var i = 0; i < 5; i++) {
      _drawNail(canvas, points[i], size.width * widths[i], color, shape, length, i);
    }
  }

  void _drawHandMass(
    Canvas canvas,
    Size size,
    Paint paint, {
    required bool shadowOnly,
    bool outlineOnly = false,
  }) {
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

    if (!outlineOnly) {
      finger(.355, .365, .115, .405, -.035);
      finger(.490, .319, .118, .500, 0);
      finger(.620, .356, .110, .444, .025);
      finger(.735, .420, .099, .352, .055);
      finger(.241, .568, .112, .315, -.73);
    } else {
      finger(.355, .365, .115, .405, -.035);
      finger(.490, .319, .118, .500, 0);
      finger(.620, .356, .110, .444, .025);
      finger(.735, .420, .099, .352, .055);
      finger(.241, .568, .112, .315, -.73);
    }

    final palm = Path()
      ..moveTo(size.width * .294, size.height * .443)
      ..cubicTo(size.width * .36, size.height * .399, size.width * .68, size.height * .405, size.width * .755, size.height * .492)
      ..cubicTo(size.width * .798, size.height * .574, size.width * .744, size.height * .806, size.width * .662, size.height * .875)
      ..cubicTo(size.width * .586, size.height * .938, size.width * .414, size.height * .934, size.width * .338, size.height * .854)
      ..cubicTo(size.width * .273, size.height * .785, size.width * .251, size.height * .563, size.width * .294, size.height * .443)
      ..close();
    canvas.drawPath(palm, paint);

    final wrist = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .365, size.height * .805, size.width * .31, size.height * .26),
      Radius.circular(size.width * .12),
    );
    canvas.drawRRect(wrist, paint);
  }

  void _drawSkinDetails(Canvas canvas, Size size) {
    final blush = Paint()
      ..color = const Color(0xFF8B4C40).withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .54, size.height * .58),
        width: size.width * .38,
        height: size.height * .20,
      ),
      blush,
    );

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: .12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .405, size.height * .44, size.width * .09, size.height * .36),
        Radius.circular(size.width * .04),
      ),
      highlight,
    );

    final creasePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF834F45).withValues(alpha: .22);

    final crease1 = Path()
      ..moveTo(size.width * .33, size.height * .64)
      ..cubicTo(size.width * .42, size.height * .59, size.width * .52, size.height * .60, size.width * .63, size.height * .66);
    canvas.drawPath(crease1, creasePaint);

    final crease2 = Path()
      ..moveTo(size.width * .36, size.height * .73)
      ..cubicTo(size.width * .44, size.height * .70, size.width * .52, size.height * .70, size.width * .59, size.height * .74);
    canvas.drawPath(crease2, creasePaint);

    final knuckle = Paint()
      ..color = const Color(0xFF7D4438).withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final p in [
      Offset(.355, .435),
      Offset(.49, .435),
      Offset(.62, .45),
      Offset(.735, .485),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * p.dx, size.height * p.dy),
          width: size.width * .07,
          height: size.height * .035,
        ),
        knuckle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DemoHandPainter oldDelegate) => true;
}

void _drawNail(
  Canvas canvas,
  Offset center,
  double width,
  Color color,
  String shape,
  double length,
  int index,
) {
  final height = width * (1.55 + (length - 1) * 1.25);
  final rotations = [-.70, -.04, 0.0, .035, .075];
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotations[index]);

  final path = _nailPath(width, height, shape);

  final cuticleShadow = Paint()
    ..color = const Color(0xFF6D3D35).withValues(alpha: .35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
  canvas.save();
  canvas.translate(0, height * .115);
  canvas.scale(1.10, .45);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: width * .95, height: width * .48),
    cuticleShadow,
  );
  canvas.restore();

  canvas.drawShadow(path, Colors.black.withValues(alpha: .70), 5, false);

  final polishRect = Rect.fromLTWH(-width / 2, -height, width, height * 1.22);
  final polish = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.white, .20)!,
        color,
        Color.lerp(color, Colors.black, .14)!,
      ],
      stops: const [0, .50, 1],
    ).createShader(polishRect);
  canvas.drawPath(path, polish);

  canvas.save();
  canvas.clipPath(path);

  final sideShade = Paint()
    ..shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.black.withValues(alpha: .10),
        Colors.transparent,
        Colors.white.withValues(alpha: .10),
      ],
      stops: const [0, .52, 1],
    ).createShader(polishRect);
  canvas.drawRect(polishRect, sideShade);

  final gloss = Paint()
    ..color = Colors.white.withValues(alpha: .26)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
  final glossPath = Path()
    ..moveTo(-width * .18, -height * .66)
    ..cubicTo(-width * .28, -height * .38, -width * .22, -height * .08, -width * .10, height * .02);
  canvas.drawPath(
    glossPath,
    gloss
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, width * .075)
      ..strokeCap = StrokeCap.round,
  );

  final micro = Paint()
    ..color = Colors.white.withValues(alpha: .16)
    ..style = PaintingStyle.stroke
    ..strokeWidth = .7;
  canvas.drawArc(
    Rect.fromLTRB(-width * .36, -height * .72, width * .36, -height * .18),
    3.65,
    2.1,
    false,
    micro,
  );
  canvas.restore();

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..color = Colors.white.withValues(alpha: .16),
  );
  canvas.restore();
}

Path _nailPath(double w, double h, String shape) {
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
