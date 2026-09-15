import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/scan_repository.dart';

class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.processedImagePath,
    required this.quality,
    required this.cmr,
    this.savedDocument,
  });

  final String processedImagePath;
  final ScanQuality quality;
  final CmrData cmr;
  final ScannedDocument? savedDocument;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  static const _repository = ScanRepository();

  late final TextEditingController _cmrNumber;
  late final TextEditingController _shipper;
  late final TextEditingController _consignee;
  late final TextEditingController _loadingPlace;
  late final TextEditingController _deliveryPlace;
  late final TextEditingController _date;
  late final TextEditingController _plate;
  late final TextEditingController _packageCount;
  late final TextEditingController _grossWeight;
  late final TextEditingController _goods;

  ScannedDocument? _savedDocument;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _savedDocument = widget.savedDocument;
    final cmr = widget.cmr;
    _cmrNumber = _controller(cmr.cmrNumber);
    _shipper = _controller(cmr.shipper);
    _consignee = _controller(cmr.consignee);
    _loadingPlace = _controller(cmr.loadingPlace);
    _deliveryPlace = _controller(cmr.deliveryPlace);
    _date = _controller(cmr.date);
    _plate = _controller(cmr.plate);
    _packageCount = _controller(cmr.packageCount?.toString());
    _grossWeight = _controller(cmr.grossWeightKg?.toString());
    _goods = _controller(cmr.goodsDescription);
  }

  TextEditingController _controller(String? value) => TextEditingController(text: value ?? '');

  @override
  void dispose() {
    _cmrNumber.dispose();
    _shipper.dispose();
    _consignee.dispose();
    _loadingPlace.dispose();
    _deliveryPlace.dispose();
    _date.dispose();
    _plate.dispose();
    _packageCount.dispose();
    _grossWeight.dispose();
    _goods.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  CmrData _currentCmr() {
    final packageText = _packageCount.text.trim();
    final weightText = _grossWeight.text.trim().replaceAll(',', '.');
    return CmrData(
      cmrNumber: _clean(_cmrNumber),
      shipper: _clean(_shipper),
      consignee: _clean(_consignee),
      loadingPlace: _clean(_loadingPlace),
      deliveryPlace: _clean(_deliveryPlace),
      date: _clean(_date),
      plate: _clean(_plate),
      packageCount: packageText.isEmpty ? null : int.tryParse(packageText),
      grossWeightKg: weightText.isEmpty ? null : double.tryParse(weightText),
      goodsDescription: _clean(_goods),
      rawText: widget.cmr.rawText,
    );
  }

  int _filledFieldCount() {
    final values = <String?>[
      _clean(_cmrNumber),
      _clean(_shipper),
      _clean(_consignee),
      _clean(_loadingPlace),
      _clean(_deliveryPlace),
      _clean(_date),
      _clean(_plate),
      _clean(_packageCount),
      _clean(_grossWeight),
      _clean(_goods),
    ];
    return values.where((value) => value != null).length;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final cmr = _currentCmr();
      ScannedDocument saved;
      if (_savedDocument == null) {
        saved = await _repository.saveNew(
          sourceImagePath: widget.processedImagePath,
          cmr: cmr,
          quality: widget.quality,
        );
      } else {
        saved = ScannedDocument(
          id: _savedDocument!.id,
          createdAt: _savedDocument!.createdAt,
          imagePath: _savedDocument!.imagePath,
          cmr: cmr,
          quality: widget.quality,
        );
        await _repository.update(saved);
      }
      if (!mounted) return;
      setState(() => _savedDocument = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CMR mentve offline.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A mentés nem sikerült: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.cmr.rawText.trim().isNotEmpty;
    final filled = _filledFieldCount();
    final completion = filled / 10;
    final imagePath = _savedDocument?.imagePath ?? widget.processedImagePath;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('CMR • Smart Scan eredmény'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 390),
              decoration: BoxDecoration(
                color: const Color(0xFF101216),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 220,
                  child: Center(
                    child: Text('Az előnézet nem tölthető be.', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hasText ? const Color(0xFF14231C) : const Color(0xFF2A2113),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (hasText ? const Color(0xFF48D597) : Colors.orange).withValues(alpha: .35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    hasText ? Icons.verified_rounded : Icons.warning_amber_rounded,
                    color: hasText ? const Color(0xFF48D597) : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasText
                          ? 'A kép feldolgozása és az OCR lefutott. A mezők most már javíthatók és offline elmenthetők.'
                          : 'A kép feldolgozása lefutott, de az OCR nem talált biztos szöveget. A mezőket kézzel is kitöltheted.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Adatkitöltés', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                      Text('$filled / 10', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(
                    value: completion,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFE6B85C),
                    backgroundColor: Colors.white12,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Felismert CMR adatok',
              key: ValueKey('cmr-results-title'),
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Ellenőrizd, javítsd, majd mentsd el. Az automatikus felismerést mindig vesd össze az eredeti dokumentummal.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            _field('CMR szám', _cmrNumber),
            _field('Feladó', _shipper, maxLines: 2),
            _field('Címzett', _consignee, maxLines: 2),
            _field('Felrakóhely', _loadingPlace, maxLines: 2),
            _field('Lerakóhely', _deliveryPlace, maxLines: 2),
            _field('Dátum', _date),
            _field('Rendszám', _plate, textCapitalization: TextCapitalization.characters),
            _field('Darabszám', _packageCount, keyboardType: TextInputType.number),
            _field('Bruttó tömeg (kg)', _grossWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _field('Áru', _goods, maxLines: 3),
            const SizedBox(height: 8),
            ExpansionTile(
              collapsedIconColor: Colors.white60,
              iconColor: const Color(0xFFE6B85C),
              title: const Text('OCR nyers szöveg', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: SelectableText(
                    widget.cmr.rawText.trim().isEmpty ? 'Nem sikerült szöveget felismerni.' : widget.cmr.rawText,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _qualityCard(),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('save-offline'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_savedDocument == null ? Icons.save_rounded : Icons.check_circle_rounded),
              label: Text(_saving ? 'Mentés…' : (_savedDocument == null ? 'Mentés offline' : 'Módosítások mentése')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Új CMR fotózása'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityCard() {
    final warnings = widget.quality.warnings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Képminőség', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(
            warnings.isEmpty ? 'A képminőség rendben.' : warnings.join('\n'),
            style: TextStyle(
              color: warnings.isEmpty ? const Color(0xFF48D597) : Colors.orangeAccent,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF14181D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6B85C)),
          ),
        ),
      ),
    );
  }
}
