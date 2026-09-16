import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/aims_scan_engine.dart';
import '../services/cmr_parser.dart';
import '../services/frame_crop_service.dart';
import '../services/ocr_service.dart';
import '../widgets/scanner_overlay.dart';
import 'scan_review_screen.dart';

enum _ScannerFlashMode { off, auto, on }

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.camera});
  final CameraDescription camera;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _processing = false;
  bool _initializing = false;
  bool _flashChanging = false;
  _ScannerFlashMode _flashMode = _ScannerFlashMode.auto;
  String? _cameraError;
  String _phase = '';
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    _cameraError = null;
    final generation = ++_cameraGeneration;
    await _disposeCamera();

    const presets = <ResolutionPreset>[
      ResolutionPreset.high,
      ResolutionPreset.veryHigh,
      ResolutionPreset.medium,
    ];

    Object? lastError;
    for (final preset in presets) {
      if (!mounted || generation != _cameraGeneration) break;
      final candidate = CameraController(
        widget.camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await candidate.initialize();
        if (!mounted || generation != _cameraGeneration) {
          await candidate.dispose();
          break;
        }
        _controller = candidate;
        try {
          await candidate.setFocusMode(FocusMode.auto);
        } catch (_) {}
        try {
          await candidate.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        try {
          await candidate.setFlashMode(_cameraFlashMode(_flashMode));
        } catch (_) {
          _flashMode = _ScannerFlashMode.off;
          try {
            await candidate.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
        _initializing = false;
        if (mounted) setState(() {});
        return;
      } catch (e) {
        lastError = e;
        try {
          await candidate.dispose();
        } catch (_) {}
      }
    }

    _initializing = false;
    if (!mounted || generation != _cameraGeneration) return;
    setState(() => _cameraError = _friendlyCameraError(lastError));
  }

  Future<void> _disposeCamera() async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  String _friendlyCameraError(Object? error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
          return 'A kameraengedély nincs megadva. Engedélyezd a Beállításokban, majd próbáld újra.';
        case 'CameraAccessRestricted':
          return 'A kamera használata ezen a készüléken korlátozva van.';
        default:
          return 'A kamera nem indult el (${error.code}).';
      }
    }
    return 'A kamera nem indult el. Próbáld újra.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_processing) _initialize();
      return;
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _cameraGeneration++;
      _disposeCamera();
    }
  }

  FlashMode _cameraFlashMode(_ScannerFlashMode mode) {
    switch (mode) {
      case _ScannerFlashMode.off:
        return FlashMode.off;
      case _ScannerFlashMode.auto:
        return FlashMode.auto;
      case _ScannerFlashMode.on:
        return FlashMode.always;
    }
  }

  String _flashLabel(_ScannerFlashMode mode) {
    switch (mode) {
      case _ScannerFlashMode.off:
        return 'KI';
      case _ScannerFlashMode.auto:
        return 'AUTO';
      case _ScannerFlashMode.on:
        return 'BE';
    }
  }

  IconData _flashIcon(_ScannerFlashMode mode) {
    switch (mode) {
      case _ScannerFlashMode.off:
        return Icons.flash_off_rounded;
      case _ScannerFlashMode.auto:
        return Icons.flash_auto_rounded;
      case _ScannerFlashMode.on:
        return Icons.flash_on_rounded;
    }
  }

  Future<void> _setFlashMode(_ScannerFlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processing || _flashChanging || mode == _flashMode) return;
    setState(() => _flashChanging = true);
    try {
      await controller.setFlashMode(_cameraFlashMode(mode));
      if (mounted) setState(() => _flashMode = mode);
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A vaku ezen a kamerán nem állítható (${e.code}).')));
    } finally {
      if (mounted) setState(() => _flashChanging = false);
    }
  }

  Future<void> _captureAndProcess() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processing) return;

    setState(() {
      _processing = true;
      _phase = 'Fotó készítése…';
    });

    final ocr = OcrService();
    XFile? shot;
    String? fullCopy;
    String? frameCopy;
    String? processedPath;
    try {
      shot = await controller.takePicture();
      if (!mounted) return;

      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      fullCopy = '${temp.path}/aims_full_$stamp.jpg';
      frameCopy = '${temp.path}/aims_frame_$stamp.jpg';
      processedPath = '${temp.path}/aims_smart_$stamp.jpg';
      await File(shot.path).copy(fullCopy);

      setState(() => _phase = 'A kereten belüli dokumentum kivágása…');
      await const FrameCropService().crop(inputPath: fullCopy, outputPath: frameCopy);

      setState(() => _phase = 'Dokumentum tisztítása…');
      final result = await const AimsScanEngine().process(inputPath: frameCopy, outputPath: processedPath);

      if (!mounted) return;
      setState(() => _phase = 'OCR és CMR-adatok feldolgozása…');
      final processedText = await ocr.recognize(result.outputPath);
      final cmr = const CmrParser().parse(processedText);

      for (final path in [fullCopy, frameCopy]) {
        try {
          if (path != null && await File(path).exists()) await File(path).delete();
        } catch (_) {}
      }
      fullCopy = null;
      frameCopy = null;

      await _disposeCamera();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(
            processedImagePath: result.outputPath,
            quality: result.quality,
            cmr: cmr,
            smartOcrSource: 'Scanner keret',
          ),
        ),
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _phase = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kamerahiba (${e.code}): ${e.description ?? 'a kép nem készült el'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _phase = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A Smart Scan nem sikerült: $e')));
    } finally {
      await ocr.dispose();
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraError != null)
              _CameraErrorView(message: _cameraError!, onRetry: _initialize)
            else if (controller == null || !controller.value.isInitialized)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else
              Center(child: CameraPreview(controller)),
            if (_cameraError == null) const ScannerOverlay(),
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Csak a kereten belüli rész kerül a scanbe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            Positioned(top: 8, left: 8, child: IconButton.filledTonal(onPressed: _processing ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))),
            if (controller != null && controller.value.isInitialized)
              Positioned(
                left: 0,
                right: 0,
                bottom: 120,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .68), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white24)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _ScannerFlashMode.values.map((mode) {
                        final selected = mode == _flashMode;
                        return Semantics(
                          button: true,
                          selected: selected,
                          label: 'Vaku ${_flashLabel(mode)}',
                          child: InkWell(
                            key: ValueKey('flash-${mode.name}'),
                            borderRadius: BorderRadius.circular(20),
                            onTap: (_processing || _flashChanging) ? null : () => _setFlashMode(mode),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(color: selected ? const Color(0xFFE6B85C) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_flashIcon(mode), size: 18, color: selected ? Colors.black : Colors.white),
                                  const SizedBox(width: 5),
                                  Text(_flashLabel(mode), style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            if (_cameraError == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 22,
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'CMR fényképezése és feldolgozása',
                    child: GestureDetector(
                      key: const ValueKey('capture-and-process'),
                      onTap: _processing ? null : _captureAndProcess,
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), color: Colors.white.withValues(alpha: .18)),
                        alignment: Alignment.center,
                        child: Container(width: 60, height: 60, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            if (_processing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFFE6B85C)),
                          const SizedBox(height: 18),
                          const Text('SMART SCAN', style: TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                          const SizedBox(height: 8),
                          Text(_phase, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded, color: Colors.white70, size: 52),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Újrapróbálás')),
          ],
        ),
      ),
    );
  }
}
