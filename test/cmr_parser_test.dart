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
      expect(cmr.filledFieldCount, 10);
    });

    test('keeps the OCR text for manual review', () {
      const raw = 'CMR szám: AIMS-778899\nFeladó: Teszt Kft.';
      final cmr = const CmrParser().parse(raw);
      expect(cmr.rawText, raw);
      expect(cmr.cmrNumber, 'AIMS-778899');
      expect(cmr.shipper, 'Teszt Kft.');
    });

    test('recognizes standalone CMR serial, Hungarian plate, pallet count and weight', () {
      const raw = '''
157357
Feladó: Logistic-A.I.M.S. Kft.
Címzett: Example Kft.
Felrakóhely: Győr
Lerakóhely: Budapest
2026-09-15
SWF-373
1 raklap
112 kg
Áru megnevezése: alkatrész
''';

      final cmr = const CmrParser().parse(raw);
      expect(cmr.cmrNumber, '157357');
      expect(cmr.plate, 'SWF-373');
      expect(cmr.packageCount, 1);
      expect(cmr.grossWeightKg, 112);
      expect(cmr.date, '2026-09-15');
      expect(cmr.filledFieldCount, greaterThanOrEqualTo(8));
    });

    test('recognizes modern Hungarian four-letter plate format', () {
      const raw = 'Vehicle: AA AA-123\nGross weight: 900 kg';
      final cmr = const CmrParser().parse(raw);
      expect(cmr.plate, 'AA-AA-123');
      expect(cmr.grossWeightKg, 900);
    });
  });
}
