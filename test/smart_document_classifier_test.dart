import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/smart_document_classifier.dart';

void main() {
  const classifier = SmartDocumentClassifier();

  test('recognizes CMR', () {
    final r = classifier.classify(
      'CMR International Consignment Note\nConsignor\nConsignee\nCarrier\nPlace of delivery',
    );
    expect(r.type, SmartDocumentType.cmr);
    expect(r.confidence, greaterThan(.7));
  });

  test('recognizes fuel receipt', () {
    final r = classifier.classify(
      'SHELL Tankstelle\nDiesel 42.30 L\nPrice/L 1.679 EUR\nTOTAL 71.02 EUR',
    );
    expect(r.type, SmartDocumentType.fuelReceipt);
  });

  test('recognizes toll receipt', () {
    final r = classifier.classify(
      'ASFINAG E-VIGNETTE\nAutobahn Maut\nValid until 2026-10-01',
    );
    expect(r.type, SmartDocumentType.tollReceipt);
  });

  test('recognizes parking receipt', () {
    final r = classifier.classify(
      'PARKHAUS\nParking ticket\nAmount 12.00 EUR',
    );
    expect(r.type, SmartDocumentType.parkingReceipt);
  });

  test('recognizes customs document', () {
    final r = classifier.classify(
      'CUSTOMS EXPORT ACCOMPANYING DOCUMENT\nMRN 26DE1234567890\nT1',
    );
    expect(r.type, SmartDocumentType.customs);
  });

  test('recognizes pallet exchange document', () {
    final r = classifier.classify(
      'Palettenschein\nPalettentausch\n20 Europalette',
    );
    expect(r.type, SmartDocumentType.palletExchange);
  });

  test('asks for confirmation on weak text', () {
    final r = classifier.classify('ABC Logistics 2026 09 21');
    expect(r.needsConfirmation, isTrue);
  });
}
