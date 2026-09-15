import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'nailfit_painters.dart';

const ink = Color(0xFF24191B);
const muted = Color(0xFF806F71);
const rose = Color(0xFFC8667A);
const roseDark = Color(0xFFA94E63);
const cream = Color(0xFFFFF9F6);
const line = Color(0xFFEEDCDD);

class NailFitApp extends StatelessWidget {
  const NailFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAILFIT',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(seedColor: rose, brightness: Brightness.light),
      ),
      home: const NailFitHome(),
    );
  }
}

class NailLook {
  const NailLook(this.name, this.shape, this.color, this.finish, this.length, this.match, this.category);
  final String name;
  final String shape;
  final Color color;
  final NailFinish finish;
  final double length;
  final int match;
  final String category;
}

const looks = <NailLook>[
  NailLook('Rózsás nude', 'Mandula', Color(0xFFD99CA6), NailFinish.glossy, .98, 96, 'Nude'),
  NailLook('Francia klasszikus', 'Mandula', Color(0xFFE7B8B1), NailFinish.french, .92, 95, 'Francia'),
  NailLook('Finom csillogás', 'Ovális', Color(0xFFD98A9C), NailFinish.glitter, 1.04, 93, 'Merész'),
  NailLook('Őszi elegancia', 'Mandula', Color(0xFF681A2B), NailFinish.glossy, 1.02, 91, 'Őszi'),
  NailLook('Letisztult bézs', 'Kocka', Color(0xFFC7A18F), NailFinish.glossy, .82, 90, 'Minimal'),
  NailLook('Rose chrome', 'Coffin', Color(0xFFB96A78), NailFinish.chrome, 1.18, 88, 'Merész'),
];

class NailFitHome extends StatefulWidget {
  const NailFitHome({super.key});

  @override
  State<NailFitHome> createState() => _NailFitHomeState();
}

class _NailFitHomeState extends State<NailFitHome> {
  final _picker = ImagePicker();
  final _previewKey = GlobalKey();
  final _points = <Offset>[];
  final _favorites = <String>{};
  final _saved = <NailLook>[];

  int _tab = 0;
  XFile? _photo;
  NailLook _look = looks.first;
  bool _saving = false;
  String _category = 'Minimal';

