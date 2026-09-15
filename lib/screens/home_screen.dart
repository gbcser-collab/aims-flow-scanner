import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openScanner() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final backs = cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      if (backs.isEmpty && cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nem található kamera.')));
        return;
      }
      final camera = backs.isNotEmpty ? backs.first : cameras.first;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerPage(camera: camera)));
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kamera hiba: ${e.code}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AIMS Flow Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF171A1F), borderRadius: BorderRadius.circular(24)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AIMS FLOW', style: TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                SizedBox(height: 10),
                Text('CMR Scanner', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Élő dokumentumfelismerés • autofókusz • auto-capture', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _openScanner, icon: const Icon(Icons.document_scanner_rounded), label: const Text('Scanner megnyitása')),
            const SizedBox(height: 12),
            const Text(
              'A kamera folyamatosan ellenőrzi a dokumentum éleit, fényerejét és élességét. Ha a CMR stabil és jól olvasható, automatikusan elkészíti a képet.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.camera});
  final CameraDescription camera;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _controller;
  final _detector = _LiveDocumentDetector();

  bool _busy = false;
  bool _streaming = false;
  bool _autoCapture = true;
  String? _error;
  String? _photoPath;
  _DocumentQuality _quality = const _DocumentQuality.empty();
  _DocumentQuality? _capturedQuality;
  Offset? _focusPoint;
  int _lastAnalysisMs = 0;
  int _stableFrames = 0;
  Rect? _lastDetectedRect;
  int _cameraGeneration = 0;
  DateTime? _lastCaptureAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    final generation = ++_cameraGeneration;
    await _disposeCamera(invalidateGeneration: false);

    if (mounted) {
      setState(() {
        _error = null;
        _quality = const _DocumentQuality.empty();
        _stableFrames = 0;
      });
    }

    for (final preset in const [ResolutionPreset.veryHigh, ResolutionPreset.high, ResolutionPreset.medium]) {
      final candidate = CameraController(widget.camera, preset, enableAudio: false);
      try {
        await candidate.initialize();
        if (!mounted || generation != _cameraGeneration) {
          await candidate.dispose();
          return;
        }

        try {
          await candidate.setFlashMode(FlashMode.off);
        } catch (_) {}
        try {
          await candidate.setFocusMode(FocusMode.auto);
        } catch (_) {}
        try {
          await candidate.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        try {
          await candidate.setJpegImageQuality(95);
        } catch (_) {}

        _controller = candidate;
        if (mounted) setState(() => _error = null);
        await _startAnalysis();
        return;
      } on CameraException catch (e) {
        await candidate.dispose();
        _error = '${e.code}: ${e.description ?? ''}';
      } catch (e) {
        await candidate.dispose();
        _error = 'camera-init: $e';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _startAnalysis() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _streaming || _photoPath != null) return;
    try {
      await c.startImageStream(_onCameraImage);
      _streaming = true;
    } catch (e) {
      // A scanner ettől még használható marad: fókusz + kézi fotó működik.
      _streaming = false;
      if (mounted) {
        setState(() {
          _quality = const _DocumentQuality(
            documentFound: false,
            sharpEnough: false,
            brightnessOk: false,
            confidence: 0,
            sharpness: 0,
            brightness: 0,
            detectedRect: null,
            status: 'Élő elemzés nem elérhető • koppints a fókuszhoz',
          );
        });
      }
    }
  }

  Future<void> _stopAnalysis() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  void _onCameraImage(CameraImage image) {
    if (_busy || _photoPath != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAnalysisMs < 170) return;
    _lastAnalysisMs = now;

    final q = _detector.analyze(image);
    final previous = _lastDetectedRect;
    final stableRect = q.detectedRect != null && previous != null && _rectDistance(q.detectedRect!, previous) < 0.12;
    final good = q.documentFound && q.sharpEnough && q.brightnessOk;

    if (good && (previous == null || stableRect)) {
      _stableFrames = math.min(_stableFrames + 1, 8);
    } else {
      _stableFrames = math.max(0, _stableFrames - 2);
    }
    _lastDetectedRect = q.detectedRect;

    final stableProgress = (_stableFrames / 7).clamp(0.0, 1.0);
    final display = q.withStatus(_statusFor(q, stableProgress));
    if (mounted) setState(() => _quality = display);

    final recentlyCaptured = _lastCaptureAt != null && DateTime.now().difference(_lastCaptureAt!) < const Duration(seconds: 2);
    if (_autoCapture && good && stableProgress >= 1 && !recentlyCaptured && !_busy) {
      _lastCaptureAt = DateTime.now();
      unawaited(_takePicture(auto: true));
    }
  }

  static double _rectDistance(Rect a, Rect b) {
    return (a.left - b.left).abs() +
        (a.top - b.top).abs() +
        (a.right - b.right).abs() +
        (a.bottom - b.bottom).abs();
  }

  String _statusFor(_DocumentQuality q, double stableProgress) {
    if (!q.documentFound) return 'Igazítsd a CMR-t a keretbe';
    if (!q.brightnessOk) return q.brightness < 45 ? 'Túl sötét • adj több fényt' : 'Túl világos • kerüld a becsillanást';
    if (!q.sharpEnough) return 'Fókuszálok… tartsd stabilan';
    if (stableProgress < .45) return 'Dokumentum megvan • tartsd mozdulatlanul';
    if (stableProgress < 1) return 'Jó kép • még egy pillanat…';
    return _autoCapture ? 'Éles és stabil • automatikus fotó' : 'Éles és stabil • fotózhatsz';
  }

  Future<void> _focusAt(TapDownDetails details, Size size) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || size.width <= 0 || size.height <= 0) return;
    final point = Offset(
      (details.localPosition.dx / size.width).clamp(0.0, 1.0),
      (details.localPosition.dy / size.height).clamp(0.0, 1.0),
    );
    setState(() => _focusPoint = details.localPosition);
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setFocusPoint(point);
      await c.setExposurePoint(point);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (mounted) setState(() => _focusPoint = null);
  }

  Future<void> _takePicture({bool auto = false}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    final qualityAtCapture = _quality;
    try {
      await _stopAnalysis();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!auto) {
        // Egy rövid időt adunk az autofókusznak a kézi exponálás előtt.
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      final file = await c.takePicture();
      if (mounted) {
        setState(() {
          _photoPath = file.path;
          _capturedQuality = qualityAtCapture;
          _stableFrames = 0;
        });
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.description ?? ''}');
      await _startAnalysis();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retake() async {
    setState(() {
      _photoPath = null;
      _capturedQuality = null;
      _stableFrames = 0;
      _lastDetectedRect = null;
      _quality = const _DocumentQuality.empty();
    });
    final c = _controller;
    if (c != null) {
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
    }
    await _startAnalysis();
  }

  Future<void> _disposeCamera({bool invalidateGeneration = true}) async {
    if (invalidateGeneration) _cameraGeneration++;
    final c = _controller;
    _controller = null;
    _streaming = false;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_controller == null) unawaited(_initCamera());
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_disposeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    final c = _controller;
    _controller = null;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CMR Scanner'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _autoCapture = !_autoCapture),
            icon: Icon(_autoCapture ? Icons.auto_awesome : Icons.touch_app, color: _autoCapture ? const Color(0xFFE6B85C) : Colors.white70),
            label: Text(_autoCapture ? 'AUTO' : 'KÉZI', style: TextStyle(color: _autoCapture ? const Color(0xFFE6B85C) : Colors.white70, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: _photoPath != null
          ? _ReviewView(path: _photoPath!, quality: _capturedQuality, onRetake: _retake)
          : _error != null && (c == null || !c.value.isInitialized)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('A kamera nem indult el.\n\n$_error', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _initCamera, child: const Text('Újrapróbálom')),
                    ]),
                  ),
                )
              : c == null || !c.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) => unawaited(_focusAt(d, size)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(child: CameraPreview(c)),
                              IgnorePointer(child: CustomPaint(painter: _FramePainter(_quality, _stableFrames / 7))),
                              if (_focusPoint != null)
                                Positioned(
                                  left: _focusPoint!.dx - 28,
                                  top: _focusPoint!.dy - 28,
                                  child: const _FocusReticle(),
                                ),
                              Positioned(
                                top: 18,
                                left: 16,
                                right: 16,
                                child: _QualityPanel(quality: _quality, stableProgress: (_stableFrames / 7).clamp(0.0, 1.0)),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 26,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Koppints a dokumentumra a fókuszhoz', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 10),
                                    Center(
                                      child: FloatingActionButton.large(
                                        onPressed: _busy ? null : () => _takePicture(),
                                        child: _busy ? const CircularProgressIndicator() : const Icon(Icons.camera_alt_rounded),
                                      ),
                                    ),
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
}

class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.quality, required this.stableProgress});
  final _DocumentQuality quality;
  final double stableProgress;

  @override
  Widget build(BuildContext context) {
    final good = quality.documentFound && quality.sharpEnough && quality.brightnessOk;
    final color = good ? const Color(0xFF48D597) : quality.documentFound ? const Color(0xFFFFC857) : Colors.white;
    final sharp = (quality.sharpness / 24 * 100).clamp(0, 100).round();
    final light = (quality.brightness / 180 * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .68), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .55))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(good ? Icons.check_circle : Icons.document_scanner_outlined, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(quality.status, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Élesség $sharp%', style: const TextStyle(color: Colors.white70, fontSize: 12))),
            Expanded(child: Text('Fény $light%', textAlign: TextAlign.end, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: good ? stableProgress : 0, minHeight: 4, backgroundColor: Colors.white12, color: const Color(0xFF48D597)),
          ),
        ],
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.path, required this.quality, required this.onRetake});
  final String path;
  final _DocumentQuality? quality;
  final Future<void> Function() onRetake;

  @override
  Widget build(BuildContext context) {
    final q = quality;
    final good = q != null && q.documentFound && q.sharpEnough && q.brightnessOk;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(path), fit: BoxFit.contain),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(good ? Icons.verified_rounded : Icons.info_outline, color: good ? const Color(0xFF48D597) : const Color(0xFFFFC857)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  good ? 'Minőség ellenőrizve • a kép éles és megfelelően megvilágított' : 'Nézd meg a dokumentum olvashatóságát',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 24,
          child: FilledButton.icon(onPressed: onRetake, icon: const Icon(Icons.refresh), label: const Text('Új fotó')),
        ),
      ],
    );
  }
}

