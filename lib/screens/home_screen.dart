import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/scan_repository.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _repository = ScanRepository();

  bool _opening = false;
  bool _historyLoading = true;
  String? _error;
  List<ScannedDocument> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final items = await _repository.loadAll();
      if (!mounted) return;
      setState(() {
        _history = items;
        _historyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _historyLoading = false);
    }
  }

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
      await _loadHistory();
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

  Future<void> _openSaved(ScannedDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          processedImagePath: document.imagePath,
          quality: document.quality,
          cmr: document.cmr,
          savedDocument: document,
        ),
      ),
    );
    await _loadHistory();
  }

  Future<void> _deleteSaved(ScannedDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mentett CMR törlése?'),
        content: const Text('A dokumentum képe és a mentett CMR-adatok végleg törlődnek erről a készülékről.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Törlés')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(document);
    await _loadHistory();
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow Smart Scanner'),
        actions: [
          IconButton(
            tooltip: 'Mentések frissítése',
            onPressed: _historyLoading ? null : _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
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
                    'AIMS FLOW • SMART • v0.7',
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
                    'Fotó, dokumentum-korrekció, OCR, szerkeszthető CMR mezők és offline mentési előzmények egy folyamatban.',
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
              title: 'OCR + javítható mezők',
              text: 'Kiolvassa a nyomtatott szöveget, a találatokat pedig mentés előtt kézzel is javíthatod.',
            ),
            const SizedBox(height: 10),
            const _Feature(
              icon: Icons.offline_pin_rounded,
              title: 'Offline CMR előzmények',
              text: 'A mentett dokumentumok a telefonon maradnak, újra megnyithatók és módosíthatók.',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Legutóbbi mentések',
                    style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6B85C).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_history.length}',
                    style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_historyLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE6B85C))),
              )
            else if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  children: [
                    Icon(Icons.inbox_rounded, color: Colors.white38),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Még nincs mentett CMR. Az első Smart Scan után a „Mentés offline” gombbal kerül ide.',
                        style: TextStyle(color: Colors.white60, height: 1.35),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._history.map((document) => _historyCard(document)),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final primary = document.cmr.cmrNumber?.trim().isNotEmpty == true
        ? 'CMR ${document.cmr.cmrNumber}'
        : 'Mentett CMR';
    final secondary = [
      document.cmr.consignee,
      document.cmr.deliveryPlace,
    ].whereType<String>().where((item) => item.trim().isNotEmpty).take(2).join(' • ');

    return Semantics(
      label: 'Mentett CMR dokumentum',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          onTap: () => _openSaved(document),
          contentPadding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 54,
              height: 64,
              child: image.existsSync()
                  ? Image.file(image, fit: BoxFit.cover)
                  : const ColoredBox(
                      color: Colors.white10,
                      child: Icon(Icons.description_rounded, color: Colors.white38),
                    ),
            ),
          ),
          title: Text(primary, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              secondary.isEmpty ? _formatDate(document.createdAt) : '$secondary\n${_formatDate(document.createdAt)}',
              style: const TextStyle(color: Colors.white54, height: 1.3),
            ),
          ),
          isThreeLine: secondary.isNotEmpty,
          trailing: IconButton(
            tooltip: 'Mentés törlése',
            onPressed: () => _deleteSaved(document),
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
          ),
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
