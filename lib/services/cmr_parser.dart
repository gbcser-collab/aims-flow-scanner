import '../models/scan_models.dart';

class CmrParser {
  const CmrParser();

  CmrData parse(String raw) {
    final normalized = raw.replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return CmrData(
      cmrNumber: _cmrNumber(lines, normalized),
      shipper: _afterLabel(lines, const [
        'sender', 'feladó', 'absender', 'nadawca', 'expéditeur', 'expediteur',
      ]),
      consignee: _afterLabel(lines, const [
        'consignee', 'címzett', 'empfänger', 'empfanger', 'odbiorca', 'destinataire',
      ]),
      loadingPlace: _afterLabel(lines, const [
        'place of taking over', 'place of taking over the goods', 'felrakóhely',
        'felvétel helye', 'lieu de chargement', 'miejsce załadunku',
        'miejsce zaladunku', 'übernahmeort', 'ubernahmeort', 'ort der übernahme',
      ]),
      deliveryPlace: _afterLabel(lines, const [
        'place of delivery', 'lerakóhely', 'kiszolgáltatás helye',
        'lieu de livraison', 'miejsce dostawy', 'ablieferungsort', 'ort der ablieferung',
      ]),
      date: _date(normalized),
      plate: _plate(normalized),
      packageCount: _packages(lines, normalized),
      grossWeightKg: _weight(normalized),
      goodsDescription: _afterLabel(lines, const [
        'nature of goods', 'áru megnevezése', 'bezeichnung des gutes',
        'rodzaj towaru', 'nature de la marchandise',
        'goods description', 'description of goods',
      ]),
      rawText: raw,
    );
  }

  String? _cmrNumber(List<String> lines, String raw) {
    final labelled = _afterLabel(lines, const [
      'cmr no', 'cmr nr', 'cmr szám', 'cmr number', 'lettre de voiture',
      'frachtbrief nr', 'frachtbrief-nr',
    ]);
    if (labelled != null) {
      final cleaned = _firstIdentifier(labelled);
      if (cleaned != null) return cleaned;
    }

    final explicit = RegExp(
      r'\bCMR\s*(?:NO|NR|N°|NUMBER|SZÁM)?\s*[:#.-]?\s*([A-Z0-9][A-Z0-9/-]{4,20})\b',
      caseSensitive: false,
    ).firstMatch(raw);
    if (explicit != null) return explicit.group(1)?.toUpperCase();

    // Many pre-printed CMR pads have a standalone serial number in the upper area.
    for (final line in lines.take(18)) {
      final match = RegExp(r'^(?:N[O0]\.?\s*)?(\d{6,12})$').firstMatch(line.replaceAll(' ', ''));
      if (match != null) return match.group(1);
    }

    final generic = RegExp(r'\b([A-Z0-9]*\d[A-Z0-9/-]{5,19})\b', caseSensitive: false).firstMatch(raw);
    return generic?.group(1)?.toUpperCase();
  }

  String? _firstIdentifier(String input) {
    final upper = input.trim().toUpperCase();
    final match = RegExp(
      r'\b([A-Z]{1,8}[-/]?[A-Z0-9]*\d[A-Z0-9/-]{2,20}|\d{5,20})\b',
    ).firstMatch(upper);
    return match?.group(1);
  }

  String? _plate(String raw) {
    final upper = raw.toUpperCase();
    final patterns = [
      // Hungarian 2022+ format, e.g. AA AA-123 / AAAA-123.
      RegExp(r'\b[A-Z]{2}[ -]?[A-Z]{2}[- ]?\d{3}\b'),
      // Classic Hungarian format, e.g. SWF-373.
      RegExp(r'\b[A-Z]{3}[- ]?\d{3}\b'),
      // Common European formats.
      RegExp(r'\b[A-Z]{1,3}[- ]?[A-Z]{1,3}[- ]?\d{2,4}\b'),
      RegExp(r'\b[A-Z]{1,3}[- ]?\d{1,4}[- ]?[A-Z]{1,3}\b'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(upper);
      if (match != null) {
        return match.group(0)?.replaceAll(RegExp(r'\s+'), '-').replaceAll('--', '-');
      }
    }
    return null;
  }

  String? _date(String raw) {
    final patterns = [
      RegExp(r'\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20)?\d{2}\b'),
      RegExp(r'\b20\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b'),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(raw)?.group(0);
      if (value != null) return value;
    }
    return null;
  }

  double? _weight(String raw) {
    final patterns = [
      RegExp(r'\b(\d{1,6}(?:[.,]\d{1,3})?)\s*(?:kg|kgs|kilogram|kilograms)\b', caseSensitive: false),
      RegExp(r'(?:gross weight|bruttó tömeg|brutto(?:gewicht)?|poids brut)[^\d]{0,20}(\d{1,6}(?:[.,]\d{1,3})?)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    return null;
  }

  int? _packages(List<String> lines, String raw) {
    final labelled = _afterLabel(lines, const [
      'number of packages', 'darabszám', 'anzahl der packstücke', 'anzahl der packstucke',
      'ilość sztuk', 'ilosc sztuk', 'nombre de colis', 'number of parcels',
    ]);
    if (labelled != null) {
      final number = RegExp(r'\b\d{1,5}\b').firstMatch(labelled);
      if (number != null) return int.tryParse(number.group(0)!);
    }
    final general = RegExp(
      r'\b(\d{1,5})\s*(?:pcs|pc|db|colli|pal(?:let)?s?|raklap|raklapok|paletta|paletták|boxes|cartons?)\b',
      caseSensitive: false,
    ).firstMatch(raw);
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
            .replaceFirst(RegExp(r'^\s*[:;,.\-–—]?\s*'), '')
            .trim();
        if (_usableValue(sameLine)) return sameLine;
        if (i + 1 < lines.length && _usableValue(lines[i + 1])) return lines[i + 1];
      }
    }
    return null;
  }

  bool _usableValue(String value) {
    if (value.length < 2) return false;
    final lower = value.toLowerCase();
    const printedNoise = [
      'sender', 'consignee', 'place of', 'expéditeur', 'destinataire',
      'absender', 'empfänger', 'nadawca', 'odbiorca',
    ];
    return !printedNoise.any((item) => lower == item);
  }
}