  String get _favKey => '${_look.name}-${_look.shape}-${_look.finish.name}';
  bool get _favorite => _favorites.contains(_favKey);

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90, maxWidth: 2200);
    if (!mounted || file == null) return;
    setState(() {
      _photo = file;
      _points.clear();
      _tab = 1;
    });
  }

  void _select(NailLook look, {bool tryOn = true}) {
    setState(() {
      _look = look;
      if (tryOn) _tab = 2;
    });
  }

  void _toggleFavorite() {
    setState(() {
      _favorite ? _favorites.remove(_favKey) : _favorites.add(_favKey);
    });
    _message(_favorite ? 'Kedvencekhez adva.' : 'Eltávolítva a kedvencekből.');
  }

  void _addPoint(Offset local, Size size) {
    if (_photo == null || _points.length >= 5) return;
    setState(() => _points.add(Offset(local.dx / size.width, local.dy / size.height)));
  }

  void _analyze() {
    if (_photo != null && _points.isEmpty) {
      setState(() {
        _points.addAll(const [Offset(.79, .57), Offset(.30, .27), Offset(.45, .18), Offset(.60, .24), Offset(.72, .34)]);
      });
      _message('Vizuális körömpont-becslés alkalmazva.');
    }
    setState(() => _tab = 2);
  }

  Future<void> _savePng() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('preview');
      final image = await boundary.toImage(pixelRatio: 2.2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('png');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/nailfit_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      setState(() => _saved.insert(0, _look));
      _message('Look elmentve PNG-ként.');
    } catch (_) {
      if (mounted) _message('A PNG mentés most nem sikerült.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _activeScreen()),
      bottomNavigationBar: _nav(),
    );
  }

  Widget _activeScreen() => switch (_tab) {
        0 => _home(),
        1 => _scan(),
        2 => _tryOn(),
        3 => _savedScreen(),
        _ => _profile(),
      };

  Widget _scroll(List<Widget> children) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFFCF9), Color(0xFFFFF0ED), Color(0xFFFFFAF7)]),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _nav() {
    const nav = [
      (Icons.home_outlined, Icons.home_rounded, 'Főoldal'),
      (Icons.camera_alt_outlined, Icons.camera_alt_rounded, 'Scan'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Try-On'),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Mentett'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 5, 14, 9),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
          boxShadow: const [BoxShadow(color: Color(0x1FB17A85), blurRadius: 24, offset: Offset(0, 9))],
        ),
        child: Row(
          children: List.generate(nav.length, (i) {
            final active = _tab == i;
            return Expanded(
              child: InkWell(
                key: ValueKey('nav-$i'),
                borderRadius: BorderRadius.circular(22),
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: active ? const Color(0xFFFBE3E7) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(active ? nav[i].$2 : nav[i].$1, color: active ? roseDark : const Color(0xFF485257), size: 23),
                      const SizedBox(height: 2),
                      Text(nav[i].$3, style: TextStyle(fontSize: 10, color: active ? roseDark : const Color(0xFF485257), fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
                      SizedBox(height: 4, child: active ? const Center(child: CircleAvatar(radius: 2.5, backgroundColor: roseDark)) : null),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _header({bool compact = false}) {
    return Row(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('NAIL', style: TextStyle(fontSize: 21, letterSpacing: 4, color: ink, fontWeight: FontWeight.w500)),
            Text('FIT', style: TextStyle(fontSize: 21, letterSpacing: 4, color: rose, fontWeight: FontWeight.w500)),
          ]),
          if (!compact) const Text('B E A U T Y   M E E T S   Y O U', style: TextStyle(fontSize: 6.5, letterSpacing: 1.1, color: muted)),
        ]),
        const Spacer(),
        InkWell(
          onTap: _stylist,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFBE7EA), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_rounded, size: 14, color: rose), SizedBox(width: 5), Text('BEAUTY AI', style: TextStyle(fontSize: 8.7, letterSpacing: 1.2, color: roseDark, fontWeight: FontWeight.w800))]),
          ),
        ),
        const SizedBox(width: 7),
        Container(width: 37, height: 37, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .78), shape: BoxShape.circle), child: const Icon(Icons.notifications_none_rounded, color: ink, size: 20)),
      ],
    );
  }

  Widget _home() => _scroll([
        _header(),
        const SizedBox(height: 18),
        _hero(),
        const SizedBox(height: 24),
        _title('Neked ajánljuk', 'Összes megtekintése'),
        const SizedBox(height: 10),
        _lookList(looks.take(5).toList(), 142),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _quick(Icons.favorite_border_rounded, 'Kedvencek', 'Mentett stílusaid', () => setState(() => _tab = 3))),
          const SizedBox(width: 8),
          Expanded(child: _quick(Icons.bookmark_border_rounded, 'Look mentése', 'Kedvenc szetted', () => setState(() => _tab = 2))),
          const SizedBox(width: 8),
          Expanded(child: _quick(Icons.person_outline_rounded, 'Stílusprofil', 'Ajánlásaid', () => setState(() => _tab = 4))),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: 202,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: _matchCard()),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _season()),
          ]),
        ),
        const SizedBox(height: 23),
        _title('Stílusok böngészése', 'Összes kategória'),
        const SizedBox(height: 9),
        _categories(),
        const SizedBox(height: 18),
        _aiCard(),
        const SizedBox(height: 12),
        _outfitCard(),
      ]);

  Widget _hero() {
    return LayoutBuilder(builder: (_, c) {
      final compact = c.maxWidth < 390;
      return Container(
        height: compact ? 255 : 280,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.3), boxShadow: const [BoxShadow(color: Color(0x1A9C6872), blurRadius: 24, offset: Offset(0, 11))]),
        child: Row(children: [
          Expanded(
            flex: 10,
            child: Container(
              padding: EdgeInsets.fromLTRB(compact ? 14 : 19, 20, 8, 15),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFECE7), Color(0xFFF5D7D4)])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('T A L Á L D   M E G', style: TextStyle(color: roseDark, fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text('a hozzád illő\nkörmöket.', style: TextStyle(fontFamily: 'serif', color: ink, fontSize: compact ? 27 : 32, height: .94)),
                const SizedBox(height: 10),
                Text('Forma, árnyalat és stílus — még a szalon előtt.', style: TextStyle(color: muted, fontSize: compact ? 9.5 : 10.7, height: 1.3)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('hero-camera'),
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: const Text('Készíts fotót'),
                    style: FilledButton.styleFrom(backgroundColor: rose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            flex: 11,
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: DemoHandPainter(color: _look.color, shape: _look.shape, length: _look.length, finish: _look.finish)),
              Positioned(right: 10, top: 16, child: Text('Your\nNails\nYour Story ♡', textAlign: TextAlign.right, style: TextStyle(color: Colors.white.withValues(alpha: .90), fontFamily: 'serif', fontStyle: FontStyle.italic, fontSize: 13, height: 1.02))),
            ]),
          ),
        ]),
      );
    });
  }

  Widget _scan() => _scroll([
        _header(compact: true),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Kéz szkennelése', style: TextStyle(fontFamily: 'serif', fontSize: 36, height: 1, color: ink)), SizedBox(height: 7), Text('Igazítsd a kezed a kerethez, és készíts egy éles fotót.', style: TextStyle(color: muted, fontSize: 12, height: 1.35))])),
          const SizedBox(width: 12),
          SizedBox(width: 82, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text('1 / 3', style: TextStyle(color: roseDark, fontWeight: FontWeight.w800, fontSize: 12)), const SizedBox(height: 6), ClipRRect(borderRadius: BorderRadius.circular(99), child: const LinearProgressIndicator(value: .34, minHeight: 5, color: rose, backgroundColor: line)), const SizedBox(height: 5), const Text('KÉZ ELEMZÉSE', style: TextStyle(color: muted, fontSize: 7.5, letterSpacing: .9))])),
        ]),
        const SizedBox(height: 15),
        _scanPreview(),
        const SizedBox(height: 14),
        _features(),
        const SizedBox(height: 11),
        _scanInsight(),
        const SizedBox(height: 20),
        _title('Ajánlott stílusok neked', 'Összes'),
        const SizedBox(height: 9),
        _lookList(looks.take(3).toList(), 136),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _primary(Icons.auto_awesome_rounded, 'Elemzés indítása', _analyze)),
          const SizedBox(width: 8),
          Expanded(child: _secondary(Icons.camera_alt_outlined, 'Fotó újra', () => _pick(ImageSource.camera))),
        ]),
      ]);

  Widget _scanPreview() {
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(27), border: Border.all(color: Colors.white, width: 1.4), boxShadow: const [BoxShadow(color: Color(0x1B90636B), blurRadius: 22, offset: Offset(0, 10))]),
      child: LayoutBuilder(builder: (_, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onTapDown: (e) => _addPoint(e.localPosition, size),
          child: Stack(fit: StackFit.expand, children: [
            if (_photo != null) Image.file(File(_photo!.path), fit: BoxFit.cover) else CustomPaint(painter: DemoHandPainter(color: const Color(0xFFD6A1A2), shape: 'Ovális', length: .84, finish: NailFinish.glossy, scanPose: true)),
            const CustomPaint(painter: ScanOverlayPainter(complete: true)),
            if (_photo != null) CustomPaint(painter: NailOverlayPainter(points: _points, color: _look.color, shape: _look.shape, length: _look.length, finish: _look.finish, calibration: _points.length < 5)),
            Positioned(left: 15, right: 15, top: 15, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: const Color(0x71352A28), borderRadius: BorderRadius.circular(99)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16), const SizedBox(width: 7), Flexible(child: Text(_photo == null ? 'Igazítsd a kezed a kerethez' : (_points.length < 5 ? 'Koppints az 5 körömre · ${_points.length}/5' : 'Körmök kijelölve'), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)))]))),
          ]),
        );
      }),
    );
  }

  Widget _tryOn() => _scroll([
        _header(compact: true),
        const SizedBox(height: 15),
        Row(children: [
          Container(width: 42, height: 42, decoration: const BoxDecoration(color: Color(0xFFFBE4E7), shape: BoxShape.circle), child: IconButton(onPressed: () => setState(() => _tab = 1), icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 20))),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('VIRTUÁLIS PRÓBA', style: TextStyle(color: roseDark, fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w800)), SizedBox(height: 2), Text('Próbáld fel', style: TextStyle(fontFamily: 'serif', fontSize: 39, color: ink, height: 1)), SizedBox(height: 4), Text('Nézd meg, hogyan áll rajtad.', style: TextStyle(color: muted, fontSize: 11.5))])),
          InkWell(onTap: () => _pick(ImageSource.camera), borderRadius: BorderRadius.circular(99), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFBE3E7), borderRadius: BorderRadius.circular(99)), child: const Icon(Icons.camera_alt_rounded, color: roseDark, size: 20))),
        ]),
        const SizedBox(height: 15),
        RepaintBoundary(key: _previewKey, child: _tryPreview()),
        const SizedBox(height: 19),
        _title('További stílusok kipróbálása', 'Összes stílus'),
        const SizedBox(height: 9),
        _lookList(looks, 140),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _action(_favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, _favorite ? 'Kedvenc' : 'Kedvencekhez', _toggleFavorite)),
          const SizedBox(width: 7),
          Expanded(child: _action(Icons.bookmark_border_rounded, _saving ? 'Mentés…' : 'Look mentése', _savePng)),
          const SizedBox(width: 7),
          Expanded(child: _action(Icons.ios_share_rounded, 'Megosztás', () => _message('Megosztási modul: következő bekötés.'))),
        ]),
        const SizedBox(height: 17),
        _tune(),
        const SizedBox(height: 17),
        _booking(),
      ]);

  Widget _tryPreview() {
    return Container(
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.4), boxShadow: const [BoxShadow(color: Color(0x20966973), blurRadius: 25, offset: Offset(0, 12))]),
      child: LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth;
        return Stack(fit: StackFit.expand, children: [
          if (_photo != null) Image.file(File(_photo!.path), fit: BoxFit.cover) else CustomPaint(painter: DemoHandPainter(color: _look.color, shape: _look.shape, length: _look.length, finish: _look.finish)),
          if (_photo != null) CustomPaint(painter: NailOverlayPainter(points: _points, color: _look.color, shape: _look.shape, length: _look.length, finish: _look.finish, calibration: _points.length < 5)),
          Positioned(left: 13, top: 13, child: _darkChip(_photo == null ? 'STUDIO DEMO' : 'SAJÁT KÉZ')),
          Positioned(right: 13, top: 13, child: InkWell(onTap: _toggleFavorite, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .90), shape: BoxShape.circle), child: Icon(_favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: roseDark, size: 21)))),
          Positioned(left: 13, bottom: 13, child: Container(width: w * .47, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .90), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(_look.name, style: const TextStyle(fontFamily: 'serif', fontSize: 18, fontWeight: FontWeight.w600, color: ink)), const SizedBox(height: 2), Text('${_look.shape} · ${_finishName(_look.finish)}', style: const TextStyle(color: muted, fontSize: 9))]))),
          Positioned(right: 13, bottom: 13, child: Container(width: w * .36, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xF6FBE8EB), borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Row(children: [Icon(Icons.auto_awesome_rounded, color: rose, size: 13), SizedBox(width: 4), Text('AI AJÁNLÁS', style: TextStyle(color: roseDark, fontSize: 7.2, letterSpacing: .8, fontWeight: FontWeight.w800))]), const SizedBox(height: 6), Text('${_look.match}% egyezés', style: const TextStyle(fontFamily: 'serif', fontSize: 20, color: ink, height: 1)), const SizedBox(height: 4), const Text('Illik a kézformádhoz és tónusodhoz.', style: TextStyle(color: muted, fontSize: 8.2, height: 1.2))]))),
        ]);
      }),
    );
  }

  Widget _savedScreen() {
    final fav = looks.where((l) => _favorites.any((k) => k.startsWith('${l.name}-'))).toList();
    final display = fav.isEmpty ? looks.take(3).toList() : fav;
    return _scroll([
      _header(compact: true),
      const SizedBox(height: 17),
      const Text('Mentett lookok', style: TextStyle(fontFamily: 'serif', fontSize: 38, color: ink, height: 1)),
      const SizedBox(height: 6),
      Text('Kedvencek, kollekciók és ${_saved.length} saját PNG mentés.', style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 22),
      _title('Mentett kollekciók', 'Összes kollekció'),
      const SizedBox(height: 9),
      _collections(),
      const SizedBox(height: 23),
      _title('Kedvenc szettjeid', 'Összes megtekintése'),
      const SizedBox(height: 9),
      _lookList(display, 148),
      if (_saved.isNotEmpty) ...[
        const SizedBox(height: 22),
        _title('Saját mentéseid', null),
        const SizedBox(height: 9),
        _lookList(_saved.take(6).toList(), 148),
      ],
      const SizedBox(height: 20),
      _aiCard(),
    ]);
  }

  Widget _profile() => _scroll([
        _header(compact: true),
        const SizedBox(height: 17),
        _profileCard(),
        const SizedBox(height: 23),
        _title('Mentett kollekciók', 'Összes kollekció'),
        const SizedBox(height: 9),
        _collections(),
        const SizedBox(height: 23),
        _title('Kedvenc szettjeid', 'Összes megtekintése'),
        const SizedBox(height: 9),
        _lookList(looks.take(3).toList(), 148),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.65,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _utility(Icons.person_outline_rounded, 'Stílusprofil szerkesztése'),
            _utility(Icons.notifications_none_rounded, 'Értesítések'),
            _utility(Icons.share_outlined, 'Megosztott lookok'),
            _utility(Icons.image_outlined, 'PNG export'),
            _utility(Icons.lock_outline_rounded, 'Adatvédelem'),
            _utility(Icons.help_outline_rounded, 'Súgó és GYIK'),
          ],
        ),
        const SizedBox(height: 18),
        _profileBanner(),
      ]);

  Widget _title(String title, String? trailing) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: Text(title, style: const TextStyle(fontFamily: 'serif', color: ink, fontSize: 24, fontWeight: FontWeight.w600, height: 1))), if (trailing != null) Text('$trailing  →', style: const TextStyle(color: roseDark, fontSize: 10, fontWeight: FontWeight.w800))]);

  Widget _lookList(List<NailLook> data, double height) => SizedBox(height: height, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: data.length, separatorBuilder: (_, __) => const SizedBox(width: 9), itemBuilder: (_, i) => _lookCard(data[i])));

  Widget _lookCard(NailLook item) {
    final selected = _look.name == item.name;
    return InkWell(
      onTap: () => _select(item),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 142,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .90), borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? rose : Colors.white, width: selected ? 2 : 1), boxShadow: const [BoxShadow(color: Color(0x109E6D76), blurRadius: 12, offset: Offset(0, 6))]),
        child: Column(children: [Expanded(child: CustomPaint(painter: NailSwatchPainter(color: item.color, shape: item.shape, finish: item.finish), child: const SizedBox.expand())), Padding(padding: const EdgeInsets.fromLTRB(9, 7, 9, 8), child: Row(children: [Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ink))), const Icon(Icons.favorite_border_rounded, color: roseDark, size: 16)]))]),
      ),
    );
  }

  BoxDecoration _card({Color? color}) => BoxDecoration(color: color ?? Colors.white.withValues(alpha: .76), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white), boxShadow: const [BoxShadow(color: Color(0x0F9B6B74), blurRadius: 15, offset: Offset(0, 7))]);

  Widget _quick(IconData icon, String title, String sub, VoidCallback tap) => InkWell(onTap: tap, borderRadius: BorderRadius.circular(19), child: Container(height: 80, padding: const EdgeInsets.all(10), decoration: _card(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(icon, color: ink, size: 20), const Spacer(), const Icon(Icons.chevron_right_rounded, color: muted, size: 17)]), const SizedBox(height: 5), Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)), Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.2, color: muted))])));

  Widget _matchCard() => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE8EC), Color(0xFFF4D4D9)]), borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.auto_awesome_rounded, size: 15, color: rose), SizedBox(width: 5), Text('AI AJÁNLÁS NEKED', style: TextStyle(color: roseDark, fontSize: 7.8, letterSpacing: 1, fontWeight: FontWeight.w800))]), const SizedBox(height: 9), Text('${_look.match}% egyezés', style: const TextStyle(fontFamily: 'serif', color: ink, fontSize: 27, height: 1)), const SizedBox(height: 6), const Text('A stílus harmonikusan illik a kézformádhoz és a választott hosszadhoz.', style: TextStyle(color: muted, fontSize: 9.5, height: 1.3)), const Spacer(), FilledButton(onPressed: () => setState(() => _tab = 2), style: FilledButton.styleFrom(backgroundColor: rose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text('Próbáld ki  →', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)))]));

  Widget _season() => InkWell(onTap: () => _select(looks[3]), borderRadius: BorderRadius.circular(23), child: Container(padding: const EdgeInsets.all(13), decoration: _card(color: const Color(0xFFFFF5F0)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.eco_outlined, color: roseDark, size: 23), Spacer(), Text('Új őszi\nkollekció', style: TextStyle(fontFamily: 'serif', fontSize: 21, color: ink, height: .95)), SizedBox(height: 7), Text('Természetes árnyalatok, időtlen elegancia.', style: TextStyle(color: muted, fontSize: 8.8, height: 1.3)), SizedBox(height: 8), Text('Felfedezem  →', style: TextStyle(color: roseDark, fontSize: 9.5, fontWeight: FontWeight.w800))])));

  Widget _categories() {
    const data = [(Icons.diamond_outlined, 'Minimal'), (Icons.waves_rounded, 'Francia'), (Icons.circle, 'Nude'), (Icons.favorite_border_rounded, 'Menyasszony'), (Icons.eco_outlined, 'Őszi'), (Icons.auto_awesome_rounded, 'Merész')];
    return SizedBox(height: 39, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: data.length, separatorBuilder: (_, __) => const SizedBox(width: 7), itemBuilder: (_, i) { final active = _category == data[i].$2; return ChoiceChip(selected: active, avatar: Icon(data[i].$1, size: 14, color: active ? roseDark : muted), label: Text(data[i].$2), onSelected: (_) => setState(() => _category = data[i].$2), selectedColor: const Color(0xFFF7DCE1), backgroundColor: Colors.white.withValues(alpha: .72), side: BorderSide(color: active ? rose.withValues(alpha: .45) : Colors.white), showCheckmark: false, labelStyle: TextStyle(fontSize: 9.5, color: active ? roseDark : ink)); }));
  }

  Widget _aiCard() => InkWell(onTap: _stylist, borderRadius: BorderRadius.circular(23), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFCE4E8), Color(0xFFFFF7F3)]), borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white)), child: const Row(children: [CircleAvatar(radius: 23, backgroundColor: Colors.white, child: Icon(Icons.auto_awesome_rounded, color: rose)), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Beauty AI Stylist', style: TextStyle(fontFamily: 'serif', fontSize: 19, fontWeight: FontWeight.w600, color: ink)), SizedBox(height: 3), Text('Írd le az alkalmat, a ruhád vagy a hangulatod — ajánlunk egy lookot.', style: TextStyle(color: muted, fontSize: 9.8, height: 1.3))])), Icon(Icons.arrow_forward_rounded, color: roseDark)])));

  Widget _outfitCard() => InkWell(onTap: () => _message('Ruhafotó-párosítás: vizuális modul előkészítve.'), borderRadius: BorderRadius.circular(23), child: Container(padding: const EdgeInsets.all(15), decoration: _card(), child: const Row(children: [CircleAvatar(radius: 22, backgroundColor: Color(0xFFF7DCE1), child: Icon(Icons.checkroom_outlined, color: roseDark)), SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Párosítsd a ruhádhoz', style: TextStyle(fontFamily: 'serif', color: ink, fontSize: 18, fontWeight: FontWeight.w600)), SizedBox(height: 2), Text('Tölts fel egy outfit-fotót, és válassz hozzá harmonizáló körmöt.', style: TextStyle(color: muted, fontSize: 9.5))])), Icon(Icons.chevron_right_rounded, color: muted)])));

  Widget _features() {
    const data = [(Icons.circle, 'Bőrtónus', 'Világos, meleg'), (Icons.back_hand_outlined, 'Kézforma', 'Karcsú, hosszúkás'), (Icons.water_drop_outlined, 'Körömágy', 'Közepes, ovális'), (Icons.auto_awesome_rounded, 'Ajánlott forma', 'Mandula')];
    return Container(padding: const EdgeInsets.all(13), decoration: _card(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Felismert jellemzők', style: TextStyle(fontFamily: 'serif', color: ink, fontSize: 21, fontWeight: FontWeight.w600)), const SizedBox(height: 9), ...data.map((x) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9), decoration: BoxDecoration(color: const Color(0xFFFFF8F6), borderRadius: BorderRadius.circular(15)), child: Row(children: [CircleAvatar(radius: 16, backgroundColor: const Color(0xFFF6D8DE), child: Icon(x.$1, size: 16, color: roseDark)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.$2, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)), Text(x.$3, style: const TextStyle(fontSize: 9.3, color: muted))])), const Icon(Icons.chevron_right_rounded, size: 17, color: muted)])))]));
  }

  Widget _scanInsight() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE7EA), Color(0xFFF6D6DB)]), borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white)), child: Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.auto_awesome_rounded, color: rose, size: 15), SizedBox(width: 5), Text('AI ELEMZÉS', style: TextStyle(color: roseDark, fontSize: 8, letterSpacing: 1.1, fontWeight: FontWeight.w800))]), SizedBox(height: 9), Text('Mandula forma ajánlott.', style: TextStyle(fontFamily: 'serif', fontSize: 23, color: ink, height: 1)), SizedBox(height: 6), Text('A kéz arányaihoz harmonikusan illik.', style: TextStyle(color: muted, fontSize: 9.7)), SizedBox(height: 10), Text('Meleg nude árnyalatok jól állnak.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: ink))])), const SizedBox(width: 9), SizedBox(width: 82, height: 105, child: ClipRRect(borderRadius: BorderRadius.circular(17), child: CustomPaint(painter: NailSwatchPainter(color: Color(0xFFD99CA6), shape: 'Mandula', finish: NailFinish.glossy))))]));

  Widget _primary(IconData icon, String label, VoidCallback tap) => FilledButton.icon(onPressed: tap, icon: Icon(icon, size: 18), label: Text(label), style: FilledButton.styleFrom(backgroundColor: rose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)), textStyle: const TextStyle(fontSize: 10.3, fontWeight: FontWeight.w800)));
  Widget _secondary(IconData icon, String label, VoidCallback tap) => OutlinedButton.icon(onPressed: tap, icon: Icon(icon, size: 18), label: Text(label), style: OutlinedButton.styleFrom(foregroundColor: ink, backgroundColor: Colors.white.withValues(alpha: .72), side: const BorderSide(color: Colors.white), padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)), textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)));
  Widget _darkChip(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0x7C382B2A), borderRadius: BorderRadius.circular(99)), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 8.8, fontWeight: FontWeight.w800)));

  Widget _action(IconData icon, String label, VoidCallback tap) => InkWell(onTap: tap, borderRadius: BorderRadius.circular(18), child: Container(height: 60, decoration: _card(), padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: ink, size: 19), const SizedBox(width: 6), Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(color: ink, fontSize: 9.5, fontWeight: FontWeight.w800)))])));

  Widget _tune() {
    const shapeNames = ['Mandula', 'Ovális', 'Kocka', 'Coffin', 'Stiletto'];
    return Container(padding: const EdgeInsets.all(15), decoration: _card(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Finomhangolás', style: TextStyle(fontFamily: 'serif', fontSize: 23, color: ink, fontWeight: FontWeight.w600)),
      const SizedBox(height: 11),
      const Text('Forma', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: shapeNames.map((s) => ChoiceChip(selected: _look.shape == s, label: Text(s), onSelected: (_) => setState(() => _look = NailLook('Saját kombináció', s, _look.color, _look.finish, _look.length, 92, 'Saját')), selectedColor: const Color(0xFFF6DCE0), backgroundColor: const Color(0xFFFFF8F6), side: const BorderSide(color: line), showCheckmark: false, labelStyle: const TextStyle(fontSize: 9.5))).toList()),
      const SizedBox(height: 12),
      const Text('Finish', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: NailFinish.values.map((f) => ChoiceChip(selected: _look.finish == f, label: Text(_finishName(f)), onSelected: (_) => setState(() => _look = NailLook('Saját kombináció', _look.shape, _look.color, f, _look.length, 92, 'Saját')), selectedColor: const Color(0xFFF6DCE0), backgroundColor: const Color(0xFFFFF8F6), side: const BorderSide(color: line), showCheckmark: false, labelStyle: const TextStyle(fontSize: 9.5))).toList()),
      const SizedBox(height: 12),
      const Text('Hossz', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)),
      SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: rose, inactiveTrackColor: line, thumbColor: roseDark, trackHeight: 3), child: Slider(value: _look.length.clamp(.74, 1.42), min: .74, max: 1.42, divisions: 14, onChanged: (v) => setState(() => _look = NailLook('Saját kombináció', _look.shape, _look.color, _look.finish, v, 92, 'Saját')))),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Természetes', style: TextStyle(color: muted, fontSize: 8.5)), Text('Extra hosszú', style: TextStyle(color: muted, fontSize: 8.5))]),
    ]));
  }

  String _finishName(NailFinish f) => switch (f) { NailFinish.glossy => 'Fényes', NailFinish.french => 'Francia', NailFinish.glitter => 'Csillogó', NailFinish.chrome => 'Chrome' };

  Widget _booking() => InkWell(onTap: _salons, borderRadius: BorderRadius.circular(23), child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFBE3E7), Color(0xFFFFF5F1)]), borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white)), child: const Row(children: [CircleAvatar(radius: 23, backgroundColor: Color(0xFFF5CFD6), child: Icon(Icons.calendar_month_outlined, color: roseDark)), SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Időpontfoglalás a szalonban', style: TextStyle(fontFamily: 'serif', fontSize: 18, color: ink, fontWeight: FontWeight.w600)), SizedBox(height: 2), Text('Vidd magaddal a kedvenc stílusod.', style: TextStyle(color: muted, fontSize: 9.5))])), Icon(Icons.chevron_right_rounded, color: muted)])));

  Widget _collections() {
    final data = [('Nude kedvencek', looks[0]), ('Őszi elegancia', looks[3]), ('Csillogó hangulat', looks[2]), ('Francia klasszikus', looks[1])];
    return SizedBox(height: 158, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: data.length, separatorBuilder: (_, __) => const SizedBox(width: 9), itemBuilder: (_, i) => InkWell(onTap: () => _select(data[i].$2), child: Container(width: 155, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white)), child: Column(children: [Expanded(child: CustomPaint(painter: NailSwatchPainter(color: data[i].$2.color, shape: data[i].$2.shape, finish: data[i].$2.finish), child: const SizedBox.expand())), Padding(padding: const EdgeInsets.all(9), child: Row(children: [Expanded(child: Text(data[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w700))), const Icon(Icons.more_vert_rounded, color: roseDark, size: 16)]))])))));
  }

  Widget _profileCard() => Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFEEEB), Color(0xFFF8DFE2)]), borderRadius: BorderRadius.circular(27), border: Border.all(color: Colors.white)), child: Column(children: [
        Row(children: [const CircleAvatar(radius: 39, backgroundColor: Color(0xFFD98D83), child: Icon(Icons.person_rounded, color: Colors.white, size: 44)), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Anna', style: TextStyle(fontFamily: 'serif', fontSize: 30, color: ink, height: 1)), SizedBox(height: 3), Text('Stílusprofil  ›', style: TextStyle(color: muted, fontSize: 11.5))])), const Text('Beautiful\nNails ♡', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'serif', fontStyle: FontStyle.italic, color: roseDark, fontSize: 12))]),
        const SizedBox(height: 14),
        Wrap(spacing: 6, runSpacing: 6, children: const [_ProfileTag(Icons.water_drop_outlined, 'Mandula'), _ProfileTag(Icons.circle, 'Nude'), _ProfileTag(Icons.diamond_outlined, 'Minimal'), _ProfileTag(Icons.eco_outlined, 'Őszi')]),
        const SizedBox(height: 14),
        const Divider(color: line),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: _stat(Icons.bookmark_border_rounded, '${24 + _saved.length}', 'Mentett lookok')), Expanded(child: _stat(Icons.favorite_border_rounded, '${17 + _favorites.length}', 'Kedvencek')), Expanded(child: _stat(Icons.auto_awesome_rounded, '36', 'Próbák'))]),
      ]));

  Widget _stat(IconData icon, String n, String label) => Column(children: [Icon(icon, size: 20, color: ink), const SizedBox(height: 4), Text(n, style: const TextStyle(fontFamily: 'serif', fontSize: 22, color: ink)), Text(label, style: const TextStyle(fontSize: 8.2, color: muted))]);

  Widget _utility(IconData icon, String label) => InkWell(onTap: () => _message('$label · prototípus funkció'), borderRadius: BorderRadius.circular(17), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10), decoration: _card(), child: Row(children: [CircleAvatar(radius: 16, backgroundColor: const Color(0xFFF6D8DD), child: Icon(icon, color: ink, size: 16)), const SizedBox(width: 8), Expanded(child: Text(label, maxLines: 2, style: const TextStyle(color: ink, fontSize: 9.5, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded, color: muted, size: 16)])));

  Widget _profileBanner() => InkWell(onTap: _stylist, borderRadius: BorderRadius.circular(23), child: Container(height: 140, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(23), border: Border.all(color: Colors.white)), child: Row(children: [Expanded(flex: 3, child: Container(padding: const EdgeInsets.all(15), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFCE3E7), Color(0xFFFFF4F0)])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(Icons.auto_awesome_rounded, color: rose, size: 14), SizedBox(width: 5), Text('BEAUTY AI', style: TextStyle(color: roseDark, fontSize: 7.8, letterSpacing: 1, fontWeight: FontWeight.w800))]), SizedBox(height: 7), Text('Személyre szabott ajánlás', style: TextStyle(fontFamily: 'serif', fontSize: 20, color: ink, height: 1)), SizedBox(height: 4), Text('Új stílusok a Te ízlésed alapján.', style: TextStyle(color: muted, fontSize: 8.8))]))), Expanded(flex: 2, child: CustomPaint(painter: DemoHandPainter(color: Color(0xFFD99CA6), shape: 'Mandula', length: .95, finish: NailFinish.glossy), child: const SizedBox.expand()))])));

  void _stylist() {
    final controller = TextEditingController();
    String mood = 'Elegáns';
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: Container(padding: const EdgeInsets.fromLTRB(18, 15, 18, 23), decoration: const BoxDecoration(color: Color(0xFFFFF8F5), borderRadius: BorderRadius.vertical(top: Radius.circular(29))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(99)))),
      const SizedBox(height: 15),
      const Row(children: [Icon(Icons.auto_awesome_rounded, color: rose), SizedBox(width: 7), Text('Beauty AI Stylist', style: TextStyle(fontFamily: 'serif', fontSize: 25, color: ink, fontWeight: FontWeight.w600))]),
      const SizedBox(height: 5),
      const Text('Írd le az alkalmat, a ruhád vagy a hangulatod.', style: TextStyle(color: muted, fontSize: 10.5)),
      const SizedBox(height: 12),
      TextField(controller: controller, minLines: 2, maxLines: 3, decoration: InputDecoration(hintText: 'Pl. fekete ruha, esküvő, arany ékszer…', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(17)))),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: ['Elegáns', 'Menyasszony', 'Iroda', 'Randi', 'Őszi', 'Merész'].map((m) => ChoiceChip(selected: mood == m, label: Text(m), onSelected: (_) => setSheet(() => mood = m), selectedColor: const Color(0xFFF6DCE0), backgroundColor: Colors.white, side: const BorderSide(color: line), showCheckmark: false, labelStyle: const TextStyle(fontSize: 9.5))).toList()),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { final q = '${controller.text} $mood'.toLowerCase(); NailLook result = looks[0]; if (q.contains('esküvő') || q.contains('menyasszony') || q.contains('francia')) result = looks[1]; if (q.contains('csillog') || q.contains('party')) result = looks[2]; if (q.contains('fekete') || q.contains('őszi') || q.contains('bordó')) result = looks[3]; if (q.contains('iroda') || q.contains('minimal') || q.contains('bézs')) result = looks[4]; if (q.contains('merész') || q.contains('chrome')) result = looks[5]; Navigator.pop(ctx); _select(result); _message('Beauty AI javaslat: ${result.name}'); }, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Ajánlás készítése'), style: FilledButton.styleFrom(backgroundColor: rose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))))),
    ])))));
  }

  void _salons() {
    const data = [('Anna Nails', '96% stílusmatch', 'Csütörtök 16:30'), ('Rose Studio', '92% stílusmatch', 'Péntek 10:00'), ('Gloss Room', '89% stílusmatch', 'Szombat 09:30')];
    showModalBottomSheet<void>(context: context, backgroundColor: Colors.transparent, builder: (ctx) => Container(padding: const EdgeInsets.fromLTRB(18, 15, 18, 22), decoration: const BoxDecoration(color: Color(0xFFFFF8F5), borderRadius: BorderRadius.vertical(top: Radius.circular(29))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(99)))), const SizedBox(height: 15), const Text('Szalon találatok · DEMO', style: TextStyle(fontFamily: 'serif', fontSize: 24, color: ink, fontWeight: FontWeight.w600)), const SizedBox(height: 5), const Text('A végleges marketplace portfólió, ár, távolság és szabad időpont szerint rendez.', style: TextStyle(color: muted, fontSize: 9.8)), const SizedBox(height: 11), ...data.map((x) => Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(11), decoration: _card(), child: Row(children: [const CircleAvatar(radius: 19, backgroundColor: Color(0xFFF6D7DD), child: Icon(Icons.storefront_outlined, color: roseDark, size: 18)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)), Text('${x.$2} · ${x.$3}', style: const TextStyle(color: muted, fontSize: 8.8))])), TextButton(onPressed: () { Navigator.pop(ctx); _message('Demo foglalás: ${x.$1}'); }, child: const Text('Megnézem'))])))])));
  }
}

class _ProfileTag extends StatelessWidget {
  const _ProfileTag(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: roseDark), const SizedBox(width: 5), Text(label, style: const TextStyle(color: ink, fontSize: 9.5, fontWeight: FontWeight.w600))]));
}
