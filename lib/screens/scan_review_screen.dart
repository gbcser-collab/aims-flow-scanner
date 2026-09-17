import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scan_models.dart';
import '../services/cmr_sync_service.dart';
import '../services/scan_repository.dart';
import '../widgets/aims_skin.dart';

class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.processedImagePath,
    required this.quality,
    required this.cmr,
    this.savedDocument,
    this.smartOcrSource,
  });

  final String processedImagePath;
  final ScanQuality quality;
  final CmrData cmr;
  final ScannedDocument? savedDocument;
  final String? smartOcrSource;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  static const _repository = ScanRepository();
  static const _sync = CmrSyncService();

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
  bool _syncing = false;
  String? _autoSaveError;

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePrivateSaveAndSync());
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

  Future<void> _ensurePrivateSaveAndSync() async {
    if (_savedDocument == null) {
      if (mounted) setState(() => _saving = true);
      try {
        final saved = await _repository.saveNew(
          sourceImagePath: widget.processedImagePath,
          cmr: _currentCmr(),
          quality: widget.quality,
        );
        if (!mounted) return;
        setState(() {
          _savedDocument = saved;
          _autoSaveError = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _autoSaveError = error.toString());
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    await _syncNow(silent: true);
  }

  Future<void> _copySummary() async {
    final text = _currentCmr().toPlainText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CMR összegzés a vágólapra másolva.')),
    );
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
        saved = _savedDocument!.copyWith(cmr: cmr, quality: widget.quality);
        await _repository.update(saved);
      }
      if (!mounted) return;
      setState(() {
        _savedDocument = saved;
        _autoSaveError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CMR az alkalmazás privát tárhelyén mentve.')),
      );
      await _syncNow(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A mentés nem sikerült: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (_syncing || _savedDocument == null) return;
    setState(() => _syncing = true);
    try {
      final report = await _sync.syncPending();
      final refreshed = await _repository.findById(_savedDocument!.id);
      if (!mounted) return;
      if (refreshed != null) setState(() => _savedDocument = refreshed);
      if (!silent) {
        final text = report.notConfigured
            ? 'A céges szerver még nincs beállítva ebben a buildben.'
            : report.failed > 0
                ? 'Szinkron: ${report.succeeded} sikeres, ${report.failed} sikertelen.'
                : 'Céges szinkron rendben.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _statusTitle(ScannedDocument? document) {
    if (document == null) return 'Privát mentés folyamatban';
    switch (document.deliveryState) {
      case CmrDeliveryState.localOnly:
        return 'Az appban mentve';
      case CmrDeliveryState.queued:
        return 'Küldésre vár';
      case CmrDeliveryState.uploaded:
        return 'Szerverre feltöltve';
      case CmrDeliveryState.emailed:
        return 'Céges e-mail elküldve';
      case CmrDeliveryState.approved:
        return 'Admin jóváhagyta';
      case CmrDeliveryState.syncError:
        return 'Szinkronhiba – újrapróbáljuk';
    }
  }

  String _statusSubtitle(ScannedDocument? document) {
    if (_autoSaveError != null) return 'Mentési hiba: $_autoSaveError';
    if (document == null) return 'A CMR nem kerül a Galériába vagy a Letöltések közé.';
    if (document.approvedAt != null && document.deleteAfter != null) {
      return 'Jóváhagyva. Automatikus helyi törlés: ${_formatDate(document.deleteAfter!)} (15 nap).';
    }
    if (document.emailedAt != null) return 'Elküldve: ${_formatDate(document.emailedAt!)} • admin jóváhagyásra vár.';
    if (document.lastSyncError != null) return 'A dokumentum biztonságosan az appban marad és újra próbálkozik.';
    return 'Privát app-tárhely • automatikus céges szinkron, ha van internet.';
  }

  String _formatDate(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.cmr.rawText.trim().isNotEmpty;
    final filled = _filledFieldCount();
    final completion = filled / 10;
    final imagePath = _savedDocument?.imagePath ?? widget.processedImagePath;
    final missing = 10 - filled;
    final approved = _savedDocument?.isApproved == true;

    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('CMR • Smart Scan PRO'),
      ),
      body: AimsBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 390),
                decoration: BoxDecoration(
                  color: const Color(0xD9081B35),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: aimsCyan.withValues(alpha: .4)),
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
              const SizedBox(height: 12),
              _lifecycleCard(),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: hasText ? const Color(0xB5092D3C) : const Color(0xB52A2318),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (hasText ? aimsMint : Colors.orange).withValues(alpha: .45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(hasText ? Icons.auto_awesome_rounded : Icons.warning_amber_rounded, color: hasText ? aimsMint : Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasText
                            ? 'Smart OCR lefutott${widget.smartOcrSource == null ? '' : ' • forrás: ${widget.smartOcrSource}'}. A jobb OCR-eredményt használjuk.'
                            : 'A feldolgozás lefutott, de az OCR nem talált biztos szöveget. A mezők kézzel is kitölthetők.',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _metricCard('Adatkitöltés', '$filled / 10', completion, aimsCyan)),
                  const SizedBox(width: 10),
                  Expanded(child: _metricCard('Képminőség', '${widget.quality.score} / 100', widget.quality.score / 100, aimsMint)),
                ],
              ),
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
                    style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700),
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
              Text(
                approved
                    ? 'A dokumentumot az admin már jóváhagyta; az adatok csak megtekintésre szolgálnak.'
                    : 'Ellenőrizd és javítsd, ha szükséges. A kép automatikusan az app privát tárhelyére került.',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 12),
              AbsorbPointer(
                absorbing: approved,
                child: Opacity(
                  opacity: approved ? .72 : 1,
                  child: Column(
                    children: [
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                collapsedIconColor: Colors.white60,
                iconColor: aimsCyan,
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
              OutlinedButton.icon(
                key: const ValueKey('copy-summary'),
                onPressed: _copySummary,
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('CMR összegzés másolása'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: Colors.white, side: BorderSide(color: aimsCyan.withValues(alpha: .4))),
              ),
              const SizedBox(height: 10),
              if (!approved)
                AimsNeonButton(
                  label: _saving ? 'Mentés…' : 'Módosítások mentése az appba',
                  onPressed: _saving ? null : _save,
                  leading: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.shield_rounded, color: Colors.white),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _syncing ? null : () => _syncNow(),
                icon: _syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: aimsCyan))
                    : const Icon(Icons.cloud_sync_rounded),
                label: Text(_syncing ? 'Szinkron…' : 'Céges szinkron most'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Colors.white, side: BorderSide(color: aimsCyan.withValues(alpha: .4))),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                icon: const Icon(Icons.document_scanner_rounded),
                label: const Text('Új CMR fotózása'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Colors.white, side: BorderSide(color: aimsCyan.withValues(alpha: .4))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lifecycleCard() {
    final document = _savedDocument;
    final stateColor = document?.deliveryState == CmrDeliveryState.syncError
        ? Colors.orangeAccent
        : document?.isApproved == true
            ? aimsMint
            : aimsCyan;
    return AimsGlassCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(document?.isApproved == true ? Icons.verified_user_rounded : Icons.lock_rounded, color: stateColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusTitle(document), style: TextStyle(color: stateColor, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(_statusSubtitle(document), style: const TextStyle(color: Colors.white70, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, double progress, Color color) {
    return AimsGlassCard(
      padding: const EdgeInsets.all(13),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 6, borderRadius: BorderRadius.circular(8), color: color, backgroundColor: Colors.white12),
        ],
      ),
    );
  }

  Widget _qualityCard() {
    final warnings = widget.quality.warnings;
    return AimsGlassCard(
      padding: const EdgeInsets.all(14),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Képminőség-ellenőrzés', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(
            warnings.isEmpty ? 'A képminőség rendben.' : warnings.join('\n'),
            style: TextStyle(color: warnings.isEmpty ? aimsMint : Colors.orangeAccent, height: 1.35),
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
          labelStyle: TextStyle(color: empty ? Colors.orangeAccent : const Color(0xFFB7E6FF)),
          filled: true,
          fillColor: empty ? const Color(0xCC242016) : const Color(0xCC0A2447),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: aimsCyan.withValues(alpha: .32))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: aimsCyan, width: 1.5)),
        ),
      ),
    );
  }
}
