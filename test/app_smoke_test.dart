import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow unified login renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Belépés'), findsOneWidget);
    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('Felhasználó'), findsOneWidget);
    expect(find.text('Jelszó'), findsNWidgets(2));
    expect(find.text('2FA kód'), findsOneWidget);
    expect(find.text('Tovább'), findsOneWidget);
    expect(find.textContaining('Új eszköz'), findsOneWidget);
    expect(find.textContaining('Segítség'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(8));
  });
}
