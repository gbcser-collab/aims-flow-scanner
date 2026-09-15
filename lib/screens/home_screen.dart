import 'dart:io';

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
                Text('Samsung kompatibilitási tesztbuild', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _openScanner, icon: const Icon(Icons.document_scanner_rounded), label: const Text('Scanner megnyitása')),
            const SizedBox(height: 12),
            const Text('Ez a build először a telepítést, indítást és Samsung kameraútvonalat ellenőrzi. A CMR/OCR réteg a stabil kameraalap után kerül vissza.', textAlign: TextAlign.center),
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
  bool _busy = false;
  String? _error;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _disposeCamera();
    for (final preset in const [ResolutionPreset.veryHigh, ResolutionPreset.high, ResolutionPreset.medium]) {
      final candidate = CameraController(widget.camera, preset, enableAudio: false);
      try {
        await candidate.initialize();
        try { await candidate.setFlashMode(FlashMode.off); } catch (_) {}
        if (!mounted) { await candidate.dispose(); return; }
        _controller = candidate;
        setState(() => _error = null);
        return;
      } on CameraException catch (e) {
        await candidate.dispose();
        _error = '${e.code}: ${e.description ?? ''}';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      try { await c.dispose(); } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_controller == null) _initCamera();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _disposeCamera();
    }
  }

  Future<void> _takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (mounted) setState(() => _photoPath = file.path);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.description ?? ''}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('CMR Scanner')),
      body: _photoPath != null
          ? Stack(fit: StackFit.expand, children: [
              Image.file(File(_photoPath!), fit: BoxFit.contain),
              Positioned(left: 20, right: 20, bottom: 24, child: FilledButton(onPressed: () => setState(() => _photoPath = null), child: const Text('Új fotó'))),
            ])
          : _error != null && (c == null || !c.value.isInitialized)
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('A kamera nem indult el.\n\n$_error', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
              : c == null || !c.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(fit: StackFit.expand, children: [
                      Center(child: CameraPreview(c)),
                      IgnorePointer(child: CustomPaint(painter: _FramePainter())),
                      Positioned(left: 0, right: 0, bottom: 28, child: Center(child: FloatingActionButton.large(onPressed: _busy ? null : _takePicture, child: _busy ? const CircularProgressIndicator() : const Icon(Icons.camera_alt_rounded)))),
                    ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(size.width * .07, size.height * .1, size.width * .86, size.height * .7);
    final shade = Paint()..color = Colors.black45;
    final p = Path()..addRect(Offset.zero & size)..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)))..fillType = PathFillType.evenOdd;
    canvas.drawPath(p, shade);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
