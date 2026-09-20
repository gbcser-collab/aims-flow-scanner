enum AimsVoiceIntent {
  showJob,
  showNextJobs,
  navigateNext,
  assistantHelp,
  trackingStatus,
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
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ö': 'o',
      'ő': 'o',
      'ú': 'u',
      'ü': 'u',
      'ű': 'u',
      'ä': 'a',
      'ß': 'ss',
    };
    for (final entry in replacements.entries) {
      s = s.replaceAll(entry.key, entry.value);
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

  AimsVoiceCommand parse(String rawText, {String language = 'hu'}) {
    final s = normalize(rawText);
    return switch (language) {
      'en' => _parseEn(rawText, s),
      'de' => _parseDe(rawText, s),
      _ => _parseHu(rawText, s),
    };
  }

  AimsVoiceCommand _parseHu(String raw, String s) {
    bool has(String value) => s.contains(value);
    bool any(List<String> values) => values.any(has);

    if (any(['mit tudsz', 'segits', 'segitseg', 'parancsok', 'miben tudsz segiteni'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.assistantHelp, rawText: raw);
    }
    if (any(['gps allapot', 'megy a gps', 'mukodik a gps', 'kovetes allapot', 'megy a kovetes'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.trackingStatus, rawText: raw);
    }
    if (any(['kovetkezo feladat', 'kovetkezo munka', 'kovetkezo fuvar', 'mi a kovetkezo feladat'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showNextJobs, rawText: raw);
    }
    if (any(['mutasd a fuvarom', 'mutasd a fuvart', 'fuvarom', 'aktualis fuvar', 'mostani fuvar', 'hol tartunk', 'mi a helyzet', 'mi a feladatom'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showJob, rawText: raw);
    }
    if (any(['navigalj', 'navigacio', 'navi', 'utvonal']) && has('felrako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigatePickup, rawText: raw);
    }
    if (any(['navigalj', 'navigacio', 'navi', 'utvonal']) && has('lerako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateDelivery, rawText: raw);
    }
    if (any([
      'inditsd a navigaciot',
      'indulhat a navigacio',
      'navigalj',
      'vigyel a kovetkezo cimre',
      'utvonal a kovetkezo cimre'
    ])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateNext, rawText: raw);
    }
    if (any(['megerkeztem', 'megerkeztunk', 'itt vagyok']) && has('felrako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arrivePickup, rawText: raw);
    }
    if (any(['megerkeztem', 'megerkeztunk', 'itt vagyok']) && has('lerako')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arriveDelivery, rawText: raw);
    }
    if (any(['felrakas kesz', 'felrako kesz', 'felrakodtunk', 'felrakva'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.pickupComplete, rawText: raw);
    }
    if (any(['lerakas kesz', 'lerako kesz', 'lerakodtunk', 'lerakva'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.deliveryComplete, rawText: raw);
    }
    if (any(['kovetkezo cim', 'kovetkezo megallo', 'mi a kovetkezo cim', 'hova menjek', 'mi a kovetkezo'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.nextAddress, rawText: raw);
    }
    if (any(['hivd a kapcsolattartot', 'kapcsolattarto hivasa', 'telefonalj a kapcsolattartonak'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.callContact, rawText: raw);
    }
    if (has('keses') || has('kesek')) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.delaySignal, rawText: raw);
    }
    if (any(['tankolasi bizonylat', 'tankolas bizonylat', 'uzemanyag bizonylat'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.fuelReceipt, rawText: raw);
    }
    if (any(['cmr foto', 'cmr dokumentum', 'cmr scanner', 'dokumentum foto'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.cmrDocument, rawText: raw);
    }
    if (any(['muszaki hiba', 'auto hiba', 'jarmu hiba'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.technicalIssue, rawText: raw);
    }
    if (any(['olvasd fel a fuvar', 'fuvar reszletei', 'olvasd a fuvar reszleteit'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.readJobDetails, rawText: raw);
    }
    if (any(['varakozas', 'varakozom', 'varunk'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.waitingSignal, rawText: raw);
    }
    if (any(['surgos', 'baleset', 'azonnali segitseg'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.urgentSignal, rawText: raw);
    }
    return AimsVoiceCommand(intent: AimsVoiceIntent.unknown, rawText: raw);
  }

  AimsVoiceCommand _parseEn(String raw, String s) {
    bool has(String value) => s.contains(value);
    bool any(List<String> values) => values.any(has);

    if (any(['what can you do', 'help me', 'commands', 'voice commands'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.assistantHelp, rawText: raw);
    }
    if (any(['gps status', 'is gps working', 'tracking status'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.trackingStatus, rawText: raw);
    }
    if (any(['next task', 'next job', 'next assigned job', 'what is my next job'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showNextJobs, rawText: raw);
    }
    if (any(['show my job', 'show the job', 'my job', 'job details', 'current job'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showJob, rawText: raw);
    }
    if (any(['navigate', 'navigation', 'route', 'directions']) &&
        any(['pickup', 'loading'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigatePickup, rawText: raw);
    }
    if (any(['navigate', 'navigation', 'route', 'directions']) &&
        any(['delivery', 'unloading'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateDelivery, rawText: raw);
    }
    if (any(['start navigation', 'navigate next', 'next destination', 'take me to the next stop'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateNext, rawText: raw);
    }
    if (any(['arrived', 'i am here', "i'm here"]) && any(['pickup', 'loading'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arrivePickup, rawText: raw);
    }
    if (any(['arrived', 'i am here', "i'm here"]) && any(['delivery', 'unloading'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arriveDelivery, rawText: raw);
    }
    if (any(['pickup complete', 'loading complete', 'loaded', 'pickup done'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.pickupComplete, rawText: raw);
    }
    if (any(['delivery complete', 'unloading complete', 'unloaded', 'delivery done'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.deliveryComplete, rawText: raw);
    }
    if (any(['next address', 'next stop', 'what is the next address'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.nextAddress, rawText: raw);
    }
    if (any(['call the contact', 'call contact', 'call contact person'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.callContact, rawText: raw);
    }
    if (any(['delay', 'running late', 'i am late'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.delaySignal, rawText: raw);
    }
    if (any(['fuel receipt', 'refuel receipt', 'fuel document'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.fuelReceipt, rawText: raw);
    }
    if (any(['cmr photo', 'cmr document', 'scan cmr'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.cmrDocument, rawText: raw);
    }
    if (any(['technical issue', 'vehicle issue', 'vehicle problem', 'breakdown'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.technicalIssue, rawText: raw);
    }
    if (any(['read job details', 'read the job', 'job details'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.readJobDetails, rawText: raw);
    }
    if (any(['waiting', 'i am waiting', 'we are waiting'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.waitingSignal, rawText: raw);
    }
    if (any(['urgent', 'emergency', 'accident', 'need help'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.urgentSignal, rawText: raw);
    }
    return AimsVoiceCommand(intent: AimsVoiceIntent.unknown, rawText: raw);
  }

  AimsVoiceCommand _parseDe(String raw, String s) {
    bool has(String value) => s.contains(value);
    bool any(List<String> values) => values.any(has);

    if (any(['was kannst du', 'hilfe', 'befehle', 'sprachbefehle'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.assistantHelp, rawText: raw);
    }
    if (any(['gps status', 'funktioniert gps', 'tracking status'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.trackingStatus, rawText: raw);
    }
    if (any(['nachste aufgabe', 'nachster auftrag', 'nachster job', 'was ist der nachste auftrag'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showNextJobs, rawText: raw);
    }
    if (any(['zeige meinen auftrag', 'auftrag anzeigen', 'mein auftrag', 'auftragsdetails', 'aktueller auftrag'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.showJob, rawText: raw);
    }
    if (any(['navigiere', 'navigation', 'route']) &&
        any(['abholung', 'ladestelle', 'beladung'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigatePickup, rawText: raw);
    }
    if (any(['navigiere', 'navigation', 'route']) &&
        any(['zustellung', 'entladestelle', 'entladung'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateDelivery, rawText: raw);
    }
    if (any(['navigation starten', 'zum nachsten stopp', 'nachste adresse navigieren'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.navigateNext, rawText: raw);
    }
    if (any(['angekommen', 'ich bin da']) && any(['abholung', 'ladestelle', 'beladung'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arrivePickup, rawText: raw);
    }
    if (any(['angekommen', 'ich bin da']) && any(['zustellung', 'entladestelle', 'entladung'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.arriveDelivery, rawText: raw);
    }
    if (any(['beladung fertig', 'abholung fertig', 'geladen'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.pickupComplete, rawText: raw);
    }
    if (any(['entladung fertig', 'zustellung fertig', 'entladen'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.deliveryComplete, rawText: raw);
    }
    if (any(['nachste adresse', 'nachster stopp', 'nachste station'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.nextAddress, rawText: raw);
    }
    if (any(['kontakt anrufen', 'ansprechpartner anrufen'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.callContact, rawText: raw);
    }
    if (any(['verspatung', 'ich verspate mich', 'zu spat'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.delaySignal, rawText: raw);
    }
    if (any(['tankbeleg', 'tankquittung', 'kraftstoffbeleg'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.fuelReceipt, rawText: raw);
    }
    if (any(['cmr foto', 'cmr dokument', 'cmr scannen'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.cmrDocument, rawText: raw);
    }
    if (any(['technischer fehler', 'fahrzeugproblem', 'panne'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.technicalIssue, rawText: raw);
    }
    if (any(['auftragsdetails vorlesen', 'auftrag vorlesen'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.readJobDetails, rawText: raw);
    }
    if (any(['warten', 'ich warte', 'wir warten'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.waitingSignal, rawText: raw);
    }
    if (any(['dringend', 'notfall', 'unfall', 'hilfe'])) {
      return AimsVoiceCommand(intent: AimsVoiceIntent.urgentSignal, rawText: raw);
    }
    return AimsVoiceCommand(intent: AimsVoiceIntent.unknown, rawText: raw);
  }
}