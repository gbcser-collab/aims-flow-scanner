import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/cmr_parser.dart';

void main() {
  test('parses a standard numbered printed CMR OCR transcript', () {
    const raw = '''
INTERNATIONAL CONSIGNMENT NOTE CMR
CMR No: HU-2026-847291

1 Sender (name, address, country)
Minta Feladó Kft.
1117 Budapest, Budafoki út 1.
Hungary

2 Consignee (name, address, country)
Example Receiver Sp. z o.o.
60-101 Poznań, Magazynowa 18.
Poland

3 Place of delivery of the goods
Poznań, Poland

4 Place and date of taking over the goods
Győr, Hungary
21.09.2026

7 Number of packages
12 pallets

9 Nature of goods
Machine parts

11 Gross weight in kg
1250 kg

16 Carrier
Logistic AIMS
SIP-115

21 Established in / on
Győr 21.09.2026
''';

    final cmr = const CmrParser().parse(raw);

    expect(cmr.cmrNumber, 'HU-2026-847291');
    expect(cmr.shipper, contains('Minta Feladó Kft.'));
    expect(cmr.consignee, contains('Example Receiver'));
    expect(cmr.loadingPlace, contains('Győr'));
    expect(cmr.deliveryPlace, contains('Poznań'));
    expect(cmr.date, '21.09.2026');
    expect(cmr.plate, 'SIP-115');
    expect(cmr.packageCount, 12);
    expect(cmr.grossWeightKg, 1250);
    expect(cmr.goodsDescription, contains('Machine parts'));
  });

  test('still parses label-only OCR when field numbers are lost', () {
    const raw = '''
CMR NR ABC123456
Feladó:
Teszt Transport Kft.
Címzett:
Minta Partner Kft.
Felrakóhely:
Győr
Lerakóhely:
Bratislava
Darabszám: 8 pallets
Bruttó tömeg: 980 kg
Rendszám SIP-115
22.09.2026
''';

    final cmr = const CmrParser().parse(raw);

    expect(cmr.shipper, contains('Teszt Transport'));
    expect(cmr.consignee, contains('Minta Partner'));
    expect(cmr.loadingPlace, 'Győr');
    expect(cmr.deliveryPlace, 'Bratislava');
    expect(cmr.packageCount, 8);
    expect(cmr.grossWeightKg, 980);
    expect(cmr.plate, 'SIP-115');
  });
}
