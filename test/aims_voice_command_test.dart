import 'package:aims_flow_scanner/services/aims_voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AimsVoiceCommandParser();

  test('understands the 10 core Hungarian Flow voice commands', () {
    final cases = <String, AimsVoiceIntent>{
      'Mutasd a fuvarom': AimsVoiceIntent.showJob,
      'Mi a következő feladat?': AimsVoiceIntent.showNextJobs,
      'Navigálj a felrakóra': AimsVoiceIntent.navigatePickup,
      'Navigálj a lerakóra': AimsVoiceIntent.navigateDelivery,
      'Megérkeztem a felrakóra': AimsVoiceIntent.arrivePickup,
      'Megérkeztem a lerakóra': AimsVoiceIntent.arriveDelivery,
      'Felrakás kész': AimsVoiceIntent.pickupComplete,
      'Lerakás kész': AimsVoiceIntent.deliveryComplete,
      'Mutasd a következő címet': AimsVoiceIntent.nextAddress,
      'Hívd a kapcsolattartót': AimsVoiceIntent.callContact,
      'Küldj gyors jelzést: késés': AimsVoiceIntent.delaySignal,
    };

    for (final entry in cases.entries) {
      expect(
        parser.parse(entry.key).intent,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('understands useful extra commands', () {
    expect(
      parser.parse('Tankolási bizonylat').intent,
      AimsVoiceIntent.fuelReceipt,
    );
    expect(
      parser.parse('CMR fotó').intent,
      AimsVoiceIntent.cmrDocument,
    );
    expect(
      parser.parse('Műszaki hiba').intent,
      AimsVoiceIntent.technicalIssue,
    );
    expect(
      parser.parse('Olvasd fel a fuvar részleteit').intent,
      AimsVoiceIntent.readJobDetails,
    );
  });

  test('is accent tolerant', () {
    expect(
      parser.parse('navigalj a lerakora').intent,
      AimsVoiceIntent.navigateDelivery,
    );
    expect(
      parser.parse('felrakas kesz').intent,
      AimsVoiceIntent.pickupComplete,
    );
  });

  test('adds confidence and confirmation to consequential commands', () {
    final command = parser.parse('Lerakás kész');
    expect(command.intent, AimsVoiceIntent.deliveryComplete);
    expect(command.confidence, greaterThan(.9));
    expect(command.risk, AimsVoiceRisk.consequential);
    expect(command.requiresConfirmation, isTrue);
  });

  test('does not execute explicitly negated commands', () {
    final command = parser.parse('Nem lerakás kész');
    expect(command.intent, AimsVoiceIntent.unknown);
    expect(command.confidence, lessThan(.5));
  });

  test('understands repeat last announcement command', () {
    final command = parser.parse('Mondd újra');
    expect(command.intent, AimsVoiceIntent.repeatLast);
    expect(command.requiresConfirmation, isFalse);
  });

  test('explicit emergency send can bypass confirmation', () {
    final command = parser.parse('Küldj sürgős jelzést');
    expect(command.intent, AimsVoiceIntent.urgentSignal);
    expect(command.risk, AimsVoiceRisk.emergency);
    expect(command.requiresConfirmation, isFalse);
  });

}
