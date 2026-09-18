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
    required this.sharpness,
    required this.centerScore,
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
  final double sharpness;
  final int centerScore;
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
  List<Offset>? _smartPoints;
  Timer? _persistTimer;
  Future<void> _persistChain = Future<void>.value();

  static const List<Offset> defaultPoints = <Offset>[
    Offset(.79, .57),
    Offset(.30, .27),
    Offset(.45, .18),
    Offset(.60, .24),
    Offset(.72, .34),
  ];

  bool get hasSmartCalibration => _smartPoints?.length == 5 || _skinBounds != null;
  double get photoAspectRatio => photoWidth > 0 && photoHeight > 0 ? photoWidth / photoHeight : 1.0;
  String get nextCalibrationFinger {
    const names = <String>['hüvelykujj', 'mutatóujj', 'középső ujj', 'gyűrűsujj', 'kisujj'];
    return points.length >= names.length ? 'kész' : names[points.length];
  }

  PremiumLook currentSnapshot({String? name}) => PremiumLook(
        name ?? (shape == look.shape && color.toARGB32() == look.color.toARGB32() && finish == look.finish && (length - look.length).abs() <= .01 ? look.name : '${look.name} · egyedi'),
        '$shape · ${finish.name} · személyre szabva',
        color,
        currentMatchScore,
        look.image,
        shape == look.shape && color.toARGB32() == look.color.toARGB32() && finish == look.finish && (length - look.length).abs() <= .01 ? look.category : 'Egyedi',
        shape: shape,
        finish: finish,
        length: length,
      );

  String get currentLookSignature => _lookSignature(currentSnapshot());
  bool get isCurrentFavorite => favorites.contains(currentLookSignature) || favorites.contains(look.name);
  bool isFavorite(PremiumLook item) => favorites.contains(_lookSignature(item)) || favorites.contains(item.name);

  int get currentMatchScore {
    var score = 76;
    final recommended = scan?.recommendedShape;
    if (recommended != null && shape == recommended) score += 9;
    if (shape == preferredShape) score += 5;
    if (look.category == preferredStyle) score += 4;
    if (finish == look.finish) score += 2;
    if ((length - look.length).abs() <= .14) score += 2;
    if (scan != null) {
      final argb = color.toARGB32();
      final rb = ((argb >> 16) & 0xff) - (argb & 0xff);
      final warmColor = rb > 24;
      final coolColor = rb < 8;
      if (scan!.undertone == 'meleg' && warmColor) score += 2;
      if (scan!.undertone == 'hűvös' && coolColor) score += 2;
      if (scan!.undertone == 'semleges') score += 1;
      if (scan!.qualityScore < 54) score -= 3;
    }
    return score.clamp(68, 98).toInt();
  }

  String get currentMatchReason {
    final parts = <String>[];
    if (scan != null && shape == scan!.recommendedShape) parts.add('ajánlott forma');
    if (shape == preferredShape) parts.add('profilforma');
    if (look.category == preferredStyle) parts.add('kedvelt stílus');
    return parts.isEmpty ? 'stílusprofil és aktuális beállítások' : parts.join(' · ');
  }

  Offset sourcePointFromViewport(Offset local, Size viewport) {
    if (photoWidth <= 0 || photoHeight <= 0 || viewport.width <= 0 || viewport.height <= 0) {
      return Offset((local.dx / viewport.width).clamp(0.0, 1.0).toDouble(), (local.dy / viewport.height).clamp(0.0, 1.0).toDouble());
    }
    final scale = math.max(viewport.width / photoWidth, viewport.height / photoHeight);
    final renderedW = photoWidth * scale;
    final renderedH = photoHeight * scale;
    final originX = (viewport.width - renderedW) / 2;
    final originY = (viewport.height - renderedH) / 2;
    return Offset(
      ((local.dx - originX) / renderedW).clamp(0.0, 1.0).toDouble(),
      ((local.dy - originY) / renderedH).clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset viewportPointFromSource(Offset point, Size viewport) {
    if (photoWidth <= 0 || photoHeight <= 0 || viewport.width <= 0 || viewport.height <= 0) {
      return Offset(point.dx * viewport.width, point.dy * viewport.height);
    }
    final scale = math.max(viewport.width / photoWidth, viewport.height / photoHeight);
    final renderedW = photoWidth * scale;
    final renderedH = photoHeight * scale;
    final originX = (viewport.width - renderedW) / 2;
    final originY = (viewport.height - renderedH) / 2;
    return Offset(originX + point.dx * renderedW, originY + point.dy * renderedH);
  }

  List<Offset> pointsForViewport(Size viewport) => points.map((p) {
        final q = viewportPointFromSource(p, viewport);
        return Offset((q.dx / viewport.width).clamp(-.5, 1.5).toDouble(), (q.dy / viewport.height).clamp(-.5, 1.5).toDouble());
      }).toList(growable: false);

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

      points.clear();
      final pointSpace = raw['pointSpace'] as String?;
      if (pointSpace == 'source-v1') {
        points.addAll((raw['points'] as List<dynamic>? ?? const [])
            .whereType<List<dynamic>>()
            .where((e) => e.length >= 2 && e[0] is num && e[1] is num)
            .map((e) => Offset((e[0] as num).toDouble().clamp(0.0, 1.0), (e[1] as num).toDouble().clamp(0.0, 1.0))));
      }

      photoWidth = raw['photoWidth'] as int? ?? 0;
      photoHeight = raw['photoHeight'] as int? ?? 0;
      final storedPhoto = raw['lastPhotoPath'] as String?;
      lastPhotoPath = storedPhoto != null && await File(storedPhoto).exists() ? storedPhoto : null;
      final scanAtRaw = raw['lastScanAt'] as String?;
      lastScanAt = scanAtRaw == null ? null : DateTime.tryParse(scanAtRaw);
      final appointmentRaw = raw['appointment'] as String?;
      appointment = appointmentRaw == null ? null : DateTime.tryParse(appointmentRaw);
      notifyListeners();
      if (savedPngPaths.length != ((raw['savedPngPaths'] as List<dynamic>? ?? const []).length)) _schedulePersist();
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
      final previous = lastPhotoPath;
      if (sourceFile.absolute.path != target.absolute.path) await sourceFile.copy(target.path);
      if (previous != null && previous != target.path && previous.startsWith('${dir.path}${Platform.pathSeparator}')) {
        final old = File(previous);
        if (await old.exists()) await old.delete();
      }
      lastPhotoPath = target.path;
      _schedulePersist();
      return XFile(target.path);
    } catch (_) {
      lastPhotoPath = source.path;
      _schedulePersist();
      return source;
    }
  }

  void _schedulePersist({Duration delay = const Duration(milliseconds: 180)}) {
    _persistTimer?.cancel();
    _persistTimer = Timer(delay, () {
      _persistChain = _persistChain.then((_) => _persist()).catchError((_) {});
    });
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
        'pointSpace': 'source-v1',
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
    _schedulePersist();
  }

  void setShape(String value) {
    shape = value;
    preferredShape = value;
    notifyListeners();
    _schedulePersist();
  }

  void setColor(Color value) {
    color = value;
    notifyListeners();
    _schedulePersist();
  }

  void setFinish(NailFinish value) {
    finish = value;
    notifyListeners();
    _schedulePersist();
  }

  void setLength(double value) {
    length = value.clamp(.68, 1.35).toDouble();
    notifyListeners();
    _schedulePersist();
  }

  void toggleOverlay() {
    showOverlay = !showOverlay;
    notifyListeners();
  }

  void toggleFavorite([PremiumLook? value]) {
    final item = value ?? currentSnapshot();
    final signature = _lookSignature(item);
    final legacyName = value?.name ?? look.name;
    final selected = favorites.contains(signature) || favorites.contains(legacyName);
    favorites.remove(signature);
    favorites.remove(legacyName);
    if (!selected) {
      favorites.add(signature);
      if (!saved.any((e) => _lookSignature(e) == signature)) saved.insert(0, item);
    }
    notifyListeners();
    _schedulePersist();
  }

  void saveCurrent() {
    final item = currentSnapshot();
    final signature = _lookSignature(item);
    saved.removeWhere((e) => _lookSignature(e) == signature);
    saved.insert(0, item);
    notifyListeners();
    _schedulePersist();
  }

  String _lookSignature(PremiumLook p) => '${p.name}|${p.shape}|${p.color.toARGB32()}|${p.finish.name}|${p.length.toStringAsFixed(2)}';

  void rememberPng(String path) {
    savedPngPaths.remove(path);
    savedPngPaths.insert(0, path);
    saveCurrent();
    _schedulePersist();
  }

  Future<void> clearHandData() async {
    final path = lastPhotoPath;
    lastPhotoPath = null;
    photoWidth = 0;
    photoHeight = 0;
    points.clear();
    scan = null;
    lastScanAt = null;
    _skinBounds = null;
    _smartPoints = null;
    notifyListeners();
    _schedulePersist(delay: Duration.zero);
    if (path != null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        if (path.startsWith('${dir.path}${Platform.pathSeparator}')) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> removePng(String path) async {
    savedPngPaths.remove(path);
    notifyListeners();
    _schedulePersist(delay: Duration.zero);
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void clearSaved() {
    for (final path in List<String>.from(savedPngPaths)) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    favorites.clear();
    saved.clear();
    savedPngPaths.clear();
    notifyListeners();
    _schedulePersist();
  }

  void toggleNotifications() {
    notificationsEnabled = !notificationsEnabled;
    notifyListeners();
    _schedulePersist();
  }

  void setProfile({String? shape, String? style}) {
    if (shape != null) preferredShape = shape;
    if (style != null) preferredStyle = style;
    notifyListeners();
    _schedulePersist();
  }

  void setAppointment(DateTime value) {
    appointment = value;
    notifyListeners();
    _schedulePersist();
  }

  void resetScan() {
    points.clear();
    scan = null;
    analyzing = false;
    _skinBounds = null;
    _smartPoints = null;
    notifyListeners();
    _schedulePersist();
  }

  void seedCalibration() {
    final b = _skinBounds;
    points
      ..clear()
      ..addAll(_smartPoints?.length == 5
          ? _smartPoints!
          : b == null
              ? defaultPoints
              : <Offset>[
                  Offset(b.left + b.width * .88, b.top + b.height * .55),
                  Offset(b.left + b.width * .20, b.top + b.height * .25),
                  Offset(b.left + b.width * .41, b.top + b.height * .14),
                  Offset(b.left + b.width * .62, b.top + b.height * .22),
                  Offset(b.left + b.width * .78, b.top + b.height * .34),
                ].map((p) => Offset(p.dx.clamp(.02, .98).toDouble(), p.dy.clamp(.02, .98).toDouble())));
    _refreshGeometryFromPoints();
    notifyListeners();
    _schedulePersist();
  }

  void addPoint(Offset local, Size size) {
    if (points.length >= 5 || size.width <= 0 || size.height <= 0) return;
    points.add(sourcePointFromViewport(local, size));
    _refreshGeometryFromPoints();
    notifyListeners();
    _schedulePersist();
  }

  void moveNearestPoint(Offset local, Size size, {double maxDistance = 72}) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final p = viewportPointFromSource(points[i], size);
      final d = (p - local).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (best < 0 || bestDistance > maxDistance) return;
    points[best] = sourcePointFromViewport(local, size);
    _refreshGeometryFromPoints();
    notifyListeners();
    _schedulePersist();
  }

  void undoPoint() {
    if (points.isEmpty) return;
    points.removeLast();
    _refreshGeometryFromPoints();
    notifyListeners();
    _schedulePersist();
  }

  void clearPoints() {
    points.clear();
    _refreshGeometryFromPoints();
    notifyListeners();
    _schedulePersist();
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
      var gradientSum = 0.0;
      var gradientCount = 0;
      var darkCount = 0;
      var brightCount = 0;
      final skinSamples = <Offset>[];

      for (var y = 0; y < height; y += step) {
        double? previousLuminance;
        for (var x = 0; x < width; x += step) {
          final i = (y * width + x) * 4;
          final r = data.getUint8(i).toDouble();
          final g = data.getUint8(i + 1).toDouble();
          final b = data.getUint8(i + 2).toDouble();
          final l = .2126 * r + .7152 * g + .0722 * b;
          luminanceSum += l;
          luminanceSq += l * l;
          if (l < 28) darkCount++;
          if (l > 245) brightCount++;
          if (previousLuminance != null) {
            gradientSum += (l - previousLuminance).abs();
            gradientCount++;
          }
          previousLuminance = l;
          count++;

          final maxC = math.max(r, math.max(g, b));
          final minC = math.min(r, math.min(g, b));
          final skinLike = r > 65 && g > 35 && b > 20 && r >= g * .92 && r > b && (maxC - minC) > 10 && (r - b) > 6;
          if (skinLike) {
            skinCount++;
            sr += r;
            sg += g;
            sb += b;
            skinSamples.add(Offset(x / width, y / height));
          }
        }
      }

      final brightness = count == 0 ? 0.0 : luminanceSum / count;
      final variance = count == 0 ? 0.0 : (luminanceSq / count) - brightness * brightness;
      final contrast = math.sqrt(math.max(0.0, variance));
      final originalPixels = photoWidth * photoHeight;
      final skinCoverage = count == 0 ? 0.0 : skinCount / count;
      final sharpness = gradientCount == 0 ? 0.0 : gradientSum / gradientCount;
      final darkRatio = count == 0 ? 0.0 : darkCount / count;
      final brightRatio = count == 0 ? 0.0 : brightCount / count;

      if (skinSamples.length > 24) {
        final xs = skinSamples.map((p) => p.dx).toList()..sort();
        final ys = skinSamples.map((p) => p.dy).toList()..sort();
        double q(List<double> values, double p) => values[((values.length - 1) * p).round().clamp(0, values.length - 1).toInt()];
        final left = q(xs, .025);
        final right = q(xs, .975);
        final top = q(ys, .025);
        final bottom = q(ys, .975);
        final padX = (right - left) * .04;
        final padY = (bottom - top) * .035;
        _skinBounds = Rect.fromLTRB(
          (left - padX).clamp(0.0, 1.0).toDouble(),
          (top - padY).clamp(0.0, 1.0).toDouble(),
          (right + padX).clamp(0.0, 1.0).toDouble(),
          (bottom + padY).clamp(0.0, 1.0).toDouble(),
        );
        _smartPoints = _deriveSmartPoints(skinSamples, _skinBounds!);
      } else {
        _skinBounds = null;
        _smartPoints = null;
      }

      final center = _skinBounds?.center;
      final centerDistance = center == null ? 1.0 : math.sqrt(math.pow(center.dx - .5, 2) + math.pow(center.dy - .5, 2));
      final centerScore = (100 - centerDistance * 155).clamp(0, 100).round();

      var toneCount = skinCount;
      var toneR = sr;
      var toneG = sg;
      var toneB = sb;
      final robustBounds = _skinBounds;
      if (robustBounds != null) {
        toneCount = 0;
        toneR = 0;
        toneG = 0;
        toneB = 0;
        for (var y = 0; y < height; y += step) {
          final ny = y / height;
          if (ny < robustBounds.top || ny > robustBounds.bottom) continue;
          for (var x = 0; x < width; x += step) {
            final nx = x / width;
            if (nx < robustBounds.left || nx > robustBounds.right) continue;
            final i = (y * width + x) * 4;
            final r = data.getUint8(i).toDouble();
            final g = data.getUint8(i + 1).toDouble();
            final b = data.getUint8(i + 2).toDouble();
            final maxC = math.max(r, math.max(g, b));
            final minC = math.min(r, math.min(g, b));
            final skinLike = r > 65 && g > 35 && b > 20 && r >= g * .92 && r > b && (maxC - minC) > 10 && (r - b) > 6;
            if (!skinLike) continue;
            toneCount++;
            toneR += r;
            toneG += g;
            toneB += b;
          }
        }
      }

      final avgR = toneCount == 0 ? 178.0 : toneR / toneCount;
      final avgG = toneCount == 0 ? 142.0 : toneG / toneCount;
      final avgB = toneCount == 0 ? 128.0 : toneB / toneCount;
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
        qualityScore -= 18;
        hints.add('Kevés a részlet/kontraszt');
      }
      if (sharpness < 8.5) {
        qualityScore -= 18;
        hints.add('A kép bemozdult vagy életlen');
      }
      if (darkRatio > .18) {
        qualityScore -= 10;
        hints.add('Sok az elveszett sötét részlet');
      }
      if (brightRatio > .14) {
        qualityScore -= 10;
        hints.add('Sok a kiégett világos részlet');
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
      if (centerScore < 55) {
        qualityScore -= 12;
        hints.add('Tedd közelebb a kép közepéhez a kezed');
      }
      if (photoAspectRatio > 1.35) {
        qualityScore -= 8;
        hints.add('Álló képnél pontosabb a kalibráció');
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
        sharpness: sharpness,
        centerScore: centerScore,
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
      _schedulePersist();
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
        sharpness: 0,
        centerScore: 0,
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

  List<Offset> _deriveSmartPoints(List<Offset> samples, Rect bounds) {
    if (samples.length < 25 || bounds.width <= .08 || bounds.height <= .12) return const <Offset>[];

    Offset fingerTip(double fraction) {
      final cx = bounds.left + bounds.width * fraction;
      final halfWindow = bounds.width * .075;
      final candidates = samples
          .where((p) => (p.dx - cx).abs() <= halfWindow && p.dy <= bounds.top + bounds.height * .58)
          .toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
      if (candidates.isEmpty) return Offset(cx, bounds.top + bounds.height * .22);
      final take = math.max(1, (candidates.length * .16).round());
      final top = candidates.take(take).toList();
      final x = top.map((p) => p.dx).reduce((a, b) => a + b) / top.length;
      final y = top.map((p) => p.dy).reduce((a, b) => a + b) / top.length + bounds.height * .025;
      return Offset(x.clamp(.02, .98).toDouble(), y.clamp(.02, .98).toDouble());
    }

    final midTop = bounds.top + bounds.height * .30;
    final midBottom = bounds.top + bounds.height * .78;
    final leftSide = samples.where((p) => p.dx <= bounds.left + bounds.width * .18 && p.dy >= midTop && p.dy <= midBottom).length;
    final rightSide = samples.where((p) => p.dx >= bounds.right - bounds.width * .18 && p.dy >= midTop && p.dy <= midBottom).length;
    final thumbRight = rightSide >= leftSide;
    final thumbCandidates = samples.where((p) {
      final side = thumbRight ? p.dx >= bounds.left + bounds.width * .67 : p.dx <= bounds.left + bounds.width * .33;
      return side && p.dy >= bounds.top + bounds.height * .28 && p.dy <= bounds.top + bounds.height * .78;
    }).toList()
      ..sort((a, b) => thumbRight ? b.dx.compareTo(a.dx) : a.dx.compareTo(b.dx));
    Offset thumb;
    if (thumbCandidates.isEmpty) {
      thumb = Offset(thumbRight ? bounds.left + bounds.width * .88 : bounds.left + bounds.width * .12, bounds.top + bounds.height * .55);
    } else {
      final take = math.max(1, (thumbCandidates.length * .14).round());
      final edge = thumbCandidates.take(take).toList();
      final x = edge.map((p) => p.dx).reduce((a, b) => a + b) / edge.length;
      final y = edge.map((p) => p.dy).reduce((a, b) => a + b) / edge.length;
      thumb = Offset(x.clamp(.02, .98).toDouble(), y.clamp(.02, .98).toDouble());
    }

    final fractions = thumbRight ? const <double>[.20, .41, .62, .78] : const <double>[.80, .59, .38, .22];
    return <Offset>[thumb, ...fractions.map(fingerTip)];
  }

  void _refreshGeometryFromPoints() {
    final current = scan;
    if (current == null) return;
    final hand = _estimateHandShape();
    final nailBed = _estimateNailBed();
    final recommended = hand.contains('hossz')
        ? 'Ovális'
        : hand.contains('széles')
            ? 'Mandula'
            : preferredShape;
    scan = ScanResult(
      tone: current.tone,
      undertone: current.undertone,
      handShape: hand,
      nailBed: nailBed,
      recommendedShape: recommended,
      quality: current.quality,
      qualityScore: current.qualityScore,
      brightness: current.brightness,
      contrast: current.contrast,
      resolution: current.resolution,
      skinCoverage: current.skinCoverage,
      sharpness: current.sharpness,
      centerScore: current.centerScore,
      hint: current.hint,
    );
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
    if (points.length < 5) return 'Közepes · virtuális skála';
    final ordered = points.sublist(1)..sort((a, b) => a.dx.compareTo(b.dx));
    if (ordered.length < 3) return 'Közepes · virtuális skála';
    var gap = 0.0;
    for (var i = 1; i < ordered.length; i++) {
      gap += (ordered[i].dx - ordered[i - 1].dx).abs() * photoAspectRatio;
    }
    final avgGap = gap / (ordered.length - 1);
    if (avgGap < .085) return 'Keskenyebb · virtuális skála';
    if (avgGap > .16) return 'Szélesebb · virtuális skála';
    return 'Közepes · virtuális skála';
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistChain = _persistChain.then((_) => _persist()).catchError((_) {});
    super.dispose();
  }

  PremiumLook recommendFromPrompt(String input) {
    final q = input.toLowerCase().trim();
    final scores = List<int>.filled(premiumLooks.length, 0);

    for (var i = 0; i < premiumLooks.length; i++) {
      final item = premiumLooks[i];
      if (item.category.toLowerCase() == preferredStyle.toLowerCase()) scores[i] += 3;
      if (item.shape == preferredShape) scores[i] += 2;
      if (scan != null && item.shape == scan!.recommendedShape) scores[i] += 2;
      if (q.contains(item.shape.toLowerCase())) scores[i] += 4;
      if (q.contains(item.category.toLowerCase())) scores[i] += 4;
    }

    void add(int index, int points, List<String> words) {
      for (final word in words) {
        if (q.contains(word)) scores[index] += points;
      }
    }

    add(0, 5, const ['rózsaszín', 'rozsaszin', 'pink', 'romantikus', 'randi', 'pasztell', 'soft', 'nude']);
    add(1, 7, const ['francia', 'french', 'esküvő', 'eskuvo', 'menyasszony', 'bridal', 'fehér', 'feher', 'klasszikus', 'clean']);
    add(2, 7, const ['csillám', 'csillam', 'glitter', 'party', 'buli', 'ünnep', 'unnep', 'szilveszter', 'fényes', 'fenyes', 'ragyog']);
    add(3, 6, const ['ősz', 'osz', 'bordó', 'bordo', 'burgundy', 'borvörös', 'borvoros', 'sötét', 'sotet', 'fekete', 'vacsora', 'drámai', 'dramatic']);
    add(4, 6, const ['minimal', 'bézs', 'bezs', 'munka', 'office', 'iroda', 'természetes', 'termeszetes', 'visszafogott']);

    add(3, 3, const ['elegáns', 'elegans', 'luxus', 'esti']);
    add(1, 2, const ['elegáns', 'elegans', 'alkalmi']);
    add(4, 3, const ['hétköznap', 'hetkoznap', 'mindennapi']);
    add(0, 2, const ['tavasz', 'nyár', 'nyar']);

    var bestIndex = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[bestIndex]) bestIndex = i;
    }
    final result = premiumLooks[bestIndex];
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
