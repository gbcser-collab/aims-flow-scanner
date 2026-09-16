import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_models.dart';
import '../services/scan_repository.dart';

class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.processedImagePath,
    required this.quality,
    required this.cmr,
    this.savedDocument,
    this.smartOcrSource,
    this.scanLocation,
  });

  final String processedImagePath;
  final ScanQuality quality;
  final CmrData cmr;
  final ScannedDocument? savedDocument;
  final String? smartOcrSource;
  final ScanLocation? scanLocation;

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
  bool _sharing = false;
  bool _autoSaveAttempted = false;

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

    if (_savedDocument == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSave());
    }
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
      plate: _clean(_plate)?.toUpperCase(),
      packageCount: packageText.isEmpty ? null : int.tryParse(packageText),
      grossWeightKg: weightText.isEmpty ? null : double.tryParse(weightText),
      goodsDescription: _clean(_goods),
      rawText: widget.cmr.rawText,
    );
  }

  int _filledFieldCount() => _currentCmr().filledFieldCount;

  Future<void> _copySummary() async {
    final text = _currentCmr().toPlainText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CMR összegzés a vágólapra másolva.')),
    );
  }

  Future<void> _autoSave() async {
    if (_autoSaveAttempted || _savedDocument != null) return;
    _autoSaveAttempted = true;
    await _save(silent: true);
  }

  Future<void> _save({bool silent = false}) async {
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
          location: widget.scanLocation,
        );
      } else {
        saved = ScannedDocument(
          id: _savedDocument!.id,
          createdAt: _savedDocument!.createdAt,
          imagePath: _savedDocument!.imagePath,
          cmr: cmr,
          quality: widget.quality,
          location: _savedDocument!.location ?? widget.scanLocation,
        );
        await _repository.update(saved);
      }
      if (!mounted) return;
      setState(() => _savedDocument = saved);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CMR mentve az AIMS Flow-ba.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A mentés nem sikerült: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _shareText(ScannedDocument document) {
    final location = document.location;
    final lines = <String>[
      'AIMS Flow • CMR scan',
      'Időpont: ${_formatTimestamp(document.createdAt)}',
      if (location != null) 'Hely: ${location.coordinates} (±${location.accuracyMeters.toStringAsFixed(0)} m)',
      '',
      document.cmr.toPlainText(),
      '',
      'Irodai címzett: office@logistic-aims.hu',
    ];
    return lines.join('\n');
  }

  Future<void> _share() async {
    if (_sharing) return;
    if (_savedDocument == null) {
      await _save(silent: true);
    } else {
      await _save(silent: true);
    }
    final document = _savedDocument;
    if (document == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Előbb el kell menteni a CMR-t.')),
        );
      }
      return;
    }

    setState(() => _sharing = true);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(document.imagePath)],
          text: _shareText(document),
          subject: 'CMR ${document.cmr.cmrNumber ?? ''} • Logistic-A.I.M.S.',
          title: 'Küldés e-mailben vagy Viberen',
        ),
      );
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ezen a készüléken nincs elérhető megosztási cél.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A küldés nem sikerült: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.cmr.rawText.trim().isNotEmpty;
    final filled = _filledFieldCount();
    final completion = filled / 10;
    final imagePath = _savedDocument?.imagePath ?? widget.processedImagePath;
    final missing = 10 - filled;
    final location = _savedDocument?.location ?? widget.scanLocation;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('CMR • Smart Scan PRO'),
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
                  child: Center(child: Text('Az előnézet nem tölthető be.', style: TextStyle(color: Colors.white70))),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hasText ? const Color(0xFF14231C) : const Color(0xFF2A2113),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: (hasText ? const Color(0xFF48D597) : Colors.orange).withValues(alpha: .35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(hasText ? Icons.auto_awesome_rounded : Icons.warning_amber_rounded, color: hasText ? const Color(0xFF48D597) : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasText
                          ? 'Smart OCR lefutott${widget.smartOcrSource == null ? '' : ' • forrás: ${widget.smartOcrSource}'}. A scan automatikusan az AIMS Flow-ban marad.'
                          : 'A feldolgozás lefutott, de az OCR nem talált biztos szöveget. A scan ettől még automatikusan mentésre kerül.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _metricCard('Adatkitöltés', '$filled / 10', completion, const Color(0xFFE6B85C))),
                const SizedBox(width: 10),
                Expanded(child: _metricCard('Képminőség', '${widget.quality.score} / 100', widget.quality.score / 100, const Color(0xFF48D597))),
              ],
            ),
            if (location != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111D28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: .22)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Colors.lightBlueAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scan helye: ${location.coordinates}\nPontosság: ±${location.accuracyMeters.toStringAsFixed(0)} m',
                        style: const TextStyle(color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (missing > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withValues(alpha: .25)),
                ),
                child: Text(
                  '$missing mező még hiányzik vagy ellenőrzést igényel.',
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700, height: 1.3),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Felismert CMR adatok',
              key: ValueKey('cmr-results-title'),
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text('Ellenőrizd és javítsd a szükséges mezőket.', style: TextStyle(color: Colors.white54)),
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
              key: const ValueKey('share-mail-viber'),
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(_sharing ? 'Küldés…' : 'Küldés • Mail / Viber'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFF48D597),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('copy-summary'),
              onPressed: _copySummary,
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('CMR összegzés másolása'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('save-offline'),
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_saving ? 'Mentés…' : (_savedDocument == null ? 'Mentés az AIMS Flow-ba' : 'Módosítások mentése')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
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

  Widget _metricCard(String label, String value, double progress, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            color: color,
            backgroundColor: Colors.white12,
          ),
        ],
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
          const Text('Képminőség-ellenőrzés', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(
            warnings.isEmpty ? 'A képminőség rendben.' : warnings.join('\n'),
            style: TextStyle(color: warnings.isEmpty ? const Color(0xFF48D597) : Colors.orangeAccent, height: 1.35),
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
    final empty = controller.text.trim().isEmpty;
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
          labelText: empty ? '$label • ellenőrizd' : label,
          labelStyle: TextStyle(color: empty ? Colors.orangeAccent : Colors.white54),
          filled: true,
          fillColor: empty ? const Color(0xFF201A13) : const Color(0xFF14181D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6B85C)),
          ),
        ),
      ),
    );
  }
}
