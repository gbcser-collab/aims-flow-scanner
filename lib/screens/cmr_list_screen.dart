import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/scan_repository.dart';
import '../widgets/aims_skin.dart';
import 'scan_review_screen.dart';

class CmrListScreen extends StatefulWidget {
  const CmrListScreen({super.key});

  @override
  State<CmrListScreen> createState() => _CmrListScreenState();
}

class _CmrListScreenState extends State<CmrListScreen> {
  static const _repository = ScanRepository();
  final _query = TextEditingController();
  bool _loading = true;
  List<ScannedDocument> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _repository.loadAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ScannedDocument> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((document) {
      final cmr = document.cmr;
      return [cmr.cmrNumber, cmr.shipper, cmr.consignee, cmr.loadingPlace, cmr.deliveryPlace, cmr.plate]
          .whereType<String>()
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  Future<void> _open(ScannedDocument document) async {
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
    await _load();
  }

  String _format(DateTime value) {
    final v = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${v.year}.${two(v.month)}.${two(v.day)} ${two(v.hour)}:${two(v.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('CMR-ek'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: AimsBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _query,
              style: const TextStyle(color: Colors.white),
              decoration: aimsInputDecoration(
                'Keresés CMR, cég, hely, rendszám…',
                prefix: const Icon(Icons.search_rounded, color: Color(0xFFB7E6FF)),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: aimsCyan))
            else if (items.isEmpty)
              const AimsGlassCard(
                child: Text('Nincs a keresésnek megfelelő mentett CMR.', style: TextStyle(color: Colors.white70)),
              )
            else
              ...items.map((document) {
                final image = File(document.imagePath);
                final title = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR ${document.cmr.cmrNumber}' : 'Mentett CMR';
                final route = [document.cmr.loadingPlace, document.cmr.deliveryPlace]
                    .whereType<String>()
                    .where((e) => e.trim().isNotEmpty)
                    .join(' → ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AimsGlassCard(
                    padding: EdgeInsets.zero,
                    radius: 16,
                    child: ListTile(
                      onTap: () => _open(document),
                      contentPadding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 52,
                          height: 62,
                          child: image.existsSync()
                              ? Image.file(image, fit: BoxFit.cover)
                              : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_outlined, color: aimsCyan)),
                        ),
                      ),
                      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (route.isNotEmpty) Text(route, style: const TextStyle(color: Color(0xFF9FD5FF))),
                          Text(_format(document.createdAt), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: aimsCyan),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
