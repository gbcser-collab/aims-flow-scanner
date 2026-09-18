import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_models.dart';
import '../models/tracking_models.dart';
import '../services/aims_locale.dart';
import '../services/location_capture_service.dart';
import '../services/scan_repository.dart';
import '../services/sync_coordinator.dart';

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
  static const _location = LocationCaptureService();
  final _sync = SyncCoordinator.instance;

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
    _sync.addListener(_syncChanged);
  }

  void _syncChanged() {
    if (!mounted || _savedDocument == null) return;
    unawaited(_reloadSavedDocument());
  }

  Future<void> _reloadSavedDocument() async {
    final id = _savedDocument?.id;
    if (id == null) return;
    final all = await _repository.loadAll();
    final matches = all.where((item) => item.id == id).toList();
    if (matches.isNotEmpty && mounted) setState(() => _savedDocument = matches.first);
  }

  TextEditingController _controller(String? value) => TextEditingController(text: value ?? '');

  @override
  void dispose() {
    _sync.removeListener(_syncChanged);
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
        final stamp = await _location.capture();
        saved = await _repository.saveNew(
          sourceImagePath: widget.processedImagePath,
          cmr: cmr,
          quality: widget.quality,
          location: stamp,
        );
      } else {
        saved = _savedDocument!.copyWith(
          cmr: cmr,
          syncState: CmrSyncState.pending,
          clearLastSyncError: true,
        );
        await _repository.update(saved);
      }
      if (!mounted) return;
      setState(() => _savedDocument = saved);
      await _sync.refreshPendingCount();
      unawaited(_sync.syncNow());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved.location == null
              ? _l('CMR mentve offline. Helyadat nem állt rendelkezésre; a szinkron automatikusan indul.', 'CMR saved offline. No location was available; sync will start automatically.', 'CMR offline gespeichert. Keine Standortdaten verfügbar; die Synchronisierung startet automatisch.')
              : _l('CMR mentve GPS-bélyeggel. A szinkron automatikusan indul.', 'CMR saved with GPS stamp. Sync will start automatically.', 'CMR mit GPS-Stempel gespeichert. Die Synchronisierung startet automatisch.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l('A mentés nem sikerült: $e', 'Save failed: $e', 'Speichern fehlgeschlagen: $e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    if (_savedDocument == null) await _save();
    final document = _savedDocument;
    if (document == null) return;
    final image = File(document.imagePath);
    if (!await image.exists()) return;

    setState(() => _sharing = true);
    try {
      final loc = document.location;
      final text = StringBuffer()
        ..writeln('AIMS Flow Smart Scanner • CMR')
        ..writeln('CMR: ${document.cmr.cmrNumber ?? '—'}')
        ..writeln(_l('Rendszám: ${document.cmr.plate ?? '—'}', 'Plate: ${document.cmr.plate ?? '—'}', 'Kennzeichen: ${document.cmr.plate ?? '—'}'))
        ..writeln('Mentve: ${_formatDate(document.createdAt)}');
      if (loc != null) {
        text.writeln('GPS: ${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)} (±${loc.accuracy.toStringAsFixed(0)} m)');
      }
      await SharePlus.instance.share(
        ShareParams(
          subject: 'AIMS Flow CMR ${document.cmr.cmrNumber ?? document.id}',
          text: text.toString().trim(),
          files: [XFile(document.imagePath, mimeType: 'image/jpeg')],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _syncText(CmrSyncState state) => switch (state) {
        CmrSyncState.pending => _l('Szinkronra vár', 'Waiting for sync', 'Wartet auf Synchronisierung'),
        CmrSyncState.uploaded => _l('Feltöltve', 'Uploaded', 'Hochgeladen'),
        CmrSyncState.emailed => _l('E-mail elküldve', 'Email sent', 'E-Mail gesendet'),
        CmrSyncState.approved => _l('Admin jóváhagyta', 'Approved by admin', 'Vom Admin genehmigt'),
        CmrSyncState.failed => _l('Offline / újrapróbálásra vár', 'Offline / waiting to retry', 'Offline / wartet auf neuen Versuch'),
      };

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
        title: Text(_l('CMR • Smart Scan eredmény', 'CMR • Smart Scan result', 'CMR • Smart-Scan-Ergebnis')),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AimsLanguageSelector(compact: true),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 390),
              decoration: BoxDecoration(color: const Color(0xFF101216), borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => SizedBox(height: 220, child: Center(child: Text(_l('Az előnézet nem tölthető be.', 'Preview cannot be loaded.', 'Vorschau kann nicht geladen werden.'), style: const TextStyle(color: Colors.white70)))),
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
                  Icon(hasText ? Icons.verified_rounded : Icons.warning_amber_rounded, color: hasText ? const Color(0xFF48D597) : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasText
                          ? _l('A dokumentum feldolgozása és az OCR lefutott. Ellenőrizd a mezőket; mentéskor valós idő- és engedélyezett GPS-adat kerül hozzá.', 'Document processing and OCR completed. Review the fields; time and permitted GPS data are attached when saving.', 'Dokumentverarbeitung und OCR sind abgeschlossen. Prüfe die Felder; beim Speichern werden Zeit- und erlaubte GPS-Daten hinzugefügt.')
                          : _l('Az OCR nem talált biztos szöveget. A mezőket kézzel is kitöltheted; mentéskor idő- és GPS-bélyeg kérhető.', 'OCR did not find reliable text. You can fill the fields manually; time and GPS stamps can be added on save.', 'OCR hat keinen sicheren Text erkannt. Die Felder können manuell ausgefüllt werden; beim Speichern können Zeit- und GPS-Stempel hinzugefügt werden.'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (_savedDocument != null) ...[
              const SizedBox(height: 12),
              _metadataCard(_savedDocument!),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_l('Adatkitöltés', 'Data completion', 'Datenerfassung'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                      Text('$filled / 10', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: completion, minHeight: 7, borderRadius: BorderRadius.circular(8), color: const Color(0xFFE6B85C), backgroundColor: Colors.white12),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(_l('Felismert CMR adatok', 'Recognized CMR data', 'Erkannte CMR-Daten'), key: const ValueKey('cmr-results-title'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(_l('Ellenőrizd és javítsd az adatokat. Az OCR-t mindig vesd össze az eredeti dokumentummal.', 'Review and correct the data. Always compare OCR results with the original document.', 'Daten prüfen und korrigieren. OCR-Ergebnisse immer mit dem Originaldokument vergleichen.'), style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            _field(_l('CMR szám', 'CMR number', 'CMR-Nummer'), _cmrNumber),
            _field(_l('Feladó', 'Consignor', 'Absender'), _shipper, maxLines: 2),
            _field(_l('Címzett', 'Consignee', 'Empfänger'), _consignee, maxLines: 2),
            _field(_l('Felrakóhely', 'Loading place', 'Ladeort'), _loadingPlace, maxLines: 2),
            _field(_l('Lerakóhely', 'Delivery place', 'Entladeort'), _deliveryPlace, maxLines: 2),
            _field(_l('Dátum', 'Date', 'Datum'), _date),
            _field(_l('Rendszám', 'Plate', 'Kennzeichen'), _plate, textCapitalization: TextCapitalization.characters),
            _field(_l('Darabszám', 'Package count', 'Packstückzahl'), _packageCount, keyboardType: TextInputType.number),
            _field(_l('Bruttó tömeg (kg)', 'Gross weight (kg)', 'Bruttogewicht (kg)'), _grossWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _field(_l('Áru', 'Goods', 'Ware'), _goods, maxLines: 3),
            const SizedBox(height: 8),
            ExpansionTile(
              collapsedIconColor: Colors.white60,
              iconColor: const Color(0xFFE6B85C),
              title: Text(_l('OCR nyers szöveg', 'Raw OCR text', 'OCR-Rohtext'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: SelectableText(widget.cmr.rawText.trim().isEmpty ? _l('Nem sikerült szöveget felismerni.', 'No text could be recognized.', 'Es konnte kein Text erkannt werden.') : widget.cmr.rawText, style: const TextStyle(color: Colors.white70, height: 1.35)),
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
              label: Text(_saving ? _l('Mentés…', 'Saving…', 'Speichern…') : (_savedDocument == null ? _l('Mentés + GPS + automatikus szinkron', 'Save + GPS + automatic sync', 'Speichern + GPS + automatische Synchronisierung') : _l('Módosítások mentése', 'Save changes', 'Änderungen speichern'))),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: const Color(0xFFE6B85C), foregroundColor: Colors.black, textStyle: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('share-cmr'),
              onPressed: (_sharing || _saving) ? null : _share,
              icon: _sharing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share_rounded),
              label: Text(_l('E-mail • Viber • Megosztás', 'Email • Viber • Share', 'E-Mail • Viber • Teilen')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFFE6B85C))),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.document_scanner_rounded),
              label: Text(_l('Új CMR fotózása', 'Photograph new CMR', 'Neuen CMR fotografieren')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataCard(ScannedDocument document) {
    final loc = document.location;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_l('Mentési és szinkronadat', 'Save and sync data', 'Speicher- und Synchronisierungsdaten'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(_l('Idő: ${_formatDate(document.createdAt)}', 'Time: ${_formatDate(document.createdAt)}', 'Zeit: ${_formatDate(document.createdAt)}'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            loc == null ? 'GPS: nincs helyadat' : 'GPS: ${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)} • ±${loc.accuracy.toStringAsFixed(0)} m',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(_l('Státusz: ${_syncText(document.syncState)}', 'Status: ${_syncText(document.syncState)}', 'Status: ${_syncText(document.syncState)}'), style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w800)),
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
          Row(
            children: [
              Expanded(child: Text(_l('Képminőség', 'Image quality', 'Bildqualität'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              Text('${widget.quality.score}/100', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 7),
          Text(warnings.isEmpty ? _l('A képminőség rendben.', 'Image quality is good.', 'Die Bildqualität ist in Ordnung.') : warnings.join('\n'), style: TextStyle(color: warnings.isEmpty ? const Color(0xFF48D597) : Colors.orangeAccent, height: 1.35)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {int maxLines = 1, TextInputType? keyboardType, TextCapitalization textCapitalization = TextCapitalization.sentences}) {
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE6B85C))),
        ),
      ),
    );
  }
}
