import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _opening = false;
  String? _error;

  Future<void> _openScanner() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'Nem található használható kamera.');
        return;
      }
      final backs = cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      final selected = backs.isNotEmpty ? backs.first : cameras.first;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScannerScreen(camera: selected)),
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A kamera nem érhető el (${e.code}). Ellenőrizd a kameraengedélyt.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A scanner nem indult el: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow Smart Scanner'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF171A1F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6B85C).withValues(alpha: .35)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AIMS FLOW • SMART',
                    style: TextStyle(
                      color: Color(0xFFE6B85C),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'CMR Scanner',
                    style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Egy fotó után automatikusan feldolgozza a dokumentumot, kiegyenesíti, kiolvassa a szöveget és megpróbálja kitölteni a CMR mezőket.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('open-smart-scanner'),
              onPressed: _opening ? null : _openScanner,
              icon: _opening
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_opening ? 'Kamera indítása…' : 'Smart Scan indítása'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: .4)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            const SizedBox(height: 18),
            const _Feature(
              icon: Icons.crop_free_rounded,
              title: 'Dokumentum-korrekció',
              text: 'Megkeresi a lapot, levágja a hátteret és perspektívába húzza.',
            ),
            const SizedBox(height: 10),
            const _Feature(
              icon: Icons.text_snippet_rounded,
              title: 'OCR',
              text: 'A feldolgozott képből automatikusan kiolvassa a nyomtatott szöveget.',
            ),
            const SizedBox(height: 10),
            const _Feature(
              icon: Icons.auto_awesome_rounded,
              title: 'CMR mezők',
              text: 'CMR-szám, feladó, címzett, helyek, dátum, rendszám, darabszám, súly és áru.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE6B85C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(color: Colors.white60, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
