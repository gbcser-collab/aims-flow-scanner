import 'package:aims_flow_scanner/services/cmr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CmrParser', () {
    test('extracts common international CMR fields', () {
      const raw = '''
CMR No: HU-123456
Sender: Logistic AIMS Kft.
Consignee: Example GmbH
Place of taking over: Gyor
Place of delivery: Wien
15.09.2026
ABC-123
12 pallets
2450 kg
Nature of goods: Machine parts
''';

      final cmr = const CmrParser().parse(raw);

      expect(cmr.cmrNumber, 'HU-123456');
      expect(cmr.shipper, 'Logistic AIMS Kft.');
      expect(cmr.consignee, 'Example GmbH');
      expect(cmr.loadingPlace, 'Gyor');
      expect(cmr.deliveryPlace, 'Wien');
      expect(cmr.date, '15.09.2026');
      expect(cmr.plate, 'ABC-123');
      expect(cmr.packageCount, 12);
      expect(cmr.grossWeightKg, 2450);
      expect(cmr.goodsDescription, 'Machine parts');
    });

    test('keeps the OCR text for manual review', () {
      const raw = 'CMR szám: AIMS-778899\nFeladó: Teszt Kft.';
      final cmr = const CmrParser().parse(raw);
      expect(cmr.rawText, raw);
      expect(cmr.cmrNumber, 'AIMS-778899');
      expect(cmr.shipper, 'Teszt Kft.');
    });
  });
}
