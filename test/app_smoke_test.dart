import 'package:aims_flow_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow driver home exposes core actions', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AIMS FLOW'), findsWidgets);
    expect(find.text('DRIVER MODE'), findsOneWidget);
    expect(find.text('GPS'), findsWidgets);
    expect(find.textContaining('Új fuvarnál hangos push érkezik'), findsOneWidget);

    await tester.tap(find.text('GYORS JELZÉS'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Gyors jelzés'), findsOneWidget);
    expect(find.text('Várakozás'), findsOneWidget);
    expect(find.text('Műszaki hiba'), findsOneWidget);
  });
}
