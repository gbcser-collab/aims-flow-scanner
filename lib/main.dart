import 'dart:io';

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
    const pink = Color(0xFFFF6FB3);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAILFIT',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: pink, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0D0910),
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
  Color _color = const Color(0xFFD9AAA4);
  double _length = 1.0;
  bool _demo = true;

  static const _colors = <Color>[
    Color(0xFFD9AAA4),
    Color(0xFFF2D8D3),
    Color(0xFFB84A68),
    Color(0xFF8E1739),
    Color(0xFF171317),
    Color(0xFFF4F0EE),
    Color(0xFFA894BF),
    Color(0xFF7F947A),
    Color(0xFFB98443),
    Color(0xFF8DBED5),
  ];

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
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
      'Mandula' => 96,
      'Ovális' => 94,
      'Kocka' => 89,
      'Coffin' => 92,
      _ => 87,
    };
    return (base - ((_length - 1).abs() * 13)).round().clamp(78, 98);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _header(),
                  const SizedBox(height: 18),
                  _preview(),
                  const SizedBox(height: 16),
                  _sourceButtons(),
                  const SizedBox(height: 20),
                  _shapeSelector(),
                  const SizedBox(height: 18),
                  _colorSelector(),
                  const SizedBox(height: 18),
                  _lengthSelector(),
                  const SizedBox(height: 18),
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
            const Text('NAIL', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 17)),
            const Text('FIT', style: TextStyle(color: Color(0xFFFF6FB3), fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 17)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text('MVP 0.5', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Próbáld fel.\nMielőtt elkészül.',
          style: TextStyle(fontSize: 39, height: .98, fontWeight: FontWeight.w900, letterSpacing: -1.8),
        ),
        const SizedBox(height: 10),
        Text(
          _demo
              ? 'A demó azonnal működik. Utána fotózd le a saját kezed, és jelöld meg az öt körmöt.'
              : _points.length < 5
                  ? 'Érintsd meg sorban az öt köröm közepét. ${_points.length}/5 kész.'
                  : 'Kész. Most válts formát, színt és hosszt a saját kezeden.',
          style: const TextStyle(color: Colors.white60, height: 1.45, fontSize: 14),
        ),
      ],
    );
  }

  Widget _preview() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF17111C),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 30, offset: Offset(0, 16))],
      ),
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 3 / 4,
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
                      const ColoredBox(color: Color(0xFF120E15)),
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
                      left: 12,
                      top: 12,
                      child: _chip(_demo ? 'DEMO KÉZ' : 'SAJÁT KÉZ'),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: _chip('$_shape · $_match%'),
                    ),
                    if (!_demo && _points.length < 5)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.70),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            'Koppints a ${['hüvelyk', 'mutató', 'középső', 'gyűrűs', 'kisujj'][_points.length]} köröm közepére',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
          color: Colors.black.withOpacity(.62),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _sourceButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Fotózás'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FB3),
                  foregroundColor: const Color(0xFF27101D),
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Galéria'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _useDemo,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Demó kéz'),
              ),
            ),
            if (!_demo)
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(_points.clear),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Újrajelölés'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _shapeSelector() {
    const shapes = ['Mandula', 'Ovális', 'Kocka', 'Coffin', 'Stiletto'];
    return _section(
      'Körömforma',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: shapes.map((shape) {
          final selected = _shape == shape;
          return ChoiceChip(
            selected: selected,
            label: Text(shape),
            onSelected: (_) => setState(() => _shape = shape),
            selectedColor: const Color(0xFF4B2940),
            side: BorderSide(color: selected ? const Color(0xFFFF8FC5) : Colors.white12),
          );
        }).toList(),
      ),
    );
  }

  Widget _colorSelector() {
    return _section(
      'Szín',
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _colors.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final c = _colors[i];
            final selected = c.value == _color.value;
            return GestureDetector(
              onTap: () => setState(() => _color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
                  boxShadow: selected ? const [BoxShadow(color: Color(0x66FF6FB3), blurRadius: 10)] : null,
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
      Column(
        children: [
          Slider(
            value: _length,
            min: .75,
            max: 1.45,
            divisions: 14,
            onChanged: (v) => setState(() => _length = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Természetes', style: TextStyle(fontSize: 11, color: Colors.white54)),
              Text('Extra hosszú', style: TextStyle(fontSize: 11, color: Colors.white54)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _matchCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF211727), Color(0xFF17111C)]),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nail Match', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  'A $_shape forma ezzel a hosszal ${_match >= 94 ? 'nagyon harmonikus' : _match >= 90 ? 'kiegyensúlyozott' : 'karakteres'} összhatást ad.',
                  style: const TextStyle(color: Colors.white60, height: 1.4, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text('$_match%', style: const TextStyle(color: Color(0xFF76E4B3), fontSize: 30, fontWeight: FontWeight.w900)),
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
          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
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
        final marker = Paint()..color = const Color(0xFFFF6FB3);
        canvas.drawCircle(p, 11, marker);
        _drawNumber(canvas, p, i + 1);
      } else {
        final widths = [0.078, 0.061, 0.064, 0.060, 0.052];
        _drawNail(canvas, p, size.width * widths[i], color, shape, length, i);
      }
    }
  }

  void _drawNumber(Canvas canvas, Offset p, int n) {
    final tp = TextPainter(
      text: TextSpan(text: '$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
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
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A1A2F), Color(0xFF0E0B11)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final skin = Paint()..color = const Color(0xFFD9A084);
    final palm = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .28, size.height * .42, size.width * .47, size.height * .50),
      Radius.circular(size.width * .16),
    );
    canvas.drawRRect(palm, skin);

    final fingerData = <List<double>>[
      [.31, .15, .105, .47],
      [.435, .08, .11, .54],
      [.56, .11, .108, .51],
      [.675, .18, .095, .43],
    ];
    for (final f in fingerData) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * f[0], size.height * f[1], size.width * f[2], size.height * f[3]),
          Radius.circular(size.width * .05),
        ),
        skin,
      );
    }
    canvas.save();
    canvas.translate(size.width * .255, size.height * .51);
    canvas.rotate(-.65);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size.width * .11, height: size.height * .34),
        Radius.circular(size.width * .055),
      ),
      skin,
    );
    canvas.restore();

    final points = <Offset>[
      Offset(size.width * .18, size.height * .46),
      Offset(size.width * .362, size.height * .235),
      Offset(size.width * .49, size.height * .19),
      Offset(size.width * .615, size.height * .24),
      Offset(size.width * .735, size.height * .32),
    ];
    final widths = [0.076, 0.059, 0.062, 0.058, 0.050];
    for (var i = 0; i < 5; i++) {
      _drawNail(canvas, points[i], size.width * widths[i], color, shape, length, i);
    }
  }

  @override
  bool shouldRepaint(covariant DemoHandPainter oldDelegate) => true;
}

