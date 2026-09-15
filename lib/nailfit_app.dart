import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'nailfit_painters.dart';

const nfInk = Color(0xFF23181A);
const nfMuted = Color(0xFF806E70);
const nfRose = Color(0xFFC96379);
const nfRoseDark = Color(0xFFAA4F65);
const nfBlush = Color(0xFFF8DEE3);
const nfCream = Color(0xFFFFF9F6);
const nfCard = Color(0xFFFFFDFB);
const nfLine = Color(0xFFEFDCDD);

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
        scaffoldBackgroundColor: nfCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: nfRose,
          brightness: Brightness.light,
          surface: nfCard,
        ),
        fontFamily: 'sans-serif',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: nfInk),
          bodySmall: TextStyle(color: nfMuted),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const NailFitHome(),
    );
  }
}

class StylePreset {
  const StylePreset({
    required this.name,
    required this.subtitle,
    required this.shape,
    required this.color,
    required this.finish,
    required this.length,
    required this.match,
    required this.category,
  });

  final String name;
  final String subtitle;
  final String shape;
  final Color color;
  final NailFinish finish;
  final double length;
  final int match;
  final String category;
}

class NailFitHome extends StatefulWidget {
  const NailFitHome({super.key});

  @override
  State<NailFitHome> createState() => _NailFitHomeState();
}

class _NailFitHomeState extends State<NailFitHome> {
  final ImagePicker _picker = ImagePicker();
  final List<Offset> _points = [];
  final GlobalKey _tryOnPreviewKey = GlobalKey();
  final Set<String> _favorites = <String>{};
  final List<StylePreset> _savedLooks = [];

  static const _presets = <StylePreset>[
    StylePreset(
      name: 'Rózsás nude',
      subtitle: 'Elegáns · Időtlen · Nőies',
      shape: 'Mandula',
      color: Color(0xFFD89AA4),
      finish: NailFinish.glossy,
      length: .98,
      match: 96,
      category: 'Nude',
    ),
    StylePreset(
      name: 'Francia klasszikus',
      subtitle: 'Tiszta · Finom · Klasszikus',
      shape: 'Mandula',
      color: Color(0xFFE6B5AE),
      finish: NailFinish.french,
      length: .92,
      match: 95,
      category: 'Francia',
    ),
    StylePreset(
      name: 'Finom csillogás',
      subtitle: 'Lágy · Fényes · Ünnepi',
      shape: 'Ovális',
      color: Color(0xFFD98C9C),
      finish: NailFinish.glitter,
      length: 1.04,
      match: 93,
      category: 'Merész',
    ),
    StylePreset(
      name: 'Őszi elegancia',
      subtitle: 'Mély · Elegáns · Karakteres',
      shape: 'Mandula',
      color: Color(0xFF681A2B),
      finish: NailFinish.glossy,
      length: 1.02,
      match: 91,
      category: 'Őszi',
    ),
    StylePreset(
      name: 'Letisztult bézs',
      subtitle: 'Minimal · Meleg · Hordható',
      shape: 'Kocka',
      color: Color(0xFFC7A28F),
      finish: NailFinish.glossy,
      length: .82,
      match: 90,
      category: 'Minimal',
    ),
    StylePreset(
      name: 'Rose chrome',
      subtitle: 'Modern · Fényes · Trend',
      shape: 'Coffin',
      color: Color(0xFFB96A78),
      finish: NailFinish.chrome,
      length: 1.18,
      match: 88,
      category: 'Merész',
    ),
  ];

  static const _colors = <Color>[
    Color(0xFFD89AA4),
    Color(0xFFE6B5AE),
    Color(0xFFF0D4CB),
    Color(0xFFC7A28F),
    Color(0xFFB96A78),
    Color(0xFF681A2B),
    Color(0xFF2C1E22),
    Color(0xFFA891A7),
    Color(0xFF8C9A83),
  ];

  int _tab = 0;
  XFile? _photo;
  String _shape = _presets.first.shape;
  Color _color = _presets.first.color;
  NailFinish _finish = _presets.first.finish;
  double _length = _presets.first.length;
  String _activeName = _presets.first.name;
  String _category = 'Minimal';
  bool _saving = false;
  int _savedCount = 0;

  String get _lookKey => '$_shape-${_color.toARGB32()}-${_finish.name}-${_length.toStringAsFixed(2)}';
  bool get _isFavorite => _favorites.contains(_lookKey);

