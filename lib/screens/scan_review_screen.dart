import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_models.dart';

class ScanReviewScreen extends StatelessWidget {
  const ScanReviewScreen({
    super.key,
    required this.processedImagePath,
    required this.quality,
    required this.cmr,
  });

  final String processedImagePath;
  final ScanQuality quality;
  final CmrData cmr;

  @override
  Widget build(BuildContext context) {
    final hasText = cmr.rawText.trim().isNotEmpty;
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
                File(processedImagePath),
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
                          ? 'A kép feldolgozása és az OCR lefutott. Ellenőrizd a felismert mezőket.'
                          : 'A kép feldolgozása lefutott, de ezen a képen az OCR nem talált biztosan olvasható szöveget.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
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
            _field('Bruttó tömeg', cmr.grossWeightKg == null ? null : '${cmr.grossWeightKg} kg'),
            _field('Áru', cmr.goodsDescription),
            const SizedBox(height: 8),
            ExpansionTile(
              collapsedIconColor: Colors.white60,
              iconColor: const Color(0xFFE6B85C),
              title: const Text('OCR nyers szöveg', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: SelectableText(
                    cmr.rawText.trim().isEmpty ? 'Nem sikerült szöveget felismerni.' : cmr.rawText,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _qualityCard(),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Vissza a kezdőlapra'),
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

  Widget _qualityCard() {
    final warnings = quality.warnings;
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
            style: TextStyle(color: warnings.isEmpty ? const Color(0xFF48D597) : Colors.orangeAccent, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, String? value) {
    final has = value?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            has ? value! : 'Nincs biztos találat',
            style: TextStyle(color: has ? Colors.white : Colors.white38, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
