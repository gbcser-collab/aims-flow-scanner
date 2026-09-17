import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'nailfit_painters.dart';

const nfInk = Color(0xFF211719);
const nfMuted = Color(0xFF806F71);
const nfRose = Color(0xFFC96579);
const nfRoseDark = Color(0xFFA94C61);
const nfCream = Color(0xFFFFF9F6);
const nfLine = Color(0xFFEEDCDD);

const nfHeroUrl = 'https://images.unsplash.com/photo-1610992015762-45dca7fa3a85?auto=format&fit=crop&q=78&w=1400';
const nfAlmondUrl = 'https://images.unsplash.com/photo-1772983166346-93afb9898264?auto=format&fit=crop&q=78&w=1400';

class PremiumLook {
  const PremiumLook(
    this.name,
    this.subtitle,
    this.color,
    this.match,
    this.image,
    this.category, {
    required this.shape,
    required this.finish,
    required this.length,
  });

  final String name;
  final String subtitle;
  final Color color;
  final int match;
  final String image;
  final String category;
  final String shape;
  final NailFinish finish;
  final double length;
}

const premiumLooks = <PremiumLook>[
  PremiumLook('Rózsás nude', 'Elegáns · Időtlen · Nőies', Color(0xFFD99CA6), 96, nfHeroUrl, 'Nude', shape: 'Mandula', finish: NailFinish.glossy, length: .98),
  PremiumLook('Francia klasszikus', 'Tiszta · Finom · Klasszikus', Color(0xFFE7B8B1), 95, nfAlmondUrl, 'Francia', shape: 'Mandula', finish: NailFinish.french, length: .92),
  PremiumLook('Finom csillogás', 'Puha fény · Alkalmi', Color(0xFFE6A4B2), 93, nfHeroUrl, 'Merész', shape: 'Ovális', finish: NailFinish.glitter, length: 1.04),
  PremiumLook('Őszi elegancia', 'Mély · Elegáns · Karakteres', Color(0xFF6B1D2E), 91, nfAlmondUrl, 'Őszi', shape: 'Mandula', finish: NailFinish.glossy, length: 1.02),
  PremiumLook('Letisztult bézs', 'Minimal · Természetes', Color(0xFFC7A18F), 90, nfHeroUrl, 'Minimal', shape: 'Kocka', finish: NailFinish.glossy, length: .82),
];

class ScanResult {
  const ScanResult({
    required this.tone,
    required this.undertone,
    required this.handShape,
    required this.nailBed,
    required this.recommendedShape,
    required this.quality,
    required this.qualityScore,
    required this.brightness,
    required this.contrast,
    required this.resolution,
  });

  final String tone;
  final String undertone;
  final String handShape;
  final String nailBed;
  final String recommendedShape;
  final String quality;
  final int qualityScore;
  final double brightness;
  final double contrast;
  final String resolution;
}

class NailFitV3Controller extends ChangeNotifier {
  int tab = 0;
  PremiumLook look = premiumLooks.first;
  final Set<String> favorites = <String>{};
  final List<PremiumLook> saved = <PremiumLook>[];
  final List<String> savedPngPaths = <String>[];
  final List<Offset> points = <Offset>[];

  ScanResult? scan;
  bool analyzing = false;
  bool showOverlay = true;
  bool notificationsEnabled = true;
  int tryCount = 0;
  DateTime? appointment;
  String preferredShape = 'Mandula';
  String preferredStyle = 'Nude';

  String shape = premiumLooks.first.shape;
  Color color = premiumLooks.first.color;
  NailFinish finish = premiumLooks.first.finish;
  double length = premiumLooks.first.length;

  static const List<Offset> defaultPoints = <Offset>[
    Offset(.79, .57),
    Offset(.30, .27),
    Offset(.45, .18),
    Offset(.60, .24),
    Offset(.72, .34),
  ];

