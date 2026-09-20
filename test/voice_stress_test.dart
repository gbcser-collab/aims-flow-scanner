import 'package:aims_flow_scanner/services/aims_voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

String noisy(String base, int i) {
  return switch (i % 6) {
    0 => base,
    1 => base.toUpperCase(),
    2 => '  ' + base + '  ',
    3 => base + '!!!',
    4 => base.replaceAll(' ', '  '),
    _ => base + '?',
  };
}

void runLanguageStress(
  AimsVoiceCommandParser parser,
  String language,
  List<(String, AimsVoiceIntent)> cases,
) {
  for (var i = 0; i < 10000; i++) {
    final sample = cases[i % cases.length];
    final parsed = parser.parse(noisy(sample.$1, i), language: language);
    expect(parsed.intent, sample.$2, reason: language + ' variant ' + i.toString());
  }
}
void main() {
  const parser = AimsVoiceCommandParser();

  test('Hungarian voice parser handles 10000 variants', () {
    runLanguageStress(parser, 'hu', const [
      ('Mutasd a fuvarom', AimsVoiceIntent.showJob),
      ('Következő feladat', AimsVoiceIntent.showNextJobs),
      ('Navigálj a felrakóra', AimsVoiceIntent.navigatePickup),
      ('Navigálj a lerakóra', AimsVoiceIntent.navigateDelivery),
      ('Megérkeztem a felrakóra', AimsVoiceIntent.arrivePickup),
      ('Megérkeztem a lerakóra', AimsVoiceIntent.arriveDelivery),
      ('Felrakás kész', AimsVoiceIntent.pickupComplete),
      ('Lerakás kész', AimsVoiceIntent.deliveryComplete),
      ('Következő cím', AimsVoiceIntent.nextAddress),
      ('Hívd a kapcsolattartót', AimsVoiceIntent.callContact),
      ('Késés', AimsVoiceIntent.delaySignal),
      ('CMR fotó', AimsVoiceIntent.cmrDocument),
      ('Műszaki hiba', AimsVoiceIntent.technicalIssue),
      ('Várakozom', AimsVoiceIntent.waitingSignal),
      ('Sürgős', AimsVoiceIntent.urgentSignal),
    ]);
  });
  test('English voice parser handles 10000 variants', () {
    runLanguageStress(parser, 'en', const [
      ('show my job', AimsVoiceIntent.showJob),
      ('next task', AimsVoiceIntent.showNextJobs),
      ('navigate to pickup', AimsVoiceIntent.navigatePickup),
      ('navigate to delivery', AimsVoiceIntent.navigateDelivery),
      ('arrived at pickup', AimsVoiceIntent.arrivePickup),
      ('arrived at delivery', AimsVoiceIntent.arriveDelivery),
      ('pickup complete', AimsVoiceIntent.pickupComplete),
      ('delivery complete', AimsVoiceIntent.deliveryComplete),
      ('next address', AimsVoiceIntent.nextAddress),
      ('call the contact', AimsVoiceIntent.callContact),
      ('running late', AimsVoiceIntent.delaySignal),
      ('fuel receipt', AimsVoiceIntent.fuelReceipt),
      ('scan cmr', AimsVoiceIntent.cmrDocument),
      ('vehicle problem', AimsVoiceIntent.technicalIssue),
      ('waiting', AimsVoiceIntent.waitingSignal),
      ('emergency', AimsVoiceIntent.urgentSignal),
    ]);
  });
  test('German voice parser handles 10000 variants', () {
    runLanguageStress(parser, 'de', const [
      ('zeige meinen Auftrag', AimsVoiceIntent.showJob),
      ('nächste Aufgabe', AimsVoiceIntent.showNextJobs),
      ('navigiere zur Abholung', AimsVoiceIntent.navigatePickup),
      ('navigiere zur Zustellung', AimsVoiceIntent.navigateDelivery),
      ('angekommen an der Abholung', AimsVoiceIntent.arrivePickup),
      ('angekommen an der Zustellung', AimsVoiceIntent.arriveDelivery),
      ('Beladung fertig', AimsVoiceIntent.pickupComplete),
      ('Entladung fertig', AimsVoiceIntent.deliveryComplete),
      ('nächste Adresse', AimsVoiceIntent.nextAddress),
      ('Kontakt anrufen', AimsVoiceIntent.callContact),
      ('Verspätung', AimsVoiceIntent.delaySignal),
      ('Tankbeleg', AimsVoiceIntent.fuelReceipt),
      ('CMR scannen', AimsVoiceIntent.cmrDocument),
      ('Fahrzeugproblem', AimsVoiceIntent.technicalIssue),
      ('ich warte', AimsVoiceIntent.waitingSignal),
      ('Notfall', AimsVoiceIntent.urgentSignal),
    ]);
  });

  test('10000 unrelated phrases remain unknown', () {
    for (var i = 0; i < 10000; i++) {
      expect(
        parser.parse('random-no-command-' + i.toString(), language: 'en').intent,
        AimsVoiceIntent.unknown,
      );
    }
  });
}