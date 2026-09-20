import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/aims_locale.dart';
import '../services/aims_scan_engine.dart';
import '../services/fuel_receipt_parser.dart';
import '../services/fuel_receipt_service.dart';
import '../services/ocr_service.dart';
import '../services/vehicle_tracking_service.dart';

class FuelReceiptScreen extends StatefulWidget {
  const FuelReceiptScreen({super.key, required this.camera});
  final CameraDescription camera;

  @override
  State<FuelReceiptScreen> createState() => _FuelReceiptScreenState();
}

class _FuelReceiptScreenState extends State<FuelReceiptScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _imagePath;
  String _rawText = '';
  String _phase = '';
  String? _error;
  bool _busy = false;
  bool _sending = false;

  final _plate = TextEditingController();
  final _station = TextEditingController();
  final _date = TextEditingController();
  final _total = TextEditingController();
  final _currency = TextEditingController();
  final _liters = TextEditingController();
  final _unitPrice = TextEditingController();
  final _receipt = TextEditingController();

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
    VehicleTrackingService.instance.currentStatus().then((status) {
      if (mounted) _plate.text = status.vehicleLabel;
    });
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_busy || _imagePath != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = _controller;
    _controller = null;
    try {
      await old?.dispose();
    } catch (_) {}

    final controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await controller.setFlashMode(FlashMode.auto);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = _l('A kamera nem indult el: $e', 'The camera could not start: $e', 'Die Kamera konnte nicht gestartet werden: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() {
      _busy = true;
      _phase = _l('Bizonylat fényképezése…', 'Taking receipt photo…', 'Beleg wird fotografiert…');
      _error = null;
    });

    final ocr = OcrService();
    XFile? shot;
    try {
      shot = await controller.takePicture();
      final temp = await getTemporaryDirectory();
      final output = '${temp.path}/aims_fuel_${DateTime.now().microsecondsSinceEpoch}.jpg';

      setState(() => _phase = _l('Bizonylat tisztítása…', 'Cleaning receipt image…', 'Belegbild wird bereinigt…'));
      String finalPath;
      try {
        final processed = await const AimsScanEngine().process(inputPath: shot.path, outputPath: output);
        finalPath = processed.outputPath;
      } catch (_) {
        await File(shot.path).copy(output);
        finalPath = output;
      }

      setState(() => _phase = _l('OCR és tankolási adatok felismerése…', 'Recognizing OCR and fuel data…', 'OCR- und Tankdaten werden erkannt…'));
      final text = await ocr.recognize(finalPath);
      final data = const FuelReceiptParser().parse(text);

      _rawText = text;
      _station.text = data.station ?? '';
      _date.text = data.date ?? '';
      _total.text = data.totalAmount?.toString() ?? '';
      _currency.text = data.currency ?? '';
      _liters.text = data.liters?.toString() ?? '';
      _unitPrice.text = data.pricePerLiter?.toString() ?? '';
      _receipt.text = data.receiptNumber ?? '';

      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _imagePath = finalPath;
        _phase = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _l('A tankolási bizonylat feldolgozása nem sikerült: $e', 'Fuel receipt processing failed: $e', 'Tankbeleg konnte nicht verarbeitet werden: $e'));
    } finally {
      await ocr.dispose();
      if (shot != null) {
        try {
          if (await File(shot.path).exists()) await File(shot.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  FuelReceiptData _currentData() {
    double? number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    String? value(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return FuelReceiptData(
      station: value(_station),
      date: value(_date),
      totalAmount: number(_total),
      currency: value(_currency)?.toUpperCase(),
      liters: number(_liters),
      pricePerLiter: number(_unitPrice),
      receiptNumber: value(_receipt),
      rawText: _rawText,
    );
  }

  Future<void> _send() async {
    final imagePath = _imagePath;
    if (imagePath == null || _sending) return;
    if (_plate.text.trim().length < 4) {
      setState(() => _error = _l('A küldéshez add meg a jármű rendszámát.', 'Enter the vehicle plate before sending.', 'Vor dem Senden das Fahrzeugkennzeichen eingeben.'));
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await VehicleTrackingService.instance.setVehicleLabel(_plate.text);
      final status = await VehicleTrackingService.instance.currentStatus();
      final id = await const FuelReceiptService().send(
        imagePath: imagePath,
        deviceId: status.deviceId,
        plate: _plate.text.trim().toUpperCase(),
        data: _currentData(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l('Tankolási bizonylat elküldve a főnökségnek. #$id', 'Fuel receipt sent to the office. #$id', 'Tankbeleg an die Disposition gesendet. #$id'))),
      );
      try {
        await File(imagePath).delete();
      } catch (_) {}
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retake() async {
    final path = _imagePath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    setState(() {
      _imagePath = null;
      _rawText = '';
      _error = null;
    });
    await _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _imagePath == null && _controller == null) {
      _initializeCamera();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      final controller = _controller;
      _controller = null;
      controller?.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    for (final c in [_plate, _station, _date, _total, _currency, _liters, _unitPrice, _receipt]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _imagePath;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: Text(_l('Tankolási bizonylat', 'Fuel receipt', 'Tankbeleg')),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AimsLanguageSelector(compact: true),
          ),
        ],
      ),
      body: SafeArea(
        child: imagePath == null ? _cameraView() : _reviewView(imagePath),
      ),
    );
  }

  Widget _cameraView() {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_error != null && controller == null)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))))
        else if (controller == null || !controller.value.isInitialized)
          const Center(child: CircularProgressIndicator(color: Color(0xFFE6B85C)))
        else
          CameraPreview(controller),
        Positioned(
          left: 20,
          right: 20,
          top: 20,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(16)),
            child: Text(
              _l('Töltsd ki a képet a teljes tankolási bizonylattal. Az OCR után ellenőrizheted az adatokat.', 'Fill the frame with the whole fuel receipt. You can review the data after OCR.', 'Fülle den Rahmen mit dem vollständigen Tankbeleg. Nach der OCR kannst du die Daten prüfen.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: Center(
            child: GestureDetector(
              onTap: _busy ? null : _capture,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), color: Colors.white24),
                alignment: Alignment.center,
                child: Container(width: 60, height: 60, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
              ),
            ),
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFE6B85C)),
                    const SizedBox(height: 16),
                    Text(_phase, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _reviewView(String imagePath) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(File(imagePath), height: 280, fit: BoxFit.contain),
        ),
        const SizedBox(height: 16),
        Text(_l('Ellenőrizd a felismert adatokat', 'Review recognized data', 'Erkannte Daten prüfen'), style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _field(_l('Rendszám', 'Plate', 'Kennzeichen'), _plate, caps: true),
        _field(_l('Töltőállomás', 'Fuel station', 'Tankstelle'), _station),
        _field(_l('Dátum', 'Date', 'Datum'), _date),
        Row(
          children: [
            Expanded(child: _field(_l('Összeg', 'Total', 'Betrag'), _total, number: true)),
            const SizedBox(width: 8),
            Expanded(child: _field(_l('Pénznem', 'Currency', 'Währung'), _currency, caps: true)),
          ],
        ),
        Row(
          children: [
            Expanded(child: _field(_l('Liter', 'Litres', 'Liter'), _liters, number: true)),
            const SizedBox(width: 8),
            Expanded(child: _field(_l('Egységár / liter', 'Unit price / litre', 'Preis / Liter'), _unitPrice, number: true)),
          ],
        ),
        _field(_l('Bizonylatszám', 'Receipt number', 'Belegnummer'), _receipt),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(_sending ? _l('Küldés…', 'Sending…', 'Senden…') : _l('Küldés a főnökségi appba', 'Send to office app', 'An Dispositions-App senden')),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: const Color(0xFFE6B85C),
            foregroundColor: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _sending ? null : _retake,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(_l('Újrafotózás', 'Retake photo', 'Neu fotografieren')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: Colors.white,
          ),
        ),
        ExpansionTile(
          collapsedIconColor: Colors.white54,
          iconColor: const Color(0xFFE6B85C),
          title: Text(_l('OCR nyers szöveg', 'Raw OCR text', 'OCR-Rohtext'), style: const TextStyle(color: Colors.white70)),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_rawText.isEmpty ? _l('Nem talált szöveget.', 'No text found.', 'Kein Text gefunden.') : _rawText, style: const TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, {bool number = false, bool caps = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.sentences,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF171A1F),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}