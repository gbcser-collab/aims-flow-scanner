import '../models/scan_models.dart';

class CmrParser {
  const CmrParser();

  CmrData parse(String raw) {
    final normalized = raw.replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return CmrData(
      cmrNumber: _cmrNumber(lines, normalized),
      shipper: _afterLabel(lines, const ['sender', 'feladó', 'absender', 'nadawca', 'expéditeur']),
      consignee: _afterLabel(lines, const ['consignee', 'címzett', 'empfänger', 'odbiorca', 'destinataire']),
      loadingPlace: _afterLabel(lines, const ['place of taking over', 'felrakóhely', 'lieu de chargement', 'miejsce załadunku', 'übernahmeort']),
      deliveryPlace: _afterLabel(lines, const ['place of delivery', 'lerakóhely', 'lieu de livraison', 'miejsce dostawy', 'ablieferungsort']),
      date: _firstMatch(normalized, RegExp(r'\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20)?\d{2}\b')),
      plate: _plate(normalized),
      packageCount: _packages(lines, normalized),
      grossWeightKg: _weight(normalized),
      goodsDescription: _afterLabel(lines, const ['nature of goods', 'áru megnevezése', 'bezeichnung des gutes', 'rodzaj towaru', 'nature de la marchandise']),
      rawText: raw,
    );
  }

  String? _cmrNumber(List<String> lines, String raw) {
    final labelled = _afterLabel(lines, const ['cmr no', 'cmr nr', 'cmr szám', 'lettre de voiture']);
    if (labelled != null) return labelled;
    final match = RegExp(r'\b(?:CMR[\s:#-]*)?([A-Z0-9][A-Z0-9/-]{5,20})\b', caseSensitive: false).firstMatch(raw);
    return match?.group(1) ?? match?.group(0);
  }

  String? _plate(String raw) {
    final patterns = [
      RegExp(r'\b[A-Z]{3}[- ]?\d{3}\b', caseSensitive: false),
      RegExp(r'\b[A-Z]{2}[- ]?[A-Z]{2}[- ]?\d{2,4}\b', caseSensitive: false),
      RegExp(r'\b[A-Z]{1,3}[- ]?[0-9A-Z]{2,5}\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) return match.group(0)?.toUpperCase();
    }
    return null;
  }

  double? _weight(String raw) {
    final match = RegExp(r'\b(\d{1,6}(?:[.,]\d{1,3})?)\s*(?:kg|kgs|kilogram)\b', caseSensitive: false).firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  int? _packages(List<String> lines, String raw) {
    final labelled = _afterLabel(lines, const ['number of packages', 'darabszám', 'anzahl der packstücke', 'ilość sztuk', 'nombre de colis']);
    if (labelled != null) {
      final number = RegExp(r'\b\d{1,5}\b').firstMatch(labelled);
      if (number != null) return int.tryParse(number.group(0)!);
    }
    final general = RegExp(r'\b(\d{1,5})\s*(?:pcs|pc|db|colli|pal(?:let)?s?)\b', caseSensitive: false).firstMatch(raw);
    return general == null ? null : int.tryParse(general.group(1)!);
  }

  String? _afterLabel(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      for (final label in labels) {
        final index = lower.indexOf(label.toLowerCase());
        if (index < 0) continue;
        final start = (index + label.length).clamp(0, lines[i].length).toInt();
        final sameLine = lines[i]
            .substring(start)
            .replaceFirst(RegExp(r'^\s*[:.-]?\s*'), '')
            .trim();
        if (sameLine.length >= 3) return sameLine;
        if (i + 1 < lines.length && lines[i + 1].length >= 3) return lines[i + 1];
      }
    }
    return null;
  }

  String? _firstMatch(String raw, RegExp pattern) => pattern.firstMatch(raw)?.group(0);
}
