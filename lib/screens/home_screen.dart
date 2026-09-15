import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String? _error;
  String? _scanPath;

  Future<void> _openScanner() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
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
      if (images != null && images.isNotEmpty) {
        setState(() => _scanPath = images.first);
      }
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
      if (mounted) setState(() => _busy = false);
    }
  }

  void _newScan() {
    setState(() {
      _scanPath = null;
      _error = null;
    });
    _openScanner();
  }

  @override
  Widget build(BuildContext context) {
    if (_scanPath != null) {
      return _ScanReview(path: _scanPath!, onNewScan: _newScan);
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
                border: Border.all(color: const Color(0xFFE6B85C).withValues(alpha: .35)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AIMS FLOW',
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
                    'Valódi dokumentumszkenner: automatikus lapfelismerés, auto-capture, pontos élvágás és perspektívakorrekció.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _FeatureRow(
              icon: Icons.document_scanner_rounded,
              title: 'Automatikus lapfelismerés',
              subtitle: 'A scanner megkeresi a dokumentum széleit és magától exponálhat.',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.crop_rotate_rounded,
              title: 'Kivágás és kiegyenesítés',
              subtitle: 'A ferdén fotózott CMR-t automatikusan perspektívába húzza.',
            ),
            const SizedBox(height: 10),
            const _FeatureRow(
              icon: Icons.auto_fix_high_rounded,
              title: 'Javítás és forgatás',
              subtitle: 'A natív dokumentummotor segít olvasható, tiszta eredményt készíteni.',
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: .45)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
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
              label: Text(_busy ? 'Scanner indítása…' : 'Scanner megnyitása'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Az első indításkor a Google Play-szolgáltatások letölthetik a dokumentumszkenner szükséges komponenseit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

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
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanReview extends StatelessWidget {
  const _ScanReview({required this.path, required this.onNewScan});

  final String path;
  final VoidCallback onNewScan;

  String get _filePath => path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('CMR • kész scan'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101216),
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  File(_filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
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
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF14231C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF48D597).withValues(alpha: .35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Color(0xFF48D597)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A dokumentumot a natív scanner levágta és perspektívába igazította.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
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
            ),
          ],
        ),
      ),
    );
  }
}
