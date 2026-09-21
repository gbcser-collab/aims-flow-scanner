import 'dart:io';

import 'package:flutter/material.dart';

import '../services/aims_locale.dart';
import '../services/smart_document_classifier.dart';
import '../services/smart_document_repository.dart';

class SmartDocumentReviewScreen extends StatefulWidget {
  const SmartDocumentReviewScreen({
    super.key,
    required this.imagePath,
    required this.rawText,
    required this.initialType,
    required this.confidence,
  });

  final String imagePath;
  final String rawText;
  final SmartDocumentType initialType;
  final double confidence;

  @override
  State<SmartDocumentReviewScreen> createState() =>
      _SmartDocumentReviewScreenState();
}

class _SmartDocumentReviewScreenState extends State<SmartDocumentReviewScreen> {
  static const _repository = SmartDocumentRepository();
  late SmartDocumentType _type;
  bool _saving = false;

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
    _type = widget.initialType;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repository.savePending(
        sourceImagePath: widget.imagePath,
        type: _type,
        rawText: widget.rawText,
        confidence: widget.confidence,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'Dokumentum elmentve a telefonon. Szinkronra vár.',
              'Document saved on the phone. Waiting for sync.',
              'Dokument auf dem Telefon gespeichert. Wartet auf Synchronisierung.',
            ),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'A dokumentum mentése nem sikerült: $e',
              'Document save failed: $e',
              'Dokument konnte nicht gespeichert werden: $e',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence = (widget.confidence * 100).clamp(0, 100).round();
    return Scaffold(
      backgroundColor: const Color(0xFF030A13),
      appBar: AppBar(
        title: Text(_l('Smart Document', 'Smart Document', 'Smart Document')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF0C1722),
                constraints: const BoxConstraints(maxHeight: 360),
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _l(
                'Felismert dokumentumtípus',
                'Recognized document type',
                'Erkannter Dokumenttyp',
              ),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SmartDocumentType>(
              initialValue: _type,
              dropdownColor: const Color(0xFF0D2131),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF071725),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: SmartDocumentType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.hu),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _type = value);
                    },
            ),
            const SizedBox(height: 10),
            Text(
              _l(
                'Felismerési biztonság: $confidence%',
                'Recognition confidence: $confidence%',
                'Erkennungssicherheit: $confidence%',
              ),
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1D2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24557D)),
              ),
              child: Text(
                _l(
                  'Ez a dokumentumtípus jelenleg helyben kerül megőrzésre. A Flow nem dobja el akkor sem, ha nincs internet.',
                  'This document type is currently stored locally. Flow does not discard it even without internet.',
                  'Dieser Dokumenttyp wird derzeit lokal gespeichert. Flow verwirft ihn auch ohne Internet nicht.',
                ),
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('smart-document-save-pending'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(
                _l(
                  'MENTÉS A TELEFONRA',
                  'SAVE ON PHONE',
                  'AUF TELEFON SPEICHERN',
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
