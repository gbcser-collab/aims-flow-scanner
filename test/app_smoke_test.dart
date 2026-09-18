import 'package:aims_flow_scanner/main.dart';
import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow starts on web-account login', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('DRIVER OPERATIONS'), findsOneWidget);
    expect(find.text('Belépés'), findsOneWidget);
    expect(find.byKey(const Key('flow-login-user')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-password')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-2fa')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
    expect(find.textContaining('Nincs készülék-jóváhagyás'), findsOneWidget);
  });

  testWidgets('driver shell keeps developed core actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverShellScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AIMS FLOW'), findsWidgets);
    expect(find.text('DRIVER MODE'), findsOneWidget);
    expect(find.text('KEZDŐLAP'), findsOneWidget);
    expect(find.text('FUVAROM'), findsOneWidget);
    expect(find.text('GYORS JELZÉS'), findsOneWidget);
    expect(find.text('DOKSI'), findsOneWidget);
  });
}
