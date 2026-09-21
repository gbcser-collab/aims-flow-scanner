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
    this.contextHint = '',
  });

  final CameraDescription camera;
  final String contextHint;

  @override
  State<SmartDocumentScannerScreen> createState() =>
      _SmartDocumentScannerScreenState();
}

class _SmartDocumentScannerScreenState
    extends State<SmartDocumentScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _busy = false;
  String _phase = '';
  String? _error;
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

  Future<void> _initCamera() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _camera?.dispose();
    } catch (_) {}
    final camera = CameraController(
      widget.camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await camera.initialize();
      try {
        await camera.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await camera.setFlashMode(FlashMode.auto);
      } catch (_) {}
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
    } catch (e) {
      await camera.dispose();
      if (mounted) {
        setState(() => _error = _l(
              'A kamera nem indult el: $e',
              'Camera failed to start: $e',
              'Kamera konnte nicht gestartet werden: $e',
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        'Dokumentum fotózása…',
        'Taking document photo…',
        'Dokument wird fotografiert…',
      );
      _error = null;
    });

    final ocr = OcrService();
    XFile? shot;
    try {
      shot = await camera.takePicture();
      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final output = '${temp.path}/aims_smart_document_$stamp.jpg';
      final signature = '${temp.path}/aims_smart_signature_$stamp.jpg';

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

      if (mounted) {
        setState(() => _phase = _l(
              'OCR és dokumentumtípus felismerése…',
              'OCR and document type recognition…',
              'OCR und Dokumenttyperkennung…',
            ));
      }
      final text = await ocr.recognize(result.outputPath);
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

      try {
        await camera.dispose();
      } catch (_) {}
      _camera = null;

      await _routeResult(
        imagePath: result.outputPath,
        signaturePath: signature,
        rawText: text,
        classification: classification,
        type: selected,
        scanResult: result,
      );
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
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _phase = '';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _camera == null &&
        !_busy) {
      _initCamera();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
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
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent),
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
                  CameraPreview(camera),
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
