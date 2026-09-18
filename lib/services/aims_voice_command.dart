enum AimsVoiceIntent {
  showJob,
  navigatePickup,
  navigateDelivery,
  arrivePickup,
  arriveDelivery,
  pickupComplete,
  deliveryComplete,
  nextAddress,
  callContact,
  delaySignal,
  fuelReceipt,
  cmrDocument,
  technicalIssue,
  readJobDetails,
  waitingSignal,
  urgentSignal,
  unknown,
}

class AimsVoiceCommand {
  const AimsVoiceCommand({
    required this.intent,
    required this.rawText,
  });

  final AimsVoiceIntent intent;
  final String rawText;
}

class AimsVoiceCommandParser {
  const AimsVoiceCommandParser();

  static String normalize(String input) {
    var s = input.toLowerCase().trim();
    const from = 'áéíóöőúüű';
    const to = 'aeiooouuu';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s
        .replaceAll('.', ' ')
        .replaceAll(',', ' ')
        .replaceAll('!', ' ')
        .replaceAll('?', ' ')
        .replaceAll('-', ' ');
    while (s.contains('  ')) {
      s = s.replaceAll('  ', ' ');
    }
    return s.trim();
  }

  AimsVoiceCommand parse(String rawText) {
    final s = normalize(rawText);

    bool has(String value) => s.contains(value);
    bool any(List<String> values) => values.any(has);

    if (any(['mutasd a fuvarom', 'mutasd a fuvart', 'fuvarom'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showJob, rawText: rawText);
    }

    if (any(['navigalj', 'navigacio', 'navi', 'utvonal']) && has('felrako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigatePickup, rawText: rawText);
    }

    if (any(['navigalj', 'navigacio', 'navi', 'utvonal']) && has('lerako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateDelivery, rawText: rawText);
    }

    if (any(['megerkeztem', 'megerkeztunk', 'itt vagyok']) && has('felrako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arrivePickup, rawText: rawText);
    }

    if (any(['megerkeztem', 'megerkeztunk', 'itt vagyok']) && has('lerako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arriveDelivery, rawText: rawText);
    }

    if (any(['felrakas kesz', 'felrako kesz', 'felrakodtunk', 'felrakva'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.pickupComplete, rawText: rawText);
    }

    if (any(['lerakas kesz', 'lerako kesz', 'lerakodtunk', 'lerakva'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.deliveryComplete, rawText: rawText);
    }

    if (any(['kovetkezo cim', 'kovetkezo megallo', 'mi a kovetkezo cim'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.nextAddress, rawText: rawText);
    }

    if (any(['hivd a kapcsolattartot', 'kapcsolattarto hivasa', 'telefonalj a kapcsolattartonak'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.callContact, rawText: rawText);
    }

    if (has('keses') || has('kesek')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.delaySignal, rawText: rawText);
    }

    if (any(['tankolasi bizonylat', 'tankolas bizonylat', 'uzemanyag bizonylat'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.fuelReceipt, rawText: rawText);
    }

    if (any(['cmr foto', 'cmr dokumentum', 'cmr scanner', 'dokumentum foto'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.cmrDocument, rawText: rawText);
    }

    if (any(['muszaki hiba', 'auto hiba', 'jarmu hiba'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.technicalIssue, rawText: rawText);
    }

    if (any(['olvasd fel a fuvar', 'fuvar reszletei', 'olvasd a fuvar reszleteit'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.readJobDetails, rawText: rawText);
    }

    if (any(['varakozas', 'varakozom', 'varunk'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.waitingSignal, rawText: rawText);
    }

    if (any(['surgos', 'baleset', 'azonnali segitseg'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.urgentSignal, rawText: rawText);
    }

    return AimsVoiceCommand(intent: AimsVoiceIntent.unknown, rawText: rawText);
  }
}
