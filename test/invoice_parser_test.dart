import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/invoice_parser.dart';

void main() {
  const parser = InvoiceParser();

  test('Hungarian fuel receipt is classified and parsed', () {
    final result = parser.parse('''
MOL Töltőállomás
DIESEL
42,35 L
EGYSÉGÁR 615,90
ÖSSZESEN 26083,00 HUF
2026.09.20
Bizonylat szám: HU-77881
''');
    expect(result.category, InvoiceCategory.fuel);
    expect(result.date, '2026-09-20');
    expect(result.currency, 'HUF');
    expect(result.totalAmount, closeTo(26083, 0.01));
    expect(result.liters, closeTo(42.35, 0.001));
  });

  test('European toll invoice is classified as toll or vignette', () {
    final result = parser.parse('''
ASFINAG
E-VIGNETTE
Invoice No: AT-2026-9911
Date 20.09.2026
TOTAL 11,50 EUR
AT
''');
    expect(result.category, InvoiceCategory.tollVignette);
    expect(result.currency, 'EUR');
    expect(result.totalAmount, closeTo(11.5, 0.01));
    expect(result.documentNumber, contains('AT-2026-9911'));
    expect(result.countryCode, 'AT');
  });

  test('German service invoice is classified as service', () {
    final result = parser.parse('''
AUTO WERKSTATT
RECHNUNG NR: DE-4418
20-09-2026
SERVICE
ARBEITSLOHN
GESAMT 428,90 EUR
''');
    expect(result.category, InvoiceCategory.service);
    expect(result.currency, 'EUR');
    expect(result.totalAmount, closeTo(428.9, 0.01));
  });
}
