import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../models/scan_models.dart';
import '../services/cmr_parser.dart';
import '../services/ocr_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String? _error;
  String? _scanPath;
  CmrData? _cmr;
  String? _ocrWarning;
  String _phase = '';

  String _filePath(String path) =>
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

  Future<void> _openScanner() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _ocrWarning = null;
      _phase = 'Dokumentum felismerése…';
    });

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: 1,
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      if (!mounted) return;

      final images = result.images;
      if (images == null || images.isEmpty) return;

      final scanPath = images.first;
      setState(() => _phase = 'CMR adatok felismerése…');

      CmrData cmr = const CmrData();
      String? warning;
      final ocr = OcrService();
      try {
        final text = await ocr.recognize(_filePath(scanPath));
        cmr = const CmrParser().parse(text);
        if (text.trim().isEmpty) {
          warning = 'A scan elkészült, de nem találtam olvasható szöveget.';
        }
      } catch (e) {
        warning = 'A scan elkészült, de a szövegfelismerés nem futott le: $e';
      } finally {
        await ocr.dispose();
      }

      if (!mounted) return;
      setState(() {
        _scanPath = scanPath;
        _cmr = cmr;
        _ocrWarning = warning;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message?.trim().isNotEmpty == true
            ? e.message
            : 'A dokumentumszkenner nem indult el (${e.code}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Szkennelési hiba: $e');
    } finally {
      await scanner.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _phase = '';
        });
      }
    }
  }

  void _newScan() {
    setState(() {
      _scanPath = null;
      _cmr = null;
      _ocrWarning = null;
      _error = null;
    });
    _openScanner();
  }

  @override
  Widget build(BuildContext context) {
    if (_scanPath != null) {
      return _ScanReview(
        path: _scanPath!,
        cmr: _cmr ?? const CmrData(),
        warning: _ocrWarning,
        onNewScan: _newScan,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow Scanner'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF171A1F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFE6B85C).withValues(alpha: .35),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AIMS FLOW • SMART',
                    style: TextStyle(
                      color: Color(0xFFE6B85C),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'CMR Scanner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Lapfelismerés, automatikus vágás, perspektívajavítás, OCR és CMR-adatkinyerés egy folyamatban.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _FeatureRow(
              icon: Icons.document_scanner_rounded,
              title: 'Automatikus dokumentumszkenner',
              subtitle: 'Megkeresi a lap széleit, levágja és kiegyenesíti a CMR-t.',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.text_snippet_rounded,
              title: 'OCR szövegfelismerés',
              subtitle: 'A kész scanből kiolvassa a nyomtatott szöveget a készüléken.',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.auto_awesome_rounded,
              title: 'CMR mezők felismerése',
              subtitle: 'Kikeresi többek között a CMR-számot, feladót, címzettet, rendszámot és súlyt.',
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: .45),
                  ),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _openScanner,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(
                _busy
                    ? (_phase.isEmpty ? 'Feldolgozás…' : _phase)
                    : 'Scanner megnyitása',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'A dokumentumszkenner és az OCR első használatkor letölthet szükséges Google ML Kit komponenseket.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14181D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE6B85C).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFE6B85C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanReview extends StatelessWidget {
  const _ScanReview({
    required this.path,
    required this.cmr,
    required this.onNewScan,
    this.warning,
  });

  final String path;
  final CmrData cmr;
  final String? warning;
  final VoidCallback onNewScan;

  String get _filePath =>
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

  bool get _hasOcr => cmr.rawText.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('CMR • Smart Scan'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 430),
              decoration: BoxDecoration(
                color: const Color(0xFF101216),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(_filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 220,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'A scan elkészült, de az előnézetet nem sikerült betölteni.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_hasOcr ? const Color(0xFF14231C) : const Color(0xFF2A2113)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (_hasOcr ? const Color(0xFF48D597) : Colors.orange)
                      .withValues(alpha: .35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _hasOcr ? Icons.verified_rounded : Icons.warning_amber_rounded,
                    color: _hasOcr ? const Color(0xFF48D597) : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warning ??
                          (_hasOcr
                              ? 'A dokumentum levágva, kiegyenesítve és OCR-rel feldolgozva. Ellenőrizd a felismert mezőket.'
                              : 'A dokumentum elkészült, de nem találtam biztosan olvasható szöveget.'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Felismert CMR adatok',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Az automatikus felismerést mindig ellenőrizd az eredeti dokumentummal.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            _field('CMR szám', cmr.cmrNumber),
            _field('Feladó', cmr.shipper),
            _field('Címzett', cmr.consignee),
            _field('Felrakóhely', cmr.loadingPlace),
            _field('Lerakóhely', cmr.deliveryPlace),
            _field('Dátum', cmr.date),
            _field('Rendszám', cmr.plate),
            _field('Darabszám', cmr.packageCount?.toString()),
            _field(
              'Bruttó tömeg',
              cmr.grossWeightKg == null ? null : '${cmr.grossWeightKg} kg',
            ),
            _field('Áru', cmr.goodsDescription),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF14181D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ExpansionTile(
                collapsedIconColor: Colors.white60,
                iconColor: const Color(0xFFE6B85C),
                title: const Text(
                  'OCR nyers szöveg',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    child: SelectableText(
                      cmr.rawText.trim().isEmpty
                          ? 'Nem sikerült szöveget felismerni.'
                          : cmr.rawText,
                      style: const TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onNewScan,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Új CMR szkennelése'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String? value) {
    final hasValue = value?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14181D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            hasValue ? value! : 'Nincs biztos felismerés',
            style: TextStyle(
              color: hasValue ? Colors.white : Colors.orange.shade300,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