  int get _match {
    final preset = _presets.where((p) => p.name == _activeName).cast<StylePreset?>().firstOrNull;
    if (preset != null &&
        preset.shape == _shape &&
        preset.color.toARGB32() == _color.toARGB32() &&
        preset.finish == _finish) {
      return preset.match;
    }
    final base = switch (_shape) {
      'Mandula' => 96,
      'Ovális' => 94,
      'Kocka' => 89,
      'Coffin' => 91,
      _ => 87,
    };
    return (base - ((_length - 1).abs() * 10)).round().clamp(78, 98);
  }

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
      _tab = 1;
    });
  }

  void _applyPreset(StylePreset preset, {bool openTryOn = false}) {
    setState(() {
      _activeName = preset.name;
      _shape = preset.shape;
      _color = preset.color;
      _finish = preset.finish;
      _length = preset.length;
      if (openTryOn) _tab = 2;
    });
  }

  void _toggleFavorite() {
    setState(() {
      if (_favorites.contains(_lookKey)) {
        _favorites.remove(_lookKey);
      } else {
        _favorites.add(_lookKey);
      }
    });
    _snack(_isFavorite ? 'Hozzáadva a kedvencekhez.' : 'Eltávolítva a kedvencekből.');
  }

  void _addPoint(Offset local, Size size) {
    if (_photo == null || _points.length >= 5) return;
    setState(() {
      _points.add(Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      ));
    });
  }

  Future<void> _savePreview() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _tryOnPreviewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Preview not ready');
      final image = await boundary.toImage(pixelRatio: 2.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encoding failed');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/nailfit_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      final saved = StylePreset(
        name: _activeName,
        subtitle: 'Mentett look · $_shape',
        shape: _shape,
        color: _color,
        finish: _finish,
        length: _length,
        match: _match,
        category: 'Mentett',
      );
      setState(() {
        _savedCount++;
        _savedLooks.insert(0, saved);
      });
      _snack('Look elmentve PNG-ként · #$_savedCount');
    } catch (_) {
      if (mounted) _snack('A mentés most nem sikerült.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _analyzeHand() {
    if (_photo != null && _points.isEmpty) {
      setState(() {
        _points.addAll(const [
          Offset(.79, .57),
          Offset(.30, .27),
          Offset(.45, .18),
          Offset(.60, .24),
          Offset(.72, .34),
        ]);
      });
      _snack('Vizuális automatikus becslés alkalmazva. Finomhangolás később bővíthető.');
    }
    setState(() => _tab = 2);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            _homeScreen(),
            _scanScreen(),
            _tryOnScreen(),
            _savedScreen(),
            _profileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Főoldal'),
      (Icons.camera_alt_outlined, Icons.camera_alt_rounded, 'Scan'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Try-On'),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Mentett'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1FC28B92),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _tab == i;
            final item = items[i];
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFFBE3E7) : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(active ? item.$2 : item.$1, color: active ? nfRoseDark : const Color(0xFF34434A), size: 24),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: active ? nfRoseDark : const Color(0xFF4F5659),
                          fontSize: 10.5,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(top: 3),
                        width: active ? 5 : 0,
                        height: active ? 5 : 0,
                        decoration: const BoxDecoration(color: nfRoseDark, shape: BoxShape.circle),
                      ),
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

  Widget _homeScreen() {
    return _page(
      children: [
        _brandHeader(),
        const SizedBox(height: 18),
        _homeHero(),
        const SizedBox(height: 24),
        _sectionTitle('Neked ajánljuk', trailing: 'Összes megtekintése'),
        const SizedBox(height: 10),
        _styleCarousel(_presets.take(5).toList(), height: 142),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _quickTile(Icons.favorite_border_rounded, 'Kedvencek', 'Mentett stílusaid', () => setState(() => _tab = 3))),
            const SizedBox(width: 8),
            Expanded(child: _quickTile(Icons.bookmark_border_rounded, 'Look mentése', 'A kedvenc szetted', () => setState(() => _tab = 2))),
            const SizedBox(width: 8),
            Expanded(child: _quickTile(Icons.person_outline_rounded, 'Stílusprofil', 'Személyre szabott', () => setState(() => _tab = 4))),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: _aiMatchCard()),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _seasonCard()),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle('Stílusok böngészése', trailing: 'Összes kategória'),
        const SizedBox(height: 10),
        _categoryRow(),
        const SizedBox(height: 18),
        _beautyAiPromptCard(),
      ],
    );
  }

  Widget _scanScreen() {
    return _page(
      children: [
        _brandHeader(compact: true),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kéz szkennelése', style: TextStyle(fontFamily: 'serif', fontSize: 38, height: 1, color: nfInk)),
                  SizedBox(height: 8),
                  Text('Igazítsd a kezed a kerethez, és készíts egy éles fotót a legjobb eredményért.', style: TextStyle(color: nfMuted, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('1 / 3', style: TextStyle(color: nfRoseDark, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(value: .34, minHeight: 6, color: nfRose, backgroundColor: Color(0xFFEFDCDD)),
                  ),
                  const SizedBox(height: 6),
                  const Text('KÉZ ELEMZÉSE', style: TextStyle(color: nfMuted, fontSize: 8.5, letterSpacing: 1.1)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _scanPreview(),
        const SizedBox(height: 14),
        _recognizedFeatures(),
        const SizedBox(height: 12),
        _scanAiInsight(),
        const SizedBox(height: 20),
        _sectionTitle('Ajánlott stílusok neked', trailing: 'Összes megtekintése'),
        const SizedBox(height: 10),
        _styleCarousel(_presets.take(3).toList(), height: 136),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _primaryButton(Icons.auto_awesome_rounded, 'Elemzés indítása', _analyzeHand),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _secondaryButton(Icons.camera_alt_outlined, 'Fotó újrakészítése', () => _pick(ImageSource.camera)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tryOnScreen() {
    return _page(
      children: [
        _brandHeader(compact: true),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Color(0xFFFBE6E7), shape: BoxShape.circle),
              child: IconButton(onPressed: () => setState(() => _tab = 1), icon: const Icon(Icons.arrow_back_rounded, color: nfInk)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VIRTUÁLIS PRÓBA', style: TextStyle(color: nfRoseDark, fontSize: 10, letterSpacing: 2.1, fontWeight: FontWeight.w700)),
                  SizedBox(height: 3),
                  Text('Próbáld fel', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 42, height: 1)),
                  SizedBox(height: 5),
                  Text('Nézd meg, hogyan áll rajtad, és találd meg a hozzád illő stílust.', style: TextStyle(color: nfMuted, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            _smallPill(Icons.camera_alt_rounded, 'Új fotó', () => _pick(ImageSource.camera)),
          ],
        ),
        const SizedBox(height: 16),
        RepaintBoundary(key: _tryOnPreviewKey, child: _tryOnPreview()),
        const SizedBox(height: 20),
        _sectionTitle('További stílusok kipróbálása', trailing: 'Összes stílus'),
        const SizedBox(height: 10),
        _styleCarousel(_presets, height: 140),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _actionTile(_isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, _isFavorite ? 'Kedvenc' : 'Kedvencekhez', _toggleFavorite)),
            const SizedBox(width: 8),
            Expanded(child: _actionTile(Icons.bookmark_border_rounded, _saving ? 'Mentés…' : 'Look mentése', _savePreview)),
            const SizedBox(width: 8),
            Expanded(child: _actionTile(Icons.ios_share_rounded, 'Megosztás', () => _snack('A megosztási lap bekötése a kiadási körben jön.'))),
          ],
        ),
        const SizedBox(height: 18),
        _fineTuneCard(),
        const SizedBox(height: 18),
        _bookingCard(),
      ],
    );
  }

  Widget _savedScreen() {
    final favoritePresets = _presets.where((p) {
      final key = '${p.shape}-${p.color.toARGB32()}-${p.finish.name}-${p.length.toStringAsFixed(2)}';
      return _favorites.contains(key);
    }).toList();
    final showFavorites = favoritePresets.isEmpty ? _presets.take(3).toList() : favoritePresets;

    return _page(
      children: [
        _brandHeader(compact: true),
        const SizedBox(height: 16),
        const Text('Mentett lookok', style: TextStyle(fontFamily: 'serif', fontSize: 40, color: nfInk, height: 1)),
        const SizedBox(height: 7),
        Text('Gyűjtsd egy helyre a kipróbált és kedvenc stílusaidat. $_savedCount saját PNG mentés.', style: const TextStyle(color: nfMuted, fontSize: 13)),
        const SizedBox(height: 22),
        _sectionTitle('Mentett kollekciók', trailing: 'Összes kollekció'),
        const SizedBox(height: 10),
        _collectionRow(),
        const SizedBox(height: 24),
        _sectionTitle('Kedvenc szettjeid', trailing: 'Összes megtekintése'),
        const SizedBox(height: 10),
        _styleCarousel(showFavorites, height: 150),
        if (_savedLooks.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionTitle('Saját mentéseid'),
          const SizedBox(height: 10),
          _styleCarousel(_savedLooks.take(6).toList(), height: 148),
        ],
        const SizedBox(height: 22),
        _beautyAiPromptCard(),
      ],
    );
  }

  Widget _profileScreen() {
    return _page(
      children: [
        _brandHeader(compact: true),
        const SizedBox(height: 18),
        _profileHeader(),
        const SizedBox(height: 24),
        _sectionTitle('Mentett kollekciók', trailing: 'Összes kollekció'),
        const SizedBox(height: 10),
        _collectionRow(),
        const SizedBox(height: 24),
        _sectionTitle('Kedvenc szettjeid', trailing: 'Összes megtekintése'),
        const SizedBox(height: 10),
        _styleCarousel(_presets.take(3).toList(), height: 148),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _utilityTile(Icons.person_outline_rounded, 'Stílusprofil szerkesztése'),
            _utilityTile(Icons.notifications_none_rounded, 'Értesítések'),
            _utilityTile(Icons.share_outlined, 'Megosztott lookok'),
            _utilityTile(Icons.image_outlined, 'PNG export'),
            _utilityTile(Icons.lock_outline_rounded, 'Adatvédelem és képek'),
            _utilityTile(Icons.help_outline_rounded, 'Súgó és GYIK'),
          ],
        ),
        const SizedBox(height: 18),
        _profileAiBanner(),
      ],
    );
  }

  Widget _page({required List<Widget> children}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF8), Color(0xFFFFF2EF), Color(0xFFFFF9F6)],
        ),
      ),
      child: CustomScrollView(
        key: PageStorageKey('tab-$_tab'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      ),
    );
  }

  Widget _brandHeader({bool compact = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Text('NAIL', style: TextStyle(color: nfInk, fontSize: 22, letterSpacing: 4.2, fontWeight: FontWeight.w500)),
                Text('FIT', style: TextStyle(color: nfRose, fontSize: 22, letterSpacing: 4.2, fontWeight: FontWeight.w500)),
              ],
            ),
            if (!compact) const Text('B E A U T Y   M E E T S   Y O U', style: TextStyle(fontSize: 6.8, letterSpacing: 1.2, color: nfMuted)),
          ],
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: _showStylistSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE9EC),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, color: nfRose, size: 15),
                SizedBox(width: 6),
                Text('BEAUTY AI', style: TextStyle(color: nfRoseDark, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), shape: BoxShape.circle, border: Border.all(color: Colors.white)),
          child: Stack(
            children: [
              const Center(child: Icon(Icons.notifications_none_rounded, color: nfInk, size: 21)),
              Positioned(right: 7, top: 6, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: nfRose, shape: BoxShape.circle))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeHero() {
    return Container(
      height: 280,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: const [BoxShadow(color: Color(0x1E9E6A71), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 10,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 8, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFECE7), Color(0xFFF6D8D5)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('T A L Á L D   M E G', style: TextStyle(color: nfRoseDark, fontSize: 8.5, letterSpacing: 1.7, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const Text('a hozzád illő\nkörmöket.', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 34, height: .92)),
                  const SizedBox(height: 12),
                  const Text('Nézd meg, melyik forma, árnyalat és stílus áll neked a legjobban — még a szalon előtt.', style: TextStyle(color: nfMuted, fontSize: 11.5, height: 1.35)),
                  const Spacer(),
                  SizedBox(
                    width: 180,
                    child: FilledButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded, size: 20),
                      label: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Készíts fotót'), Icon(Icons.arrow_forward_rounded, size: 18)]),
                      style: FilledButton.styleFrom(
                        backgroundColor: nfRose,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 11,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: DemoHandPainter(color: _color, shape: _shape, length: _length, finish: _finish, softBackground: true)),
                Positioned(
                  right: 13,
                  top: 18,
                  child: Text('Your\nNails\nYour Story ♡', textAlign: TextAlign.right, style: TextStyle(color: Colors.white.withValues(alpha: .92), fontFamily: 'serif', fontStyle: FontStyle.italic, fontSize: 15, height: 1.05)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleCarousel(List<StylePreset> styles, {double height = 142}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: styles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) => _styleCard(styles[i], height: height),
      ),
    );
  }

  Widget _styleCard(StylePreset style, {double height = 142}) {
    final selected = style.name == _activeName;
    final key = '${style.shape}-${style.color.toARGB32()}-${style.finish.name}-${style.length.toStringAsFixed(2)}';
    final favorite = _favorites.contains(key);
    return GestureDetector(
      onTap: () => _applyPreset(style, openTryOn: true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 142,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? nfRose : Colors.white, width: selected ? 2 : 1),
          boxShadow: const [BoxShadow(color: Color(0x10966D73), blurRadius: 12, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: NailSwatchPainter(color: style.color, shape: style.shape, finish: style.finish)),
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), shape: BoxShape.circle),
                      child: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 16, color: nfRoseDark),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Row(
                children: [
                  Expanded(child: Text(style.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: nfInk))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontFamily: 'serif', fontSize: 25, height: 1, color: nfInk, fontWeight: FontWeight.w600))),
        if (trailing != null)
          Text('$trailing  →', style: const TextStyle(color: nfRoseDark, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _quickTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.all(11),
        decoration: _softDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [Icon(icon, size: 22, color: nfInk), const Spacer(), const Icon(Icons.chevron_right_rounded, size: 18, color: nfMuted)]),
            const SizedBox(height: 6),
            Text(title, maxLines: 1, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.8, color: nfMuted)),
          ],
        ),
      ),
    );
  }

  BoxDecoration _softDecoration({Color? color}) => BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
        boxShadow: const [BoxShadow(color: Color(0x109B7178), blurRadius: 16, offset: Offset(0, 7))],
      );

  Widget _aiMatchCard() {
    return Container(
      height: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE8EC), Color(0xFFF6D7DB)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 17), SizedBox(width: 6), Text('AI AJÁNLÁS NEKED', style: TextStyle(color: nfRoseDark, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2))]),
          const SizedBox(height: 10),
          Text('$_match% egyezés', style: const TextStyle(fontFamily: 'serif', fontSize: 30, color: nfInk, height: 1)),
          const SizedBox(height: 7),
          Text('Ez a stílus harmonikusan illik a kézformádhoz és a választott hosszadhoz.', style: TextStyle(color: nfMuted.withValues(alpha: .95), fontSize: 10.5, height: 1.35)),
          const Spacer(),
          FilledButton(
            onPressed: () => setState(() => _tab = 2),
            style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Próbáld ki most  →', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _seasonCard() {
    return Container(
      height: 210,
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(color: const Color(0xFFFFF7F2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.eco_outlined, color: nfRoseDark, size: 25),
          const Spacer(),
          const Text('Új őszi\nkollekció', style: TextStyle(fontFamily: 'serif', fontSize: 23, height: .95, color: nfInk)),
          const SizedBox(height: 8),
          const Text('Természetes árnyalatok, időtlen elegancia.', style: TextStyle(color: nfMuted, fontSize: 9.5, height: 1.35)),
          const SizedBox(height: 10),
          GestureDetector(onTap: () => _applyPreset(_presets[3], openTryOn: true), child: const Text('Felfedezem  →', style: TextStyle(color: nfRoseDark, fontWeight: FontWeight.w800, fontSize: 10.5))),
        ],
      ),
    );
  }

  Widget _categoryRow() {
    const cats = [
      (Icons.diamond_outlined, 'Minimal'),
      (Icons.waves_rounded, 'Francia'),
      (Icons.circle, 'Nude'),
      (Icons.favorite_border_rounded, 'Menyasszony'),
      (Icons.eco_outlined, 'Őszi'),
      (Icons.auto_awesome_rounded, 'Merész'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final active = _category == cats[i].$2;
          return ChoiceChip(
            selected: active,
            avatar: Icon(cats[i].$1, size: 15, color: active ? nfRoseDark : nfMuted),
            label: Text(cats[i].$2),
            onSelected: (_) => setState(() => _category = cats[i].$2),
            selectedColor: const Color(0xFFF8DDE2),
            backgroundColor: Colors.white.withValues(alpha: .72),
            side: BorderSide(color: active ? nfRose.withValues(alpha: .5) : Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            labelStyle: TextStyle(color: active ? nfRoseDark : nfInk, fontSize: 10.5, fontWeight: FontWeight.w600),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _beautyAiPromptCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _showStylistSheet,
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFCE5E8), Color(0xFFFFF8F5)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
        ),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: nfRose, size: 25)),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Beauty AI Stylist', style: TextStyle(fontFamily: 'serif', fontSize: 20, color: nfInk, fontWeight: FontWeight.w600)),
                  SizedBox(height: 3),
                  Text('Írd le az alkalmat, a ruhád vagy a hangulatod. Az app összeállít egy hozzád illő lookot.', style: TextStyle(color: nfMuted, fontSize: 10.5, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: nfRoseDark),
          ],
        ),
      ),
    );
  }

  Widget _scanPreview() {
    return Container(
      height: 430,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.5), boxShadow: const [BoxShadow(color: Color(0x1C90656C), blurRadius: 24, offset: Offset(0, 12))]),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (_, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => _addPoint(e.localPosition, size),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_photo != null)
                  Image.file(File(_photo!.path), fit: BoxFit.cover)
                else
                  CustomPaint(painter: DemoHandPainter(color: const Color(0xFFD5A2A2), shape: 'Ovális', length: .84, finish: NailFinish.glossy, scanPose: true)),
                const CustomPaint(painter: ScanOverlayPainter(complete: true)),
                if (_photo != null)
                  CustomPaint(painter: NailOverlayPainter(points: _points, color: _color, shape: _shape, length: _length, finish: _finish, calibration: _points.length < 5)),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0x7A382D2B), borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 17), const SizedBox(width: 8), Text(_photo == null ? 'Igazítsd a kezed a kerethez' : (_points.length < 5 ? 'Koppints az 5 körömre · ${_points.length}/5' : 'Körmök kijelölve'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 15,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _zoomChip('1×', true),
                      _zoomChip('0,5', false),
                      _zoomChip('2', false),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _zoomChip(String label, bool active) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(color: active ? const Color(0xB92C2423) : Colors.white.withValues(alpha: .62), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : nfInk, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _recognizedFeatures() {
    final items = [
      (Icons.circle, 'Bőrtónus', 'Világos, meleg'),
      (Icons.back_hand_outlined, 'Kézforma', 'Karcsú, hosszúkás'),
      (Icons.water_drop_outlined, 'Körömágy', 'Közepes, ovális'),
      (Icons.auto_awesome_rounded, 'Ajánlott forma', 'Mandula'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Felismert jellemzők', style: TextStyle(fontFamily: 'serif', fontSize: 22, color: nfInk, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...items.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFFFF8F6), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Container(width: 34, height: 34, decoration: const BoxDecoration(color: Color(0xFFF7D9DE), shape: BoxShape.circle), child: Icon(e.$1, size: 17, color: nfRoseDark)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)), Text(e.$3, style: const TextStyle(color: nfMuted, fontSize: 10))])),
                    const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 18),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _scanAiInsight() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7EB), Color(0xFFF7D8DD)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 17), SizedBox(width: 6), Text('AI ELEMZÉS', style: TextStyle(color: nfRoseDark, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4))]),
                SizedBox(height: 10),
                Text('Mandula forma ajánlott.', style: TextStyle(fontFamily: 'serif', fontSize: 25, color: nfInk, height: 1)),
                SizedBox(height: 7),
                Text('A kéz arányaihoz ez a forma harmonikusan illik.', style: TextStyle(color: nfMuted, fontSize: 10.5, height: 1.3)),
                SizedBox(height: 12),
                Divider(color: Color(0x66C7919A)),
                SizedBox(height: 7),
                Text('Meleg nude árnyalatok jól állnak.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 82, height: 110, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)), child: CustomPaint(painter: NailSwatchPainter(color: Color(0xFFD89AA4), shape: 'Mandula', finish: NailFinish.glossy))),
        ],
      ),
    );
  }

  Widget _tryOnPreview() {
    return Container(
      height: 430,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white, width: 1.4), boxShadow: const [BoxShadow(color: Color(0x21936D74), blurRadius: 26, offset: Offset(0, 13))]),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_photo != null)
            Image.file(File(_photo!.path), fit: BoxFit.cover)
          else
            CustomPaint(painter: DemoHandPainter(color: _color, shape: _shape, length: _length, finish: _finish, softBackground: true)),
          if (_photo != null)
            CustomPaint(painter: NailOverlayPainter(points: _points, color: _color, shape: _shape, length: _length, finish: _finish, calibration: _points.length < 5)),
          Positioned(left: 14, top: 14, child: _glassChip(_photo == null ? 'STUDIO DEMO' : 'SAJÁT KÉZ')),
          Positioned(
            right: 14,
            top: 14,
            child: InkWell(
              onTap: _toggleFavorite,
              child: Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), shape: BoxShape.circle), child: Icon(_isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: nfRoseDark)),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              width: 190,
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_activeName, style: const TextStyle(fontFamily: 'serif', fontSize: 19, color: nfInk, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text('$_shape · ${_finishLabel(_finish)}', style: const TextStyle(color: nfMuted, fontSize: 9.5))]),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 14,
            child: Container(
              width: 145,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: const Color(0xF6FCE8EA), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 14), SizedBox(width: 5), Text('AI AJÁNLÁS', style: TextStyle(color: nfRoseDark, fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 1))]), const SizedBox(height: 7), Text('$_match% egyezés', style: const TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 22, height: 1)), const SizedBox(height: 5), const Text('Illik a kézformádhoz és a tónusodhoz.', style: TextStyle(color: nfMuted, fontSize: 8.5, height: 1.25))]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: const Color(0x843B2D2B), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .5)),
      );

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: _softDecoration(),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: nfInk, size: 20), const SizedBox(width: 7), Flexible(child: Text(label, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)))]),
      ),
    );
  }

  Widget _fineTuneCard() {
    const shapes = ['Mandula', 'Ovális', 'Kocka', 'Coffin', 'Stiletto'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Finomhangolás', style: TextStyle(fontFamily: 'serif', fontSize: 24, color: nfInk, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _label('Forma'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: shapes.map((s) => ChoiceChip(selected: _shape == s, label: Text(s), onSelected: (_) => setState(() { _shape = s; _activeName = 'Saját kombináció'; }), selectedColor: const Color(0xFFF7DCE1), backgroundColor: const Color(0xFFFFF8F6), side: BorderSide(color: _shape == s ? nfRose.withValues(alpha: .5) : nfLine), showCheckmark: false, labelStyle: TextStyle(fontSize: 10, color: _shape == s ? nfRoseDark : nfInk))).toList(),
          ),
          const SizedBox(height: 14),
          _label('Finish'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: NailFinish.values.map((f) => ChoiceChip(selected: _finish == f, label: Text(_finishLabel(f)), onSelected: (_) => setState(() { _finish = f; _activeName = 'Saját kombináció'; }), selectedColor: const Color(0xFFF7DCE1), backgroundColor: const Color(0xFFFFF8F6), side: BorderSide(color: _finish == f ? nfRose.withValues(alpha: .5) : nfLine), showCheckmark: false, labelStyle: TextStyle(fontSize: 10, color: _finish == f ? nfRoseDark : nfInk))).toList(),
          ),
          const SizedBox(height: 14),
          _label('Árnyalat'),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _colors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _colors[i];
                final selected = c.toARGB32() == _color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() { _color = c; _activeName = 'Saját kombináció'; }),
                  child: AnimatedContainer(duration: const Duration(milliseconds: 150), width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: selected ? nfInk : Colors.white, width: selected ? 2.5 : 1.2), boxShadow: selected ? const [BoxShadow(color: Color(0x279C6871), blurRadius: 8)] : null)),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _label('Hossz'),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: nfRose, inactiveTrackColor: nfLine, thumbColor: nfRoseDark, overlayColor: nfRose.withValues(alpha: .12), trackHeight: 3),
            child: Slider(value: _length, min: .74, max: 1.42, divisions: 14, onChanged: (v) => setState(() { _length = v; _activeName = 'Saját kombináció'; })),
          ),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Természetes', style: TextStyle(color: nfMuted, fontSize: 9)), Text('Extra hosszú', style: TextStyle(color: nfMuted, fontSize: 9))]),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(text, style: const TextStyle(color: nfInk, fontSize: 11.5, fontWeight: FontWeight.w800)));

  String _finishLabel(NailFinish finish) => switch (finish) {
        NailFinish.glossy => 'Fényes',
        NailFinish.french => 'Francia',
        NailFinish.glitter => 'Csillogó',
        NailFinish.chrome => 'Chrome',
      };

  Widget _bookingCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _showSalonSheet,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFFFBE4E7), Color(0xFFFFF6F1)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
        ),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFF6CDD4), shape: BoxShape.circle), child: const Icon(Icons.calendar_month_outlined, color: nfRoseDark)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Időpontfoglalás a szalonban', style: TextStyle(fontFamily: 'serif', fontSize: 19, fontWeight: FontWeight.w600, color: nfInk)), SizedBox(height: 3), Text('Vidd magaddal a kedvenc stílusod, és keltsd életre.', style: TextStyle(color: nfMuted, fontSize: 10.5))])),
            const Icon(Icons.chevron_right_rounded, color: nfMuted),
          ],
        ),
      ),
    );
  }

  Widget _collectionRow() {
    final collections = [
      ('Nude kedvencek', '8 look', _presets[0]),
      ('Őszi elegancia', '6 look', _presets[3]),
      ('Csillogó hangulat', '5 look', _presets[2]),
      ('Francia klasszikus', '5 look', _presets[1]),
    ];
    return SizedBox(
      height: 162,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: collections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) {
          final c = collections[i];
          return InkWell(
            onTap: () => _applyPreset(c.$3, openTryOn: true),
            child: Container(
              width: 158,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .86), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white)),
              child: Column(
                children: [
                  Expanded(child: CustomPaint(painter: NailSwatchPainter(color: c.$3.color, shape: c.$3.shape, finish: c.$3.finish), child: const SizedBox.expand())),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
                    child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5)), Text(c.$2, style: const TextStyle(color: nfMuted, fontSize: 9))])), const Icon(Icons.more_vert_rounded, color: nfRoseDark, size: 17)]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _profileHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF0ED), Color(0xFFF9DFE3)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFE9B8AE), Color(0xFFC47D75)])),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(width: 15),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Anna', style: TextStyle(fontFamily: 'serif', fontSize: 31, color: nfInk, height: 1)), SizedBox(height: 4), Row(children: [Text('Stílusprofil', style: TextStyle(color: nfMuted, fontSize: 13)), SizedBox(width: 3), Icon(Icons.chevron_right_rounded, size: 18, color: nfMuted)])])),
              const Text('Beautiful\nNails ♡', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'serif', fontStyle: FontStyle.italic, color: nfRoseDark, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: const [
              _ProfileChip(Icons.water_drop_outlined, 'Mandula'),
              _ProfileChip(Icons.circle, 'Nude'),
              _ProfileChip(Icons.diamond_outlined, 'Minimal'),
              _ProfileChip(Icons.eco_outlined, 'Őszi'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: nfLine),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _profileStat(Icons.bookmark_border_rounded, '${24 + _savedCount}', 'Mentett lookok')),
              Expanded(child: _profileStat(Icons.favorite_border_rounded, '${17 + _favorites.length}', 'Kedvencek')),
              Expanded(child: _profileStat(Icons.auto_awesome_rounded, '36', 'Próbák')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileStat(IconData icon, String number, String label) => Column(
        children: [
          Icon(icon, color: nfInk, size: 21),
          const SizedBox(height: 5),
          Text(number, style: const TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 23, height: 1)),
          Text(label, style: const TextStyle(color: nfMuted, fontSize: 8.8)),
        ],
      );

  Widget _utilityTile(IconData icon, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _snack('$label · prototípus funkció'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _softDecoration(),
        child: Row(children: [Container(width: 34, height: 34, decoration: const BoxDecoration(color: Color(0xFFF7D9DE), shape: BoxShape.circle), child: Icon(icon, color: nfInk, size: 18)), const SizedBox(width: 9), Expanded(child: Text(label, maxLines: 2, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 18)]),
      ),
    );
  }

  Widget _profileAiBanner() {
    return InkWell(
      onTap: _showStylistSheet,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 145,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(17),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFCE4E8), Color(0xFFFFF5F0)])),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 15), SizedBox(width: 5), Text('BEAUTY AI', style: TextStyle(color: nfRoseDark, fontSize: 8.5, letterSpacing: 1.3, fontWeight: FontWeight.w800))]), SizedBox(height: 8), Text('Személyre szabott ajánlás', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 23, height: 1)), SizedBox(height: 5), Text('Fedezz fel új stílusokat a Te ízlésed alapján.', style: TextStyle(color: nfMuted, fontSize: 9.5))]),
              ),
            ),
            Expanded(flex: 2, child: CustomPaint(painter: DemoHandPainter(color: Color(0xFFD89AA4), shape: 'Mandula', length: .95, finish: NailFinish.glossy), child: const SizedBox.expand())),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(IconData icon, String label, VoidCallback onTap) => FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

  Widget _secondaryButton(IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: nfInk, backgroundColor: Colors.white.withValues(alpha: .65), side: BorderSide(color: Colors.white.withValues(alpha: .9)), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
      );

  Widget _smallPill(IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFFCE3E7), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: nfRoseDark, size: 17), const SizedBox(width: 6), Text(label, style: const TextStyle(color: nfRoseDark, fontSize: 10.5, fontWeight: FontWeight.w800))]),
        ),
      );

  void _showStylistSheet() {
    final controller = TextEditingController();
    String occasion = 'Elegáns';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            decoration: const BoxDecoration(color: Color(0xFFFFF8F5), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: nfLine, borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                const Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose), SizedBox(width: 8), Text('Beauty AI Stylist', style: TextStyle(fontFamily: 'serif', fontSize: 26, color: nfInk, fontWeight: FontWeight.w600))]),
                const SizedBox(height: 6),
                const Text('Mondd el, mit viselsz, hová mész, vagy milyen hangulatot szeretnél.', style: TextStyle(color: nfMuted, fontSize: 11.5)),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: 'Pl. fekete ruha, esküvő, elegáns, arany ékszer…', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(18))),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  children: ['Elegáns', 'Menyasszony', 'Iroda', 'Randi', 'Őszi', 'Merész'].map((e) => ChoiceChip(selected: occasion == e, label: Text(e), onSelected: (_) => setSheet(() => occasion = e), selectedColor: const Color(0xFFF7DCE1), backgroundColor: Colors.white, side: const BorderSide(color: nfLine), showCheckmark: false, labelStyle: const TextStyle(fontSize: 10))).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final query = '${controller.text} $occasion'.toLowerCase();
                      StylePreset result = _presets[0];
                      if (query.contains('esküvő') || query.contains('menyasszony') || query.contains('francia')) result = _presets[1];
                      if (query.contains('csillog') || query.contains('party') || query.contains('ünnep')) result = _presets[2];
                      if (query.contains('fekete') || query.contains('őszi') || query.contains('bordó') || query.contains('esti')) result = _presets[3];
                      if (query.contains('minimal') || query.contains('iroda') || query.contains('bézs')) result = _presets[4];
                      if (query.contains('merész') || query.contains('chrome')) result = _presets[5];
                      Navigator.pop(sheetContext);
                      _applyPreset(result, openTryOn: true);
                      _snack('Beauty AI javaslat: ${result.name}');
                    },
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Ajánlás készítése'),
                    style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSalonSheet() {
    const salons = [
      ('Anna Nails', '96% stílusmatch', 'Következő: Csütörtök 16:30'),
      ('Rose Studio', '92% stílusmatch', 'Következő: Péntek 10:00'),
      ('Gloss Room', '89% stílusmatch', 'Következő: Szombat 09:30'),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        decoration: const BoxDecoration(color: Color(0xFFFFF8F5), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: nfLine, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 16),
            const Text('Szalon találatok · DEMO', style: TextStyle(fontFamily: 'serif', fontSize: 25, color: nfInk, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('A végleges marketplace-ben portfólió, ár, távolság és szabad időpont alapján rendezünk.', style: TextStyle(color: nfMuted, fontSize: 10.5)),
            const SizedBox(height: 13),
            ...salons.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: _softDecoration(),
                  child: Row(children: [Container(width: 42, height: 42, decoration: const BoxDecoration(color: Color(0xFFF5D5DA), shape: BoxShape.circle), child: const Icon(Icons.storefront_outlined, color: nfRoseDark)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)), Text('${s.$2} · ${s.$3}', style: const TextStyle(color: nfMuted, fontSize: 9.5))])), TextButton(onPressed: () { Navigator.pop(sheetContext); _snack('Demo foglalási folyamat: ${s.$1}'); }, child: const Text('Megnézem'))]),
                )),
          ],
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: nfRoseDark), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 10.5, color: nfInk, fontWeight: FontWeight.w600))]),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
