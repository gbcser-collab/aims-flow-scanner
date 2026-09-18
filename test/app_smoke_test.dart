import 'package:aims_flow_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow driver home exposes core actions', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AIMS FLOW'), findsWidgets);
    expect(find.text('DRIVER MODE'), findsOneWidget);
    expect(find.textContaining('Új fuvarnál hangos push érkezik'), findsOneWidget);
    expect(find.text('KEZDŐLAP'), findsOneWidget);
    expect(find.text('FUVAROM'), findsOneWidget);
    expect(find.text('GYORS JELZÉS'), findsOneWidget);
    expect(find.text('DOKSI'), findsOneWidget);
  });
}
