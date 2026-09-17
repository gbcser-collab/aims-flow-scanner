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
    required this.skinCoverage,
    required this.hint,
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
  final double skinCoverage;
  final String hint;
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
  String? lastPhotoPath;
  int photoWidth = 0;
  int photoHeight = 0;
  DateTime? lastScanAt;

  String shape = premiumLooks.first.shape;
  Color color = premiumLooks.first.color;
  NailFinish finish = premiumLooks.first.finish;
  double length = premiumLooks.first.length;

  Rect? _skinBounds;

  static const List<Offset> defaultPoints = <Offset>[
    Offset(.79, .57),
    Offset(.30, .27),
    Offset(.45, .18),
    Offset(.60, .24),
    Offset(.72, .34),
  ];

  bool get hasSmartCalibration => _skinBounds != null;
  double get photoAspectRatio => photoWidth > 0 && photoHeight > 0 ? photoWidth / photoHeight : 1.0;

  Future<File> get _stateFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nailfit_state_v4.json');
  }

  Future<void> restore() async {
    try {
      final file = await _stateFile;
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      favorites
        ..clear()
        ..addAll((raw['favorites'] as List<dynamic>? ?? const []).map((e) => '$e'));

      savedPngPaths.clear();
      for (final value in (raw['savedPngPaths'] as List<dynamic>? ?? const [])) {
        final path = '$value';
        if (await File(path).exists()) savedPngPaths.add(path);
      }

      saved.clear();
      final rawSaved = raw['savedLooks'] as List<dynamic>?;
      if (rawSaved != null) {
        saved.addAll(rawSaved.whereType<Map<String, dynamic>>().map(_lookFromJson));
      } else {
        saved.addAll((raw['saved'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => premiumLooks.where((p) => p.name == '$e').firstOrNull)
            .whereType<PremiumLook>());
      }

      notificationsEnabled = raw['notificationsEnabled'] as bool? ?? true;
      tryCount = raw['tryCount'] as int? ?? 0;
      preferredShape = raw['preferredShape'] as String? ?? 'Mandula';
      preferredStyle = raw['preferredStyle'] as String? ?? 'Nude';
      shape = raw['shape'] as String? ?? preferredShape;
      final colorValue = raw['color'] as int?;
      if (colorValue != null) color = Color(colorValue);
      final finishName = raw['finish'] as String?;
      if (finishName != null) finish = NailFinish.values.where((e) => e.name == finishName).firstOrNull ?? finish;
      length = (raw['length'] as num?)?.toDouble().clamp(.68, 1.35).toDouble() ?? length;

      points
        ..clear()
        ..addAll((raw['points'] as List<dynamic>? ?? const []).whereType<List<dynamic>>().where((e) => e.length >= 2).map((e) => Offset((e[0] as num).toDouble(), (e[1] as num).toDouble())));

      photoWidth = raw['photoWidth'] as int? ?? 0;
      photoHeight = raw['photoHeight'] as int? ?? 0;
      final storedPhoto = raw['lastPhotoPath'] as String?;
      lastPhotoPath = storedPhoto != null && await File(storedPhoto).exists() ? storedPhoto : null;
      final scanAtRaw = raw['lastScanAt'] as String?;
      lastScanAt = scanAtRaw == null ? null : DateTime.tryParse(scanAtRaw);
      final appointmentRaw = raw['appointment'] as String?;
      appointment = appointmentRaw == null ? null : DateTime.tryParse(appointmentRaw);
      notifyListeners();
      if (savedPngPaths.length != ((raw['savedPngPaths'] as List<dynamic>? ?? const []).length)) unawaited(_persist());
    } catch (_) {
      // A sérült helyi állapot nem akadályozhatja az app indulását.
    }
  }

  Future<XFile> rememberPhoto(XFile source) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = source.path.contains('.') ? source.path.substring(source.path.lastIndexOf('.')) : '.jpg';
      final target = File('${dir.path}/nailfit_last_hand$ext');
      final sourceFile = File(source.path);
      if (sourceFile.absolute.path != target.absolute.path) await sourceFile.copy(target.path);
      lastPhotoPath = target.path;
      unawaited(_persist());
      return XFile(target.path);
    } catch (_) {
      lastPhotoPath = source.path;
      unawaited(_persist());
      return source;
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _stateFile;
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'favorites': favorites.toList(),
        'saved': saved.map((e) => e.name).toList(),
        'savedLooks': saved.map(_lookToJson).toList(),
        'savedPngPaths': savedPngPaths,
        'notificationsEnabled': notificationsEnabled,
        'tryCount': tryCount,
        'preferredShape': preferredShape,
        'preferredStyle': preferredStyle,
        'shape': shape,
        'color': color.toARGB32(),
        'finish': finish.name,
        'length': length,
        'points': points.map((e) => <double>[e.dx, e.dy]).toList(),
        'lastPhotoPath': lastPhotoPath,
        'photoWidth': photoWidth,
        'photoHeight': photoHeight,
        'lastScanAt': lastScanAt?.toIso8601String(),
        'appointment': appointment?.toIso8601String(),
      }), flush: true);
    } catch (_) {
      // Best effort: a futó állapot mentés nélkül is használható.
    }
  }

  Map<String, dynamic> _lookToJson(PremiumLook p) => <String, dynamic>{
        'name': p.name,
        'subtitle': p.subtitle,
        'color': p.color.toARGB32(),
        'match': p.match,
        'image': p.image,
        'category': p.category,
        'shape': p.shape,
        'finish': p.finish.name,
        'length': p.length,
      };

  PremiumLook _lookFromJson(Map<String, dynamic> raw) => PremiumLook(
        raw['name'] as String? ?? 'Mentett look',
        raw['subtitle'] as String? ?? 'Saját beállítás',
        Color(raw['color'] as int? ?? nfRose.toARGB32()),
        raw['match'] as int? ?? 90,
        raw['image'] as String? ?? nfHeroUrl,
        raw['category'] as String? ?? 'Egyedi',
        shape: raw['shape'] as String? ?? 'Mandula',
        finish: NailFinish.values.where((e) => e.name == raw['finish']).firstOrNull ?? NailFinish.glossy,
        length: (raw['length'] as num?)?.toDouble() ?? 1.0,
      );

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
    }
    notifyListeners();
    unawaited(_persist());
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
    unawaited(_persist());
  }

  void setFinish(NailFinish value) {
    finish = value;
    notifyListeners();
    unawaited(_persist());
  }

  void setLength(double value) {
    length = value.clamp(.68, 1.35).toDouble();
    notifyListeners();
    unawaited(_persist());
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
    final customized = shape != look.shape || color.toARGB32() != look.color.toARGB32() || finish != look.finish || (length - look.length).abs() > .01;
    final item = customized
        ? PremiumLook(
            '${look.name} · egyedi',
            '$shape · ${finish.name} · saját finomhangolás',
            color,
            look.match,
            look.image,
            'Egyedi',
            shape: shape,
            finish: finish,
            length: length,
          )
        : look;
    final signature = _lookSignature(item);
    saved.removeWhere((e) => _lookSignature(e) == signature);
    saved.insert(0, item);
    notifyListeners();
    unawaited(_persist());
  }

  String _lookSignature(PremiumLook p) => '${p.name}|${p.shape}|${p.color.toARGB32()}|${p.finish.name}|${p.length.toStringAsFixed(2)}';

  void rememberPng(String path) {
    savedPngPaths.remove(path);
    savedPngPaths.insert(0, path);
    saveCurrent();
    unawaited(_persist());
  }

  void clearSaved() {
    for (final path in List<String>.from(savedPngPaths)) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
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
    _skinBounds = null;
    notifyListeners();
    unawaited(_persist());
  }

  void seedCalibration() {
    final b = _skinBounds;
    points
      ..clear()
      ..addAll(b == null
          ? defaultPoints
          : <Offset>[
              Offset(b.left + b.width * .88, b.top + b.height * .55),
              Offset(b.left + b.width * .20, b.top + b.height * .25),
              Offset(b.left + b.width * .41, b.top + b.height * .14),
              Offset(b.left + b.width * .62, b.top + b.height * .22),
              Offset(b.left + b.width * .78, b.top + b.height * .34),
            ].map((p) => Offset(p.dx.clamp(.02, .98).toDouble(), p.dy.clamp(.02, .98).toDouble())));
    notifyListeners();
    unawaited(_persist());
  }

  void addPoint(Offset local, Size size) {
    if (points.length >= 5 || size.width <= 0 || size.height <= 0) return;
    points.add(Offset(
      (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
    ));
    notifyListeners();
    unawaited(_persist());
  }

  void undoPoint() {
    if (points.isEmpty) return;
    points.removeLast();
    notifyListeners();
    unawaited(_persist());
  }

  void clearPoints() {
    points.clear();
    notifyListeners();
    unawaited(_persist());
  }

  Future<ScanResult?> analyzePhoto(XFile file) async {
    analyzing = true;
    notifyListeners();
    ui.Codec? originalCodec;
    ui.Image? originalImage;
    ui.Codec? analysisCodec;
    ui.Image? analysisImage;
    try {
      final bytes = await file.readAsBytes();

      originalCodec = await ui.instantiateImageCodec(bytes);
      final originalFrame = await originalCodec.getNextFrame();
      originalImage = originalFrame.image;
      photoWidth = originalImage.width;
      photoHeight = originalImage.height;

      analysisCodec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      final analysisFrame = await analysisCodec.getNextFrame();
      analysisImage = analysisFrame.image;
      final data = await analysisImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('No pixel data');

      final width = analysisImage.width;
      final height = analysisImage.height;
      final step = math.max(1, math.sqrt(width * height / 14000).floor()).toInt();
      var count = 0;
      var luminanceSum = 0.0;
      var luminanceSq = 0.0;
      var skinCount = 0;
      var sr = 0.0;
      var sg = 0.0;
      var sb = 0.0;
      var minX = width;
      var maxX = 0;
      var minY = height;
      var maxY = 0;

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
          final skinLike = r > 65 && g > 35 && b > 20 && r >= g * .92 && r > b && (maxC - minC) > 10 && (r - b) > 6;
          if (skinLike) {
            skinCount++;
            sr += r;
            sg += g;
            sb += b;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      final brightness = count == 0 ? 0.0 : luminanceSum / count;
      final variance = count == 0 ? 0.0 : (luminanceSq / count) - brightness * brightness;
      final contrast = math.sqrt(math.max(0.0, variance));
      final originalPixels = photoWidth * photoHeight;
      final skinCoverage = count == 0 ? 0.0 : skinCount / count;

      if (skinCount > 20 && maxX > minX && maxY > minY) {
        final padX = (maxX - minX) * .05;
        final padY = (maxY - minY) * .04;
        _skinBounds = Rect.fromLTRB(
          ((minX - padX) / width).clamp(0.0, 1.0).toDouble(),
          ((minY - padY) / height).clamp(0.0, 1.0).toDouble(),
          ((maxX + padX) / width).clamp(0.0, 1.0).toDouble(),
          ((maxY + padY) / height).clamp(0.0, 1.0).toDouble(),
        );
      } else {
        _skinBounds = null;
      }

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
      final redBlue = avgR - avgB;
      final greenBalance = avgG - avgB;
      final undertone = redBlue > 48 && greenBalance > 8
          ? 'meleg'
          : redBlue < 28
              ? 'hűvös'
              : 'semleges';

      final hand = _estimateHandShape();
      final nailBed = _estimateNailBed();
      final recommended = hand.contains('hossz')
          ? 'Ovális'
          : hand.contains('széles')
              ? 'Mandula'
              : preferredShape;

      var qualityScore = 100;
      final hints = <String>[];
      if (brightness < 65) {
        qualityScore -= 24;
        hints.add('Túl sötét a kép');
      } else if (brightness > 225) {
        qualityScore -= 20;
        hints.add('Túl erős a fény');
      }
      if (contrast < 22) {
        qualityScore -= 22;
        hints.add('Kevés a részlet/kontraszt');
      }
      if (originalPixels < 700000) {
        qualityScore -= 18;
        hints.add('Alacsony a felbontás');
      }
      if (skinCoverage < .055) {
        qualityScore -= 20;
        hints.add('A kéz túl kicsi vagy nem jól felismerhető');
      } else if (skinCoverage > .82) {
        qualityScore -= 8;
        hints.add('Hagyj egy kis teret a kéz körül');
      }
      qualityScore = qualityScore.clamp(30, 100).toInt();
      final quality = qualityScore >= 84
          ? 'Kiváló'
          : qualityScore >= 70
              ? 'Jó'
              : qualityScore >= 54
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
        resolution: '${photoWidth}×$photoHeight',
        skinCoverage: skinCoverage,
        hint: hints.isEmpty ? 'A kép alkalmas a Try-Onhoz.' : hints.join(' · '),
      );
      lastScanAt = DateTime.now();

      final candidate = premiumLooks.where((p) => p.shape == recommended).firstOrNull ?? premiumLooks.first;
      look = candidate;
      shape = recommended;
      color = candidate.color;
      finish = candidate.finish;
      length = candidate.length;
      notifyListeners();
      unawaited(_persist());
      return scan;
    } catch (_) {
      scan = const ScanResult(
        tone: 'Nem meghatározható',
        undertone: 'nem meghatározható',
        handShape: 'Manuális kalibráció szükséges',
        nailBed: 'Manuális becslés',
        recommendedShape: 'Mandula',
        quality: 'Fotózd újra',
        qualityScore: 30,
        brightness: 0,
        contrast: 0,
        resolution: 'Elemzés sikertelen',
        skinCoverage: 0,
        hint: 'A képet nem sikerült biztonságosan feldolgozni.',
      );
      return scan;
    } finally {
      originalImage?.dispose();
      originalCodec?.dispose();
      analysisImage?.dispose();
      analysisCodec?.dispose();
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
    final correctedX = spreadX * photoAspectRatio;
    final ratio = spreadY == 0 ? 1.0 : correctedX / spreadY;
    if (ratio < 1.08) return 'Karcsú, hosszúkás · becslés';
    if (ratio > 1.85) return 'Szélesebb kéz · becslés';
    return 'Arányos kéz · becslés';
  }

  String _estimateNailBed() {
    if (points.length < 5) return 'Közepes · manuális becslés';
    final ordered = points.sublist(1)..sort((a, b) => a.dx.compareTo(b.dx));
    if (ordered.length < 3) return 'Közepes · manuális becslés';
    var gap = 0.0;
    for (var i = 1; i < ordered.length; i++) {
      gap += (ordered[i].dx - ordered[i - 1].dx).abs() * photoAspectRatio;
    }
    final avgGap = gap / (ordered.length - 1);
    if (avgGap < .085) return 'Keskenyebb · becslés';
    if (avgGap > .16) return 'Szélesebb · becslés';
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
