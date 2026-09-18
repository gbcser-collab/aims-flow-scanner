class FuelReceiptData {
  const FuelReceiptData({
    this.station,
    this.date,
    this.totalAmount,
    this.currency,
    this.liters,
    this.pricePerLiter,
    this.receiptNumber,
    this.rawText = '',
  });

  final String? station;
  final String? date;
  final double? totalAmount;
  final String? currency;
  final double? liters;
  final double? pricePerLiter;
  final String? receiptNumber;
  final String rawText;
}

class FuelReceiptParser {
  const FuelReceiptParser();

  FuelReceiptData parse(String raw) {
    final text = raw.replaceAll('\r', '\n');
    final lines = text
        .split('\n')
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final totalMatch = RegExp(
      r'(?:TOTAL|ÖSSZESEN|FIZETEND[ŐO]|SUMME|RAZEM|CELKEM)[^\d]{0,18}(\d{1,7}(?:[.,]\d{1,2})?)\s*(HUF|FT|EUR|€|PLN|CZK)?',
      caseSensitive: false,
    ).firstMatch(text);

    final litersMatch = RegExp(
      r'\b(\d{1,4}(?:[.,]\d{1,3})?)\s*(?:L|LITER|LITRE|LITR[ÓO]W?)\b',
      caseSensitive: false,
    ).firstMatch(text);

    final unitMatch = RegExp(
      r'(?:PRICE/L|UNIT PRICE|EGYS[ÉE]G[ÁA]R|PREIS/L|CENA/L)[^\d]{0,18}(\d{1,6}(?:[.,]\d{1,3})?)',
      caseSensitive: false,
    ).firstMatch(text);

    final date = _firstDate(text);
    final receipt = _afterLabel(lines, const [
      'receipt no', 'receipt nr', 'nyugta szám', 'bizonylat szám',
      'beleg nr', 'paragon nr', 'document no', 'transaction no',
    ]);

    String? station;
    for (final line in lines.take(8)) {
      final lower = line.toLowerCase();
      if (line.length < 3 || line.length > 100) continue;
      if (RegExp(r'^\d').hasMatch(line)) continue;
      if (lower.contains('receipt') || lower.contains('nyugta') || lower.contains('invoice')) continue;
      if (RegExp(r'\b(total|összesen|summe|razem|celkem)\b', caseSensitive: false).hasMatch(line)) continue;
      station = line;
      break;
    }

    final rawCurrency = totalMatch?.group(2)?.toUpperCase();
    final currency = switch (rawCurrency) {
      'FT' => 'HUF',
      '€' => 'EUR',
      final String value => value,
      _ => null,
    };

    return FuelReceiptData(
      station: station,
      date: date,
      totalAmount: _number(totalMatch?.group(1)),
      currency: currency,
      liters: _number(litersMatch?.group(1)),
      pricePerLiter: _number(unitMatch?.group(1)),
      receiptNumber: receipt,
      rawText: raw,
    );
  }

  double? _number(String? value) =>
      value == null ? null : double.tryParse(value.replaceAll(',', '.'));

  String? _firstDate(String raw) {
    for (final pattern in [
      RegExp(r'\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20)?\d{2}\b'),
      RegExp(r'\b20\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b'),
    ]) {
      final match = pattern.firstMatch(raw);
      if (match != null) return match.group(0);
    }
    return null;
  }

  String? _afterLabel(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      for (final label in labels) {
        final index = lower.indexOf(label);
        if (index < 0) continue;
        final value = lines[i]
            .substring(index + label.length)
            .replaceFirst(RegExp(r'^[\s:;#.-]+'), '')
            .trim();
        if (value.length >= 2) return value;
        if (i + 1 < lines.length && lines[i + 1].length >= 2) return lines[i + 1];
      }
    }
    return null;
  }
}
