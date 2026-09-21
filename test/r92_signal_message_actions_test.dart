import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aims_driver_plate': 'SIP-115',
      'aims_driver_name': 'Teszt Sofőr',
      'aims_user_role': 'driver',
    });
  });

  testWidgets('quick signal buttons execute and provide feedback', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriverShellScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pump(const Duration(milliseconds: 250));

    for (final label in <String>[
      'Késés',
      'Várakozás',
      'Cím / rakodás',
      'Műszaki hiba',
      'Sürgős',
      'Egyéb',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Késés').first);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('office message send is actionable and never silently dead', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriverShellScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pump(const Duration(milliseconds: 250));

    final input = find.byKey(const Key('flow-office-message-input'));
    final send = find.byKey(const Key('flow-office-message-send'));

    await tester.dragUntilVisible(
      input,
      find.byType(ListView).at(2),
      const Offset(0, -260),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(input, findsOneWidget);
    expect(send, findsOneWidget);

    await tester.enterText(input, 'Teszt üzenet a főnökségnek');
    await tester.tap(send);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('missing driver plate forces login instead of dead controls', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aims_user_role': 'driver',
    });

    await tester.pumpWidget(const MaterialApp(home: DriverShellScreen()));
    await tester.pumpAndSettle(const Duration(milliseconds: 900));

    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
  });
}
