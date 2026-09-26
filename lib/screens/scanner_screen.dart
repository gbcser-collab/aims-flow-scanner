import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scan_models.dart';
import '../services/aims_locale.dart';
import '../services/aims_scan_engine.dart';
import '../services/cmr_parser.dart';
import '../services/ocr_service.dart';
import '../widgets/scanner_overlay.dart';
import 'scan_review_screen.dart';

enum _ScannerFlashMode { off, auto, on }

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.camera,
    this.returnDocumentIdOnSave = false,
  });

  final CameraDescription camera;
  final bool returnDocumentIdOnSave;

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
  double _viewportAspect = 9 / 16;

  String _l(String hu, String en, String de) => switch (
        AimsLocaleController.instance.languageCode
      ) {
        'en' => en,
        'de' => de,
        _ => hu,
      };

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

    // CMR Pro prioritizes document detail: signatures, stamps and small
    // reference numbers must survive perspective correction. Fall back only
    // when the device cannot initialize the higher capture preset reliably.
    const presets = <ResolutionPreset>[
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
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
          return _l('A kameraengedély nincs megadva. Engedélyezd a Beállításokban, majd próbáld újra.', 'Camera permission is missing. Enable it in Settings and try again.', 'Die Kameraberechtigung fehlt. In den Einstellungen aktivieren und erneut versuchen.');
        case 'CameraAccessRestricted':
          return _l('A kamera használata ezen a készüléken korlátozva van.', 'Camera use is restricted on this device.', 'Die Kameranutzung ist auf diesem Gerät eingeschränkt.');
        default:
          return _l('A kamera nem indult el (${error.code}).', 'The camera could not start (${error.code}).', 'Die Kamera konnte nicht gestartet werden (${error.code}).');
      }
    }
    return _l('A kamera nem indult el. Próbáld újra.', 'The camera could not start. Try again.', 'Die Kamera konnte nicht gestartet werden. Erneut versuchen.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_processing) _initialize();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
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
        // FlashMode.always fires for capture only. Do NOT use torch: the user
        // explicitly does not want the LED burning during OCR/processing.
        return FlashMode.always;
    }
  }

  String _flashLabel(_ScannerFlashMode mode) {
    switch (mode) {
      case _ScannerFlashMode.off:
        return _l('KI', 'OFF', 'AUS');
      case _ScannerFlashMode.auto:
        return 'AUTO';
      case _ScannerFlashMode.on:
        return _l('BE', 'ON', 'EIN');
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

  Future<void> _prepareCapture(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await controller.setFocusPoint(const Offset(.5, .5));
    } catch (_) {}
    try {
      await controller.setExposurePoint(const Offset(.5, .5));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
  }

  List<String> _qualityWarnings(ScanProcessingResult result) {
    final q = result.quality;
    return <String>[
      if (!result.autoCropReliable)
        _l(
          'A dokumentum széleit nem sikerült biztosan felismerni.',
          'Document edges could not be detected reliably.',
          'Die Dokumentränder konnten nicht zuverlässig erkannt werden.',
        ),
      if (q.isBlurry)
        _l('A kép életlennek tűnik.', 'The image looks blurry.', 'Das Bild wirkt unscharf.'),
      if (q.isTooDark)
        _l('A dokumentum túl sötét.', 'The document is too dark.', 'Das Dokument ist zu dunkel.'),
      if (q.isTooBright)
        _l('A dokumentum túl világos.', 'The document is too bright.', 'Das Dokument ist zu hell.'),
      if (q.hasTooMuchGlare)
        _l('Erős becsillanást érzékelek.', 'Strong glare detected.', 'Starke Spiegelung erkannt.'),
      if (q.documentTooSmall)
        _l('A dokumentum túl kicsi a képen.', 'The document is too small in the image.', 'Das Dokument ist im Bild zu klein.'),
    ];
  }

  Future<bool> _confirmScanQuality(ScanProcessingResult result) async {
    if (!result.shouldSuggestRetake) return true;
    if (!mounted) return false;
    final warnings = _qualityWarnings(result);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF101216),
            title: Text(
              _l('Érdemes újrafotózni', 'Retake recommended', 'Neues Foto empfohlen'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l(
                    'Minőség: ${result.quality.score}/100 · keret: ${(result.cornerConfidence * 100).round()}%',
                    'Quality: ${result.quality.score}/100 · frame: ${(result.cornerConfidence * 100).round()}%',
                    'Qualität: ${result.quality.score}/100 · Rahmen: ${(result.cornerConfidence * 100).round()}%',
                  ),
                ),
                const SizedBox(height: 10),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('• $warning'),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_l('HASZNÁLOM', 'USE ANYWAY', 'TROTZDEM VERWENDEN')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_l('ÚJRAFOTÓZOM', 'RETAKE', 'NEU AUFNEHMEN')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteArtifact(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l('A vaku ezen a kamerán nem állítható (${e.code}).', 'Flash cannot be changed on this camera (${e.code}).', 'Der Blitz kann bei dieser Kamera nicht geändert werden (${e.code}).'))));
    } finally {
      if (mounted) setState(() => _flashChanging = false);
    }
  }

  Future<void> _captureAndProcess() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processing) return;

    setState(() {
      _processing = true;
      _phase = _l('Fotó készítése…', 'Taking photo…', 'Foto wird aufgenommen…');
    });

    final ocr = OcrService();
    XFile? shot;
    String? processedPath;
    String? signaturePath;
    var keepArtifacts = false;
    try {
      await _prepareCapture(controller);
      if (!mounted) return;
      setState(() => _phase = _l('Fotó készítése…', 'Taking photo…', 'Foto wird aufgenommen…'));
      shot = await controller.takePicture();
      final shotFile = File(shot.path);
      if (!await shotFile.exists() || await shotFile.length() < 4096) {
        throw const FormatException('capture_file_invalid');
      }
      if (!mounted) return;
      setState(() => _phase = _l('Kereten kívüli rész levágása…', 'Cropping outside the frame…', 'Bereich außerhalb des Rahmens wird zugeschnitten…'));

      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      processedPath = '${temp.path}/aims_smart_$stamp.jpg';
      signaturePath = '${temp.path}/aims_signature_$stamp.jpg';
      final result = await const AimsScanEngine().process(
        inputPath: shot.path,
        outputPath: processedPath,
        signatureOutputPath: signaturePath,
        frameCrop: FrameCropSpec(viewportAspect: _viewportAspect),
      );

      if (!await _confirmScanQuality(result)) {
        return;
      }

      if (!mounted) return;
      setState(() => _phase = _l(
            'Szöveg felismerése több képből…',
            'Recognizing text from multiple image variants…',
            'Text wird aus mehreren Bildvarianten erkannt…',
          ));
      final text = await ocr.recognizeBest(
        processedImagePath: result.outputPath,
        originalImagePath: shot.path,
      );

      if (!mounted) return;
      setState(() => _phase = _l('CMR mezők kitöltése…', 'Filling CMR fields…', 'CMR-Felder werden ausgefüllt…'));
      final cmr = const CmrParser().parse(text);

      if (!mounted) return;
      await _disposeCamera();
      keepArtifacts = true;
      if (!mounted) return;
      if (widget.returnDocumentIdOnSave) {
        final documentId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(
              processedImagePath: result.outputPath,
              signatureImagePath: result.signatureImagePath,
              signatureConfidence: result.signatureConfidence,
              quality: result.quality,
              cmr: cmr,
              closeOnSave: true,
            ),
          ),
        );
        if (!mounted) return;
        if (documentId != null && documentId.isNotEmpty) {
          Navigator.of(context).pop(documentId);
          return;
        }
        if (mounted) {
          setState(() {
            _processing = false;
            _phase = '';
          });
        }
        await _initialize();
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(
              processedImagePath: result.outputPath,
              signatureImagePath: result.signatureImagePath,
              signatureConfidence: result.signatureConfidence,
              quality: result.quality,
              cmr: cmr,
            ),
          ),
        );
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _phase = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l('Kamerahiba (${e.code}): ${e.description ?? 'a kép nem készült el'}', 'Camera error (${e.code}): ${e.description ?? 'the image was not captured'}', 'Kamerafehler (${e.code}): ${e.description ?? 'das Bild wurde nicht aufgenommen'}'))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _phase = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l('A Smart Scan nem sikerült: $e', 'Smart Scan failed: $e', 'Smart Scan fehlgeschlagen: $e'))));
    } finally {
      await ocr.dispose();
      if (shot != null) {
        await _deleteArtifact(shot.path);
      }
      if (!keepArtifacts) {
        await _deleteArtifact(processedPath);
        await _deleteArtifact(signaturePath);
      }
      if (mounted && _processing && _controller != null) {
        setState(() {
          _processing = false;
          _phase = '';
        });
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

  Widget _cameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight > 0) _viewportAspect = constraints.maxWidth / constraints.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraError != null)
                  _CameraErrorView(message: _cameraError!, onRetry: _initialize)
                else if (controller == null || !controller.value.isInitialized)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else
                  _cameraPreview(controller),
                if (_cameraError == null) const ScannerOverlay(),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(18)),
                      child: Text(_l('Csak ami a keretben van, az kerül a scanbe', 'Only content inside the frame will be scanned', 'Nur der Inhalt im Rahmen wird gescannt'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton.filledTonal(onPressed: _processing ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ),
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
                              label: _l('Vaku ${_flashLabel(mode)}', 'Flash ${_flashLabel(mode)}', 'Blitz ${_flashLabel(mode)}'),
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
                    bottom: 14,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            button: true,
                            label: _l(
                              'CMR fényképezése és feldolgozása',
                              'Photograph and process CMR',
                              'CMR fotografieren und verarbeiten',
                            ),
                            child: GestureDetector(
                              key: const ValueKey('capture-and-process'),
                              onTap: _processing ? null : _captureAndProcess,
                              child: Container(
                                width: 86,
                                height: 86,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 5),
                                  color: Colors.white.withValues(alpha: .18),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 62,
                                  height: 62,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _l('FOTÓZÁS', 'TAKE PHOTO', 'FOTO'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
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
                              const SizedBox(height: 8),
                              Text(_l('A vaku feldolgozás közben nem világít.', 'Flash stays off during processing.', 'Der Blitz bleibt während der Verarbeitung aus.'), style: const TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
            FilledButton(onPressed: onRetry, child: Text(AimsLocaleController.instance.languageCode == 'en' ? 'Try again' : AimsLocaleController.instance.languageCode == 'de' ? 'Erneut versuchen' : 'Újrapróbálás')),
          ],
        ),
      ),
    );
  }
}