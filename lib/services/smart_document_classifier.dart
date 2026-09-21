enum SmartDocumentType {
  cmr,
  pod,
  invoice,
  fuelReceipt,
  tollReceipt,
  parkingReceipt,
  customs,
  palletExchange,
  deliveryNote,
  other,
}

extension SmartDocumentTypeX on SmartDocumentType {
  String get wire => switch (this) {
        SmartDocumentType.cmr => 'cmr',
        SmartDocumentType.pod => 'pod',
        SmartDocumentType.invoice => 'invoice',
        SmartDocumentType.fuelReceipt => 'fuel_receipt',
        SmartDocumentType.tollReceipt => 'toll_receipt',
        SmartDocumentType.parkingReceipt => 'parking_receipt',
        SmartDocumentType.customs => 'customs',
        SmartDocumentType.palletExchange => 'pallet_exchange',
        SmartDocumentType.deliveryNote => 'delivery_note',
        SmartDocumentType.other => 'other',
      };

  String get hu => switch (this) {
        SmartDocumentType.cmr => 'CMR',
        SmartDocumentType.pod => 'POD / átvételi igazolás',
        SmartDocumentType.invoice => 'Számla',
        SmartDocumentType.fuelReceipt => 'Tankolási bizonylat',
        SmartDocumentType.tollReceipt => 'Útdíj / matrica',
        SmartDocumentType.parkingReceipt => 'Parkolási bizonylat',
        SmartDocumentType.customs => 'Vámokmány',
        SmartDocumentType.palletExchange => 'Raklapcsere-papír',
        SmartDocumentType.deliveryNote => 'Szállítólevél',
        SmartDocumentType.other => 'Egyéb dokumentum',
      };
}

class SmartDocumentClassification {
  const SmartDocumentClassification({
    required this.type,
    required this.confidence,
    required this.scores,
    required this.needsConfirmation,
  });

  final SmartDocumentType type;
  final double confidence;
  final Map<SmartDocumentType, int> scores;
  final bool needsConfirmation;
}

class SmartDocumentClassifier {
  const SmartDocumentClassifier();

  SmartDocumentClassification classify(
    String rawText, {
    String context = '',
  }) {
    final text = _normalize('$rawText\n$context');
    final scores = <SmartDocumentType, int>{
      for (final type in SmartDocumentType.values) type: 0,
    };

    void add(SmartDocumentType type, int points, List<String> signals) {
      for (final signal in signals) {
        if (text.contains(_normalize(signal))) {
          scores[type] = (scores[type] ?? 0) + points;
        }
      }
    }

    add(SmartDocumentType.cmr, 4, [
      'cmr',
      'lettre de voiture',
      'frachtbrief',
      'consignment note',
      'sender consignor',
      'consignee',
      'carrier',
      'place of delivery',
      'place of taking over',
    ]);
    add(SmartDocumentType.cmr, 2, [
      'feladó',
      'címzett',
      'fuvarozó',
      'átvétel helye',
      'kiszolgáltatás helye',
    ]);

    add(SmartDocumentType.pod, 4, [
      'proof of delivery',
      'pod',
      'received by',
      'goods received',
      'delivery confirmation',
      'empfangsbestätigung',
      'ablieferbeleg',
    ]);
    add(SmartDocumentType.pod, 2, [
      'átvette',
      'átvételi igazolás',
      'aláírás',
      'signature',
      'stamp',
      'pecsét',
    ]);

    add(SmartDocumentType.invoice, 4, [
      'invoice',
      'rechnung',
      'faktura',
      'faktúra',
      'számla',
      'vat',
      'áfa',
      'amount due',
      'grand total',
      'fizetendő',
    ]);

    add(SmartDocumentType.fuelReceipt, 5, [
      'diesel',
      'gasoil',
      'fuel',
      'benzin',
      'adblue',
      'liter',
      'litre',
      'tankstelle',
      'shell',
      'omv',
      'mol ',
      'orlen',
      'circle k',
    ]);

    add(SmartDocumentType.tollReceipt, 5, [
      'vignette',
      'e-vignette',
      'e-matrica',
      'toll',
      'maut',
      'autobahn',
      'e-toll',
      'e-myto',
      'asfinag',
      'dars',
      'winieta',
      'vignetta',
    ]);

    add(SmartDocumentType.parkingReceipt, 5, [
      'parking',
      'parkoló',
      'parkolás',
      'parkhaus',
      'parken',
      'parkomat',
    ]);

    add(SmartDocumentType.customs, 5, [
      'customs',
      'douane',
      'zoll',
      'vám',
      'mrn',
      't1',
      't2',
      'export accompanying document',
      'import declaration',
    ]);

    add(SmartDocumentType.palletExchange, 5, [
      'pallet exchange',
      'palettenschein',
      'palettentausch',
      'raklapcsere',
      'europallet',
      'euro pallet',
      'europalette',
    ]);

    add(SmartDocumentType.deliveryNote, 4, [
      'delivery note',
      'lieferschein',
      'szállítólevél',
      'bon de livraison',
      'packing list',
      'lieferschein nr',
    ]);

    // Context is intentionally low-weight: OCR/document content remains primary.
    final ctx = _normalize(context);
    if (ctx.contains('cmr')) scores[SmartDocumentType.cmr] = (scores[SmartDocumentType.cmr] ?? 0) + 2;
    if (ctx.contains('pod')) scores[SmartDocumentType.pod] = (scores[SmartDocumentType.pod] ?? 0) + 2;
    if (ctx.contains('custom')) scores[SmartDocumentType.customs] = (scores[SmartDocumentType.customs] ?? 0) + 2;
    if (ctx.contains('invoice') || ctx.contains('száml')) scores[SmartDocumentType.invoice] = (scores[SmartDocumentType.invoice] ?? 0) + 2;

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0;

    if (best.value <= 1) {
      return SmartDocumentClassification(
        type: SmartDocumentType.other,
        confidence: 0.35,
        scores: scores,
        needsConfirmation: true,
      );
    }

    final gap = best.value - second;
    final confidence = (0.48 + best.value * 0.055 + gap * 0.045)
        .clamp(0.48, 0.98)
        .toDouble();

    return SmartDocumentClassification(
      type: best.key,
      confidence: confidence,
      scores: scores,
      needsConfirmation: confidence < 0.76 || gap < 2,
    );
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ő', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ű', 'u')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
