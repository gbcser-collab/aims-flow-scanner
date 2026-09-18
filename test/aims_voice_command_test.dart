import 'package:aims_flow_scanner/services/aims_voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AimsVoiceCommandParser();

  test('understands the 10 core Hungarian Flow voice commands', () {
    final cases = <String, AimsVoiceIntent>{
      'Mutasd a fuvarom': AimsVoiceIntent.showJob,
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
}