class _FocusReticle extends StatelessWidget {
  const _FocusReticle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6B85C), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE6B85C), shape: BoxShape.circle)))),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.quality, this.stableProgress);
  final _DocumentQuality quality;
  final double stableProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Rect.fromLTWH(size.width * .07, size.height * .14, size.width * .86, size.height * .64);
    final good = quality.documentFound && quality.sharpEnough && quality.brightnessOk;
    final frameColor = good ? const Color(0xFF48D597) : quality.documentFound ? const Color(0xFFFFC857) : Colors.white;

    final shade = Paint()..color = Colors.black.withValues(alpha: .42);
    final p = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(guide, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(p, shade);

    final stroke = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = good ? 4 : 3;
    canvas.drawRRect(RRect.fromRectAndRadius(guide, const Radius.circular(18)), stroke);

    final corner = Paint()
      ..color = frameColor
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 34.0;
    canvas.drawLine(guide.topLeft, guide.topLeft + const Offset(len, 0), corner);
    canvas.drawLine(guide.topLeft, guide.topLeft + const Offset(0, len), corner);
    canvas.drawLine(guide.topRight, guide.topRight + const Offset(-len, 0), corner);
    canvas.drawLine(guide.topRight, guide.topRight + const Offset(0, len), corner);
    canvas.drawLine(guide.bottomLeft, guide.bottomLeft + const Offset(len, 0), corner);
    canvas.drawLine(guide.bottomLeft, guide.bottomLeft + const Offset(0, -len), corner);
    canvas.drawLine(guide.bottomRight, guide.bottomRight + const Offset(-len, 0), corner);
    canvas.drawLine(guide.bottomRight, guide.bottomRight + const Offset(0, -len), corner);

    if (good && stableProgress > 0) {
      final progressPaint = Paint()
        ..color = const Color(0xFF48D597)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: guide.center, radius: math.min(guide.width, guide.height) * .08), -math.pi / 2, math.pi * 2 * stableProgress.clamp(0.0, 1.0), false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) {
    return oldDelegate.quality != quality || oldDelegate.stableProgress != stableProgress;
  }
}

