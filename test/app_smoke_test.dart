import 'package:aims_flow_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow production login renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Belépés'), findsOneWidget);
    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('Felhasználó'), findsOneWidget);
    expect(find.text('Jelszó'), findsOneWidget);
    expect(find.text('2FA kód'), findsOneWidget);
    expect(find.text('Tovább'), findsOneWidget);
    expect(find.text('Új eszköz\nhozzáadása'), findsOneWidget);
    expect(find.text('Segítség\nbelépéshez'), findsOneWidget);
  });
}