  Future<File> get _stateFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nailfit_state_v3.json');
  }

  Future<void> restore() async {
    try {
      final file = await _stateFile;
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      favorites
        ..clear()
        ..addAll((raw['favorites'] as List<dynamic>? ?? const []).map((e) => '$e'));
      savedPngPaths
        ..clear()
        ..addAll((raw['savedPngPaths'] as List<dynamic>? ?? const []).map((e) => '$e'));
      saved
        ..clear()
        ..addAll((raw['saved'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => premiumLooks.where((p) => p.name == '$e').firstOrNull)
            .whereType<PremiumLook>());
      notificationsEnabled = raw['notificationsEnabled'] as bool? ?? true;
      tryCount = raw['tryCount'] as int? ?? 0;
      preferredShape = raw['preferredShape'] as String? ?? 'Mandula';
      preferredStyle = raw['preferredStyle'] as String? ?? 'Nude';
      final appointmentRaw = raw['appointment'] as String?;
      appointment = appointmentRaw == null ? null : DateTime.tryParse(appointmentRaw);
      notifyListeners();
    } catch (_) {
      // A sérült helyi állapot nem akadályozhatja az app indulását.
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _stateFile;
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'favorites': favorites.toList(),
        'saved': saved.map((e) => e.name).toList(),
        'savedPngPaths': savedPngPaths,
        'notificationsEnabled': notificationsEnabled,
        'tryCount': tryCount,
        'preferredShape': preferredShape,
        'preferredStyle': preferredStyle,
        'appointment': appointment?.toIso8601String(),
      }), flush: true);
    } catch (_) {
      // Best effort: a futó állapot mentés nélkül is használható.
    }
  }

  void go(int value) {
    tab = value.clamp(0, 4).toInt();
    notifyListeners();
  }

  void select(PremiumLook value, {bool tryOn = true}) {
    look = value;
    shape = value.shape;
    color = value.color;
    finish = value.finish;
    length = value.length;
    if (tryOn) {
      tab = 2;
      tryCount++;
      unawaited(_persist());
    }
    notifyListeners();
  }

  void setShape(String value) {
    shape = value;
    preferredShape = value;
    notifyListeners();
    unawaited(_persist());
  }

  void setColor(Color value) {
    color = value;
    notifyListeners();
  }

  void setFinish(NailFinish value) {
    finish = value;
    notifyListeners();
  }

  void setLength(double value) {
    length = value.clamp(.68, 1.35).toDouble();
    notifyListeners();
  }

  void toggleOverlay() {
    showOverlay = !showOverlay;
    notifyListeners();
  }

  void toggleFavorite([PremiumLook? value]) {
    final item = value ?? look;
    if (favorites.contains(item.name)) {
      favorites.remove(item.name);
    } else {
      favorites.add(item.name);
    }
    notifyListeners();
    unawaited(_persist());
  }

  void saveCurrent() {
    if (!saved.any((e) => e.name == look.name)) saved.insert(0, look);
    notifyListeners();
    unawaited(_persist());
  }

  void rememberPng(String path) {
    savedPngPaths.remove(path);
    savedPngPaths.insert(0, path);
    saveCurrent();
    unawaited(_persist());
  }

  void clearSaved() {
    favorites.clear();
    saved.clear();
    savedPngPaths.clear();
    notifyListeners();
    unawaited(_persist());
  }

  void toggleNotifications() {
    notificationsEnabled = !notificationsEnabled;
    notifyListeners();
    unawaited(_persist());
  }

  void setProfile({String? shape, String? style}) {
    if (shape != null) preferredShape = shape;
    if (style != null) preferredStyle = style;
    notifyListeners();
    unawaited(_persist());
  }

  void setAppointment(DateTime value) {
    appointment = value;
    notifyListeners();
    unawaited(_persist());
  }

  void resetScan() {
    points.clear();
    scan = null;
    analyzing = false;
    notifyListeners();
  }

  void seedCalibration() {
    points
      ..clear()
      ..addAll(defaultPoints);
    notifyListeners();
  }

  void addPoint(Offset local, Size size) {
    if (points.length >= 5 || size.width <= 0 || size.height <= 0) return;
    points.add(Offset(
      (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
    ));
    notifyListeners();
  }

  void undoPoint() {
    if (points.isEmpty) return;
    points.removeLast();
    notifyListeners();
  }

  void clearPoints() {
    points.clear();
    notifyListeners();
  }

  Future<ScanResult?> analyzePhoto(XFile file) async {
    analyzing = true;
    notifyListeners();
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 180);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('No pixel data');

      final width = image.width;
      final height = image.height;
      final step = math.max(1, math.sqrt(width * height / 8000).floor()).toInt();
      var count = 0;
      var luminanceSum = 0.0;
      var luminanceSq = 0.0;
      var skinCount = 0;
      var sr = 0.0;
      var sg = 0.0;
      var sb = 0.0;

      for (var y = 0; y < height; y += step) {
        for (var x = 0; x < width; x += step) {
          final i = (y * width + x) * 4;
          final r = data.getUint8(i).toDouble();
          final g = data.getUint8(i + 1).toDouble();
          final b = data.getUint8(i + 2).toDouble();
          final l = .2126 * r + .7152 * g + .0722 * b;
          luminanceSum += l;
          luminanceSq += l * l;
          count++;

          final maxC = math.max(r, math.max(g, b));
          final minC = math.min(r, math.min(g, b));
          final skinLike = r > 70 && g > 40 && b > 25 && r >= g && (maxC - minC) > 12 && (r - b) > 8;
          if (skinLike) {
            skinCount++;
            sr += r;
            sg += g;
            sb += b;
          }
        }
      }

      final brightness = count == 0 ? 0.0 : luminanceSum / count;
      final variance = count == 0 ? 0.0 : (luminanceSq / count) - brightness * brightness;
      final contrast = math.sqrt(math.max(0.0, variance));
      final pixelCount = width * height;

      final avgR = skinCount == 0 ? 178.0 : sr / skinCount;
      final avgG = skinCount == 0 ? 142.0 : sg / skinCount;
      final avgB = skinCount == 0 ? 128.0 : sb / skinCount;
      final skinLum = .2126 * avgR + .7152 * avgG + .0722 * avgB;

      final tone = skinLum > 190
          ? 'Világos'
          : skinLum > 155
              ? 'Világos-közepes'
              : skinLum > 120
                  ? 'Közepes'
                  : 'Mélyebb';
      final undertone = (avgR - avgB) > 42
          ? 'meleg'
          : ((avgR - avgB).abs() < 24 ? 'semleges' : 'hűvös');

      final hand = _estimateHandShape();
      final nailBed = _estimateNailBed();
      final recommended = hand.contains('hossz')
          ? 'Ovális'
          : hand.contains('széles')
              ? 'Mandula'
              : preferredShape;

      var qualityScore = 100;
      if (brightness < 70 || brightness > 225) qualityScore -= 24;
      if (contrast < 24) qualityScore -= 22;
      if (pixelCount < 7000) qualityScore -= 20;
      if (skinCount < count * .06) qualityScore -= 14;
      if (points.length < 5) qualityScore -= 8;
      qualityScore = qualityScore.clamp(35, 100).toInt();
      final quality = qualityScore >= 82
          ? 'Kiváló'
          : qualityScore >= 68
              ? 'Jó'
              : qualityScore >= 52
                  ? 'Elfogadható'
                  : 'Fotózd újra';

      scan = ScanResult(
        tone: tone,
        undertone: undertone,
        handShape: hand,
        nailBed: nailBed,
        recommendedShape: recommended,
        quality: quality,
        qualityScore: qualityScore,
        brightness: brightness,
        contrast: contrast,
        resolution: '${image.width}×${image.height} elemzési minta',
      );

      final candidate = premiumLooks.where((p) => p.shape == recommended).firstOrNull ?? premiumLooks.first;
      select(candidate, tryOn: false);
      shape = recommended;
      image.dispose();
      codec.dispose();
      return scan;
    } catch (_) {
      scan = const ScanResult(
        tone: 'Nem meghatározható',
        undertone: 'nem meghatározható',
        handShape: 'Manuális kalibráció szükséges',
        nailBed: 'Manuális becslés',
        recommendedShape: 'Mandula',
        quality: 'Fotózd újra',
        qualityScore: 35,
        brightness: 0,
        contrast: 0,
        resolution: 'Elemzés sikertelen',
      );
      return scan;
    } finally {
      analyzing = false;
      notifyListeners();
    }
  }

  String _estimateHandShape() {
    if (points.length < 5) return 'Arányos · becslés';
    final xs = points.map((e) => e.dx).toList()..sort();
    final ys = points.map((e) => e.dy).toList()..sort();
    final spreadX = xs.last - xs.first;
    final spreadY = ys.last - ys.first;
    final ratio = spreadY == 0 ? 1.0 : spreadX / spreadY;
    if (ratio < 1.35) return 'Karcsú, hosszúkás · becslés';
    if (ratio > 2.15) return 'Szélesebb kéz · becslés';
    return 'Arányos kéz · becslés';
  }

  String _estimateNailBed() {
    if (points.length < 5) return 'Közepes · manuális becslés';
    final ordered = points.sublist(1)..sort((a, b) => a.dx.compareTo(b.dx));
    if (ordered.length < 3) return 'Közepes · manuális becslés';
    var gap = 0.0;
    for (var i = 1; i < ordered.length; i++) {
      gap += (ordered[i].dx - ordered[i - 1].dx).abs();
    }
    final avgGap = gap / (ordered.length - 1);
    if (avgGap < .105) return 'Keskenyebb · becslés';
    if (avgGap > .165) return 'Szélesebb · becslés';
    return 'Közepes · becslés';
  }

  PremiumLook recommendFromPrompt(String input) {
    final q = input.toLowerCase();
    final result = q.contains('francia') || q.contains('esküvő') || q.contains('menyasszony')
        ? premiumLooks[1]
        : q.contains('csill') || q.contains('party') || q.contains('buli') || q.contains('fény')
            ? premiumLooks[2]
            : q.contains('ősz') || q.contains('bordó') || q.contains('sötét') || q.contains('elegáns')
                ? premiumLooks[3]
                : q.contains('minimal') || q.contains('bézs') || q.contains('munka')
                    ? premiumLooks[4]
                    : premiumLooks.first;
    select(result);
    return result;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