class _DocumentQuality {
  const _DocumentQuality({
    required this.documentFound,
    required this.sharpEnough,
    required this.brightnessOk,
    required this.confidence,
    required this.sharpness,
    required this.brightness,
    required this.detectedRect,
    required this.status,
  });

  const _DocumentQuality.empty()
      : documentFound = false,
        sharpEnough = false,
        brightnessOk = false,
        confidence = 0,
        sharpness = 0,
        brightness = 0,
        detectedRect = null,
        status = 'Keresem a dokumentumot…';

  final bool documentFound;
  final bool sharpEnough;
  final bool brightnessOk;
  final double confidence;
  final double sharpness;
  final double brightness;
  final Rect? detectedRect;
  final String status;

  _DocumentQuality withStatus(String value) => _DocumentQuality(
        documentFound: documentFound,
        sharpEnough: sharpEnough,
        brightnessOk: brightnessOk,
        confidence: confidence,
        sharpness: sharpness,
        brightness: brightness,
        detectedRect: detectedRect,
        status: value,
      );

  @override
  bool operator ==(Object other) {
    return other is _DocumentQuality &&
        other.documentFound == documentFound &&
        other.sharpEnough == sharpEnough &&
        other.brightnessOk == brightnessOk &&
        (other.confidence - confidence).abs() < .01 &&
        (other.sharpness - sharpness).abs() < .2 &&
        (other.brightness - brightness).abs() < .5 &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(documentFound, sharpEnough, brightnessOk, confidence.round(), sharpness.round(), brightness.round(), status);
}

class _LiveDocumentDetector {
  _DocumentQuality analyze(CameraImage image) {
    if (image.planes.isEmpty || image.width < 16 || image.height < 16) return const _DocumentQuality.empty();
    final plane = image.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final rowStride = plane.bytesPerRow;

    const cols = 64;
    const rows = 88;
    final grid = List<int>.filled(cols * rows, 0);
    double brightnessSum = 0;

    for (var gy = 0; gy < rows; gy++) {
      final sy = math.min(image.height - 1, (gy * image.height / rows).floor());
      for (var gx = 0; gx < cols; gx++) {
        final sx = math.min(image.width - 1, (gx * image.width / cols).floor());
        final index = sy * rowStride + sx * pixelStride;
        final y = index >= 0 && index < plane.bytes.length ? plane.bytes[index] : 0;
        grid[gy * cols + gx] = y;
        if (gx > cols * .15 && gx < cols * .85 && gy > rows * .15 && gy < rows * .85) brightnessSum += y;
      }
    }

    final innerCount = ((cols * .70) * (rows * .70)).round().clamp(1, cols * rows);
    final brightness = brightnessSum / innerCount;

    double laplacian = 0;
    var lapCount = 0;
    for (var y = 2; y < rows - 2; y += 2) {
      for (var x = 2; x < cols - 2; x += 2) {
        final center = grid[y * cols + x];
        final lap = (4 * center - grid[y * cols + x - 1] - grid[y * cols + x + 1] - grid[(y - 1) * cols + x] - grid[(y + 1) * cols + x]).abs();
        laplacian += lap;
        lapCount++;
      }
    }
    final sharpness = lapCount == 0 ? 0.0 : laplacian / lapCount;

    final vertical = List<double>.filled(cols - 1, 0);
    for (var x = 1; x < cols; x++) {
      double sum = 0;
      var count = 0;
      for (var y = (rows * .12).round(); y < (rows * .88).round(); y += 2) {
        sum += (grid[y * cols + x] - grid[y * cols + x - 1]).abs();
        count++;
      }
      vertical[x - 1] = count == 0 ? 0 : sum / count;
    }

    final horizontal = List<double>.filled(rows - 1, 0);
    for (var y = 1; y < rows; y++) {
      double sum = 0;
      var count = 0;
      for (var x = (cols * .12).round(); x < (cols * .88).round(); x += 2) {
        sum += (grid[y * cols + x] - grid[(y - 1) * cols + x]).abs();
        count++;
      }
      horizontal[y - 1] = count == 0 ? 0 : sum / count;
    }

    final left = _peak(vertical, 2, (vertical.length * .38).round());
    final right = _peak(vertical, (vertical.length * .62).round(), vertical.length - 2);
    final top = _peak(horizontal, 2, (horizontal.length * .38).round());
    final bottom = _peak(horizontal, (horizontal.length * .58).round(), horizontal.length - 2);

    final leftN = (left.index + 1) / cols;
    final rightN = (right.index + 1) / cols;
    final topN = (top.index + 1) / rows;
    final bottomN = (bottom.index + 1) / rows;
    final width = rightN - leftN;
    final height = bottomN - topN;
    final area = width * height;

    final edgeMean = (left.score + right.score + top.score + bottom.score) / 4;
    final weakestEdge = math.min(math.min(left.score, right.score), math.min(top.score, bottom.score));
    final edgeConfidence = (edgeMean / 20).clamp(0.0, 1.0);
    final coverageConfidence = ((area - .20) / .35).clamp(0.0, 1.0);
    final confidence = (.72 * edgeConfidence + .28 * coverageConfidence).clamp(0.0, 1.0);

    final brightnessOk = brightness >= 45 && brightness <= 218;
    final sharpEnough = sharpness >= 10.5;
    final documentFound = weakestEdge >= 6.0 && edgeMean >= 8.5 && area >= .25 && width >= .42 && height >= .42;
    final rect = documentFound ? Rect.fromLTRB(leftN, topN, rightN, bottomN) : null;

    return _DocumentQuality(
      documentFound: documentFound,
      sharpEnough: sharpEnough,
      brightnessOk: brightnessOk,
      confidence: confidence,
      sharpness: sharpness,
      brightness: brightness,
      detectedRect: rect,
      status: documentFound ? 'Dokumentum érzékelve' : 'Keresem a dokumentumot…',
    );
  }

  _Peak _peak(List<double> values, int start, int end) {
    final safeStart = start.clamp(0, values.length - 1);
    final safeEnd = end.clamp(safeStart, values.length - 1);
    var bestIndex = safeStart;
    var bestScore = values[safeStart];
    for (var i = safeStart + 1; i <= safeEnd; i++) {
      if (values[i] > bestScore) {
        bestScore = values[i];
        bestIndex = i;
      }
    }
    return _Peak(bestIndex, bestScore);
  }
}

class _Peak {
  const _Peak(this.index, this.score);
  final int index;
  final double score;
}
