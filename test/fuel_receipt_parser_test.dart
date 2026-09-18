import 'package:aims_flow_scanner/services/fuel_receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses common Hungarian fuel receipt', () {
    const raw = '''
MOL KOMÁROM
NYUGTA
Bizonylat szám: ABC-778899
18.09.2026
Diesel
42,35 L
Egységár 618,9
ÖSSZESEN 26212 FT
''';
    final data = const FuelReceiptParser().parse(raw);
    expect(data.station, 'MOL KOMÁROM');
    expect(data.date, '18.09.2026');
    expect(data.liters, 42.35);
    expect(data.pricePerLiter, 618.9);
    expect(data.totalAmount, 26212);
    expect(data.currency, 'HUF');
    expect(data.receiptNumber, 'ABC-778899');
  });

  test('parses international receipt total', () {
    const raw = '''
SHELL WIEN
Receipt No: 123456
2026-09-18
35.20 L
TOTAL 62.50 EUR
''';
    final data = const FuelReceiptParser().parse(raw);
    expect(data.station, 'SHELL WIEN');
    expect(data.date, '2026-09-18');
    expect(data.liters, 35.2);
    expect(data.totalAmount, 62.5);
    expect(data.currency, 'EUR');
  });
}