void _drawNail(Canvas canvas, Offset center, double width, Color color, String shape, double length, int index) {
  final height = width * (1.55 + (length - 1) * 1.25);
  final rotations = [-.70, -.10, 0.0, .10, .23];
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotations[index]);

  final path = _nailPath(width, height, shape);
  canvas.drawShadow(path, Colors.black87, 4, false);
  canvas.drawPath(path, Paint()..color = color);

  final highlight = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.white.withOpacity(.48), Colors.white.withOpacity(.03)],
    ).createShader(Rect.fromLTWH(-width / 2, -height, width, height * 1.2));
  canvas.save();
  canvas.clipPath(path);
  canvas.drawRect(Rect.fromLTWH(-width / 2, -height, width, height * 1.2), highlight);
  canvas.restore();

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white24,
  );
  canvas.restore();
}

Path _nailPath(double w, double h, String shape) {
  final path = Path();
  final top = -h * .80;
  final bottom = h * .18;

  switch (shape) {
    case 'Kocka':
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(-w / 2, top, w / 2, bottom),
        Radius.circular(w * .12),
      ));
      break;
    case 'Coffin':
      path
        ..moveTo(-w * .28, top)
        ..lineTo(w * .28, top)
        ..lineTo(w * .50, bottom)
        ..quadraticBezierTo(0, bottom + h * .05, -w * .50, bottom)
        ..close();
      break;
    case 'Stiletto':
      path
        ..moveTo(0, top - h * .16)
        ..cubicTo(w * .42, top + h * .18, w * .52, -h * .05, w * .48, bottom)
        ..quadraticBezierTo(0, bottom + h * .05, -w * .48, bottom)
        ..cubicTo(-w * .52, -h * .05, -w * .42, top + h * .18, 0, top - h * .16)
        ..close();
      break;
    case 'Ovális':
      path.addOval(Rect.fromLTRB(-w / 2, top, w / 2, bottom));
      break;
    default:
      path
        ..moveTo(0, top)
        ..cubicTo(w * .28, top + h * .03, w * .51, -h * .08, w * .49, bottom)
        ..quadraticBezierTo(0, bottom + h * .05, -w * .49, bottom)
        ..cubicTo(-w * .51, -h * .08, -w * .28, top + h * .03, 0, top)
        ..close();
  }
  return path;
}
