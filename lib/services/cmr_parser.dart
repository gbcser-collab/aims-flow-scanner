import '../models/scan_models.dart';

class CmrParser {
  const CmrParser();

  CmrData parse(String raw) {
    final normalized = _normalize(raw);
    final lines = normalized
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return CmrData(
      cmrNumber: _cmrNumber(lines, normalized),
      shipper: _field(lines, 1, const ['sender', 'feladó', 'absender', 'nadawca', 'expéditeur']),
      consignee: _field(lines, 2, const ['consignee', 'címzett', 'empfänger', 'odbiorca', 'destinataire']),
      deliveryPlace: _field(lines, 3, const ['place of delivery of the goods', 'place of delivery', 'lerakóhely', 'lieu prévu pour la livraison', 'lieu de livraison', 'miejsce dostawy', 'ablieferungsort']),
      loadingPlace: _field(lines, 4, const ['place and date of taking over the goods', 'place and date of taking over', 'place of taking over', 'felrakóhely', 'lieu et date de la prise en charge', 'lieu de chargement', 'miejsce załadunku', 'übernahmeort']),
      date: _date(normalized),
      plate: _plate(normalized),
      packageCount: _packageCount(lines, normalized),
      grossWeightKg: _weight(lines, normalized),
      goodsDescription: _field(lines, 9, const ['nature of goods', 'áru megnevezése', 'bezeichnung des gutes', 'rodzaj towaru', 'nature de la marchandise']),
      rawText: raw,
    );
  }

