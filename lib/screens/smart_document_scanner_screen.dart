import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/aims_locale.dart';
import '../services/aims_scan_engine.dart';
import '../services/cmr_parser.dart';
import '../services/invoice_parser.dart';
import '../services/ocr_service.dart';
import '../services/smart_document_classifier.dart';
import '../widgets/scanner_overlay.dart';
import 'invoice_scanner_screen.dart';
import 'scan_review_screen.dart';
import 'smart_document_review_screen.dart';

class SmartDocumentScannerScreen extends StatefulWidget {
  const SmartDocumentScannerScreen({
    super.key,
    required this.camera,
    required this.plate,
    this.contextHint = '',
    this.returnCmrDocumentIdOnSave = false,
  });

  final CameraDescription camera;
  final String plate;
  final String contextHint;
  final bool returnCmrDocumentIdOnSave;

  @override
  State<SmartDocumentScannerScreen> createState() =>
      _SmartDocumentScannerScreenState();
}

class _SmartDocumentScannerScreenState
    extends State<SmartDocumentScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _busy = false;
  bool _initializing = false;
  String _phase = '';
  String? _error;
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
    _initCamera();
  }

  Future<void> _disposeCamera() async {
    final old = _camera;
    _camera = null;
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
          return _l(
            'A kameraengedély nincs megadva. Engedélyezd a Beállításokban, majd próbáld újra.',
            'Camera permission is missing. Enable it in Settings and try again.',
            'Die Kameraberechtigung fehlt. In den Einstellungen aktivieren und erneut versuchen.',
          );
        case 'CameraAccessRestricted':
          return _l(
            'A kamera használata ezen a készüléken korlátozva van.',
            'Camera use is restricted on this device.',
            'Die Kameranutzung ist auf diesem Gerät eingeschränkt.',
          );
        default:
          return _l(
            'A kamera nem indult el (${error.code}).',
            'The camera could not start (${error.code}).',
            'Die Kamera konnte nicht gestartet werden (${error.code}).',
          );
      }
    }
    return _l(
      'A kamera nem indult el. Próbáld újra.',
      'The camera could not start. Try again.',
      'Die Kamera konnte nicht gestartet werden. Erneut versuchen.',
    );
  }

  Future<void> _initCamera() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    final generation = ++_cameraGeneration;
    if (mounted) setState(() => _error = null);
    await _disposeCamera();

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
        try {
          await candidate.setFocusMode(FocusMode.auto);
        } catch (_) {}
        try {
          await candidate.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        try {
          await candidate.setFlashMode(FlashMode.auto);
        } catch (_) {
          try {
            await candidate.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
        if (!mounted || generation != _cameraGeneration) {
          await candidate.dispose();
          break;
        }
        setState(() {
          _camera = candidate;
          _error = null;
        });
        _initializing = false;
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
    setState(() => _error = _friendlyCameraError(lastError));
  }

  Future<void> _prepareCapture(CameraController camera) async {
    try {
      await camera.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await camera.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await camera.setFocusPoint(const Offset(.5, .5));
    } catch (_) {}
    try {
      await camera.setExposurePoint(const Offset(.5, .5));
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
            backgroundColor: const Color(0xFF071725),
            title: Text(
              _l(
                'Érdemes újrafotózni',
                'Retake recommended',
                'Neues Foto empfohlen',
              ),
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

  Future<bool> _confirmWeakOcr(String text) async {
    if (text.trim().replaceAll(RegExp(r'\s+'), '').length >= 12) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF071725),
            title: Text(_l('Kevés olvasható szöveg', 'Little readable text', 'Wenig lesbarer Text')),
            content: Text(
              _l(
                'A Flow alig tudott szöveget kiolvasni. Újrafotózás jobb eredményt adhat.',
                'Flow could read very little text. A retake may give a better result.',
                'Flow konnte nur wenig Text lesen. Ein neues Foto kann ein besseres Ergebnis liefern.',
              ),
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

  Widget _cameraPreview(CameraController camera) {
    final previewSize = camera.value.previewSize;
    if (previewSize == null) return CameraPreview(camera);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(camera),
          ),
        ),
      ),
    );
  }

  Future<SmartDocumentType?> _confirmType(
    SmartDocumentClassification classification,
  ) async {
    var selected = classification.type;
    return showModalBottomSheet<SmartDocumentType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF06131F),
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final confidence =
              (classification.confidence * 100).clamp(0, 100).round();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _l(
                      'Mit fotóztál?',
                      'What did you scan?',
                      'Was wurde gescannt?',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _l(
                      'A Flow szerint: ${classification.type.hu} · $confidence%',
                      'Flow recognized: ${classification.type.hu} · $confidence%',
                      'Flow erkannt: ${classification.type.hu} · $confidence%',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SmartDocumentType>(
                    initialValue: selected,
                    dropdownColor: const Color(0xFF0D2131),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF071725),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: SmartDocumentType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.hu),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => selected = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: Text(
                      _l('FOLYTATÁS', 'CONTINUE', 'WEITER'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InvoiceCategory _invoiceCategoryFor(
    SmartDocumentType type,
    InvoiceCategory parsed,
  ) =>
      switch (type) {
        SmartDocumentType.fuelReceipt => InvoiceCategory.fuel,
        SmartDocumentType.tollReceipt => InvoiceCategory.tollVignette,
        SmartDocumentType.parkingReceipt => InvoiceCategory.parking,
        SmartDocumentType.invoice => parsed,
        _ => InvoiceCategory.other,
      };

  InvoiceData _withCategory(InvoiceData d, InvoiceCategory category) =>
      InvoiceData(
        category: category,
        vendor: d.vendor,
        date: d.date,
        totalAmount: d.totalAmount,
        currency: d.currency,
        documentNumber: d.documentNumber,
        countryCode: d.countryCode,
        liters: d.liters,
        pricePerLiter: d.pricePerLiter,
        rawText: d.rawText,
        confidence: d.confidence,
      );

  Future<void> _routeResult({
    required String imagePath,
    required String signaturePath,
    required String rawText,
    required SmartDocumentClassification classification,
    required SmartDocumentType type,
    required dynamic scanResult,
  }) async {
    if (!mounted) return;

    if (type == SmartDocumentType.cmr) {
      final cmr = const CmrParser().parse(rawText);
      if (widget.returnCmrDocumentIdOnSave) {
        final documentId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(
              processedImagePath: imagePath,
              signatureImagePath: scanResult.signatureImagePath,
              signatureConfidence: scanResult.signatureConfidence,
              quality: scanResult.quality,
              cmr: cmr,
              closeOnSave: true,
            ),
          ),
        );
        if (mounted && documentId != null && documentId.isNotEmpty) {
          Navigator.of(context).pop(documentId);
        }
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(
              processedImagePath: imagePath,
              signatureImagePath: scanResult.signatureImagePath,
              signatureConfidence: scanResult.signatureConfidence,
              quality: scanResult.quality,
              cmr: cmr,
            ),
          ),
        );
      }
      return;
    }

    if (const {
      SmartDocumentType.invoice,
      SmartDocumentType.fuelReceipt,
      SmartDocumentType.tollReceipt,
      SmartDocumentType.parkingReceipt,
    }.contains(type)) {
      final parsed = const InvoiceParser().parse(rawText);
      final data = _withCategory(
        parsed,
        _invoiceCategoryFor(type, parsed.category),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InvoiceScannerScreen(
            camera: widget.camera,
            initialImagePath: imagePath,
            initialOcr: rawText,
            initialData: data,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SmartDocumentReviewScreen(
          imagePath: imagePath,
          rawText: rawText,
          initialType: type,
          confidence: classification.confidence,
          plate: widget.plate,
        ),
      ),
    );
  }

  Future<void> _captureAndRoute() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) return;

    setState(() {
      _busy = true;
      _phase = _l(
        'Kamera stabilizálása…',
        'Stabilizing camera…',
        'Kamera wird stabilisiert…',
      );
      _error = null;
    });

    final ocr = OcrService();
    XFile? shot;
    String? output;
    String? signature;
    var keepArtifacts = false;
    try {
      await _prepareCapture(camera);
      if (!mounted) return;
      setState(() => _phase = _l(
            'Dokumentum fotózása…',
            'Taking document photo…',
            'Dokument wird fotografiert…',
          ));

      shot = await camera.takePicture();
      final shotFile = File(shot.path);
      if (!await shotFile.exists() || await shotFile.length() < 4096) {
        throw const FormatException('capture_file_invalid');
      }

      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      output = '${temp.path}/aims_smart_document_$stamp.jpg';
      signature = '${temp.path}/aims_smart_signature_$stamp.jpg';

      if (mounted) {
        setState(() => _phase = _l(
              'Keret, perspektíva és képjavítás…',
              'Frame, perspective and image cleanup…',
              'Rahmen, Perspektive und Bildoptimierung…',
            ));
      }

      final result = await const AimsScanEngine().process(
        inputPath: shot.path,
        outputPath: output,
        signatureOutputPath: signature,
        frameCrop: FrameCropSpec(viewportAspect: _viewportAspect),
      );

      if (!await _confirmScanQuality(result)) {
        return;
      }

      if (mounted) {
        setState(() => _phase = _l(
              'Több-passzos OCR és dokumentumtípus felismerése…',
              'Multi-pass OCR and document type recognition…',
              'Mehrfach-OCR und Dokumenttyperkennung…',
            ));
      }
      final text = await ocr.recognizeBest(
        processedImagePath: result.outputPath,
        originalImagePath: shot.path,
      );
      if (!await _confirmWeakOcr(text)) {
        return;
      }

      final classification = const SmartDocumentClassifier().classify(
        text,
        context: widget.contextHint,
      );

      SmartDocumentType? selected = classification.type;
      if (classification.needsConfirmation) {
        if (!mounted) return;
        selected = await _confirmType(classification);
      }
      if (selected == null || !mounted) return;

      await _disposeCamera();
      keepArtifacts = true;

      await _routeResult(
        imagePath: result.outputPath,
        signaturePath: signature,
        rawText: text,
        classification: classification,
        type: selected,
        scanResult: result,
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = _l(
            'Kamerahiba (${e.code}): ${e.description ?? 'a kép nem készült el'}',
            'Camera error (${e.code}): ${e.description ?? 'the image was not captured'}',
            'Kamerafehler (${e.code}): ${e.description ?? 'das Bild wurde nicht aufgenommen'}',
          ));
      _cameraGeneration++;
      await _disposeCamera();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _l(
              'A Smart Scanner nem tudta feldolgozni a dokumentumot: $e',
              'Smart Scanner could not process the document: $e',
              'Smart Scanner konnte das Dokument nicht verarbeiten: $e',
            ));
      }
    } finally {
      await ocr.dispose();
      if (shot != null) {
        await _deleteArtifact(shot.path);
      }
      if (!keepArtifacts) {
        await _deleteArtifact(output);
        await _deleteArtifact(signature);
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _phase = '';
        });
        if (_camera == null && (ModalRoute.of(context)?.isCurrent ?? false)) {
          unawaited(_initCamera());
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _camera == null && !_busy) {
      unawaited(_initCamera());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cameraGeneration++;
      unawaited(_disposeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    final camera = _camera;
    _camera = null;
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight > 0) {
              _viewportAspect =
                  constraints.maxWidth / constraints.maxHeight;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                if (_error != null && camera == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.orangeAccent,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.orangeAccent),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _initializing ? null : _initCamera,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(_l('ÚJRAPRÓBÁLÁS', 'RETRY', 'ERNEUT VERSUCHEN')),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (camera == null || !camera.value.isInitialized)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF1CB8FF),
                    ),
                  )
                else
                  _cameraPreview(camera),
                if (camera != null && camera.value.isInitialized)
                  const ScannerOverlay(),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton.filledTonal(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 58,
                  right: 58,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .68),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _l(
                        'SMART SCANNER · egy fotó, automatikus felismerés',
                        'SMART SCANNER · one photo, automatic recognition',
                        'SMART SCANNER · ein Foto, automatische Erkennung',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (camera != null && camera.value.isInitialized)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: Center(
                      child: GestureDetector(
                        key: const Key('smart-document-capture'),
                        onTap: _busy ? null : _captureAndRoute,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 5,
                            ),
                            color: Colors.white24,
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_busy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Color(0xFF1CB8FF),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _phase,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
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