  String _normalize(String value) => value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('–', '-').replaceAll('—', '-').replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  String? _cmrNumber(List<String> lines, String raw) {
    final labelled = _afterLabel(lines, const ['cmr no', 'cmr no.', 'cmr nr', 'cmr nr.', 'cmr szám', 'lettre de voiture', 'consignment note no']);
    if (_usable(labelled)) return _trimValue(labelled!);
    final patterns = <RegExp>[
      RegExp(r'\bCMR\s*(?:NO|NR|N[°º]|SZÁM)?\s*[:#.-]?\s*([A-Z0-9][A-Z0-9/.-]{4,24})\b', caseSensitive: false),
      RegExp(r'\b(?:NO|NR|N[°º])\s*[:#.-]?\s*([A-Z]{0,4}\d[A-Z0-9/.-]{4,20})\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(raw)?.group(1);
      if (_usable(value)) return _trimValue(value!);
    }
    return null;
  }

  String? _field(List<String> lines, int number, List<String> labels) {
    final numbered = _afterFieldNumber(lines, number, labels);
    if (_usableFieldValue(numbered, labels)) return _trimValue(numbered!);
    final labelled = _afterLabel(lines, labels);
    if (_usableFieldValue(labelled, labels)) return _trimValue(labelled!);
    return null;
  }

  String? _afterFieldNumber(List<String> lines, int number, List<String> labels) {
    // A CMR field number must be followed by a real field separator or
    // whitespace. The previous optional separator allowed box 1 to match a
    // date such as "15.09.2026" and box 2 to match "2.09.2026".
    final startPattern = RegExp(
      '^\\s*' + RegExp.escape(number.toString()) + '(?:\\s*[.)\\-:]\\s*|\\s+)(.*)\$',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final match = startPattern.firstMatch(lines[i]);
      if (match == null) continue;
      var same = (match.group(1) ?? '').trim();
      same = _removeKnownLabels(same, labels);
      if (_usableFieldValue(same, labels)) return same;
      final collected = <String>[];
      for (var j = i + 1; j < lines.length && collected.length < 3; j++) {
        if (_looksLikeNextField(lines[j], number)) break;
        final candidate = _removeKnownLabels(lines[j], labels);
        if (!_usableFieldValue(candidate, labels)) continue;
        collected.add(candidate);
        if (collected.join(' ').length >= 18) break;
      }
      if (collected.isNotEmpty) return collected.join(', ');
    }
    return null;
  }

  bool _looksLikeNextField(String line, int current) {
    final match = RegExp(r'^\s*(\d{1,2})\s*[.)\-:]').firstMatch(line);
    if (match == null) return false;
    final value = int.tryParse(match.group(1)!);
    return value != null && value != current && value >= 1 && value <= 24;
  }

  String _removeKnownLabels(String value, List<String> labels) {
    var result = value.trim();
    for (final label in labels) {
      final lower = result.toLowerCase();
      final index = lower.indexOf(label.toLowerCase());
      if (index < 0) continue;
      final before = result.substring(0, index).trim();
      final after = result.substring(index + label.length).trim();
      result = after.length >= before.length ? after : before;
    }
    return result.replaceFirst(RegExp(r'^\s*[:;,.\-]+\s*'), '').trim();
  }

  String? _afterLabel(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      for (final label in labels) {
        final index = lower.indexOf(label.toLowerCase());
        if (index < 0) continue;
        final start = (index + label.length).clamp(0, lines[i].length).toInt();
        final sameLine = lines[i].substring(start).replaceFirst(RegExp(r'^\s*[:;,.\-]?\s*'), '').trim();
        if (_usableFieldValue(sameLine, labels)) return sameLine;
        for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
          if (_looksLikeAnyFieldStart(lines[j])) break;
          final candidate = lines[j].trim();
          if (_usableFieldValue(candidate, labels)) return candidate;
        }
      }
    }
    return null;
  }

  bool _looksLikeAnyFieldStart(String line) => RegExp(r'^\s*(?:[1-9]|1\d|2[0-4])\s*[.)\-:]').hasMatch(line);
  bool _usable(String? value) => value != null && value.trim().length >= 2;

  bool _usableFieldValue(String? value, List<String> labels) {
    if (!_usable(value)) return false;
    final v = value!.trim();
    final lower = v.toLowerCase();
    if (v.length < 3) return false;
    if (labels.any((label) => lower == label.toLowerCase())) return false;
    const promptWords = <String>['name', 'address', 'country', 'nom', 'adresse', 'pays', 'anschrift', 'land', 'nazwa', 'adres', 'kraj'];
    var promptHits = 0;
    for (final word in promptWords) {
      if (RegExp('(^|[^a-zà-ž])' + RegExp.escape(word) + r'([^a-zà-ž]|$)', caseSensitive: false).hasMatch(lower)) promptHits++;
    }
    if (promptHits >= 2) return false;
    const promptFragments = <String>['of the goods', 'the goods', 'des marchandises', 'der güter', 'towaru'];
    if (promptFragments.any((fragment) => lower == fragment)) return false;
    return RegExp(r'[A-Za-zÀ-ž0-9]').hasMatch(v);
  }

  String _trimValue(String value) => value.replaceFirst(RegExp(r'^\s*[:;,.\-]+\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _date(String raw) {
    final patterns = <RegExp>[
      RegExp(r'\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:19|20)?\d{2}\b'),
      RegExp(r'\b(?:19|20)\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) return match.group(0);
    }
    return null;
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

  double? _weight(List<String> lines, String raw) {
    final field11 = _afterFieldNumber(lines, 11, const ['gross weight', 'gross weight in kg', 'bruttó tömeg', 'bruttogewicht', 'poids brut', 'waga brutto']);
    for (final source in [field11, raw]) {
      if (source == null) continue;
      final match = RegExp(r'\b(\d{1,6}(?:[.,]\d{1,3})?)\s*(?:kg|kgs|kilogram)?\b', caseSensitive: false).firstMatch(source);
      if (match != null) {
        final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
        if (value != null && value > 0) return value;
      }
    }
    return null;
  }

  int? _packageCount(List<String> lines, String raw) {
    final field7 = _afterFieldNumber(lines, 7, const ['number of packages', 'darabszám', 'anzahl der packstücke', 'ilość sztuk', 'nombre de colis']);
    for (final source in [field7, raw]) {
      if (source == null) continue;
      final match = RegExp(r'\b(\d{1,5})\s*(?:pcs|pc|db|colli|pal(?:let)?s?)?\b', caseSensitive: false).firstMatch(source);
      if (match != null) {
        final value = int.tryParse(match.group(1)!);
        if (value != null && value > 0) return value;
      }
    }
    return null;
  }
}
