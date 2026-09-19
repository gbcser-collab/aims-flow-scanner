import 'package:aims_flow_scanner/main.dart';
import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:aims_flow_scanner/widgets/aims_flow_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow starts on plate and short-code login', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('DRIVER OPERATIONS'), findsOneWidget);
    expect(find.text('Belépés'), findsOneWidget);
    expect(find.byKey(const Key('flow-login-user')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-password')), findsOneWidget);
    expect(find.byKey(const Key('flow-admin-toggle')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-2fa')), findsNothing);
    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
    expect(find.byKey(const Key('flow-register-open')), findsOneWidget);
    expect(
      find.textContaining('Sofőr belépés rendszámmal és 6 karakteres kóddal'),
      findsOneWidget,
    );
    expect(find.textContaining('3 betű és 3 szám'), findsOneWidget);
    expect(find.byKey(const Key('flow-forgot-code-open')), findsOneWidget);
  });

  testWidgets('admin mode reveals 2FA only when requested', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('flow-admin-toggle')));
    await tester.tap(find.byKey(const Key('flow-admin-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('flow-login-2fa')), findsOneWidget);
  });

  testWidgets('native registration opens from login', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('flow-register-open')));
    await tester.tap(find.byKey(const Key('flow-register-open')));
    await tester.pumpAndSettle();

    expect(find.text('REGISZTRÁCIÓ'), findsOneWidget);
    expect(find.byKey(const Key('flow-register-company')), findsOneWidget);
    expect(find.byKey(const Key('flow-register-plate')), findsOneWidget);
    expect(find.byKey(const Key('flow-register-country')), findsOneWidget);
    expect(find.byKey(const Key('flow-country-globe')), findsOneWidget);
    expect(find.byKey(const Key('flow-register-email')), findsOneWidget);
  });

  testWidgets('country search starts empty and shows at most five matches',
      (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('flow-register-open')));
    await tester.tap(find.byKey(const Key('flow-register-open')));
    await tester.pumpAndSettle();

    final countryFinder = find.byKey(const Key('flow-register-country'));
    final countryField = tester.widget<TextField>(countryFinder);
    expect(countryField.controller?.text ?? '', isEmpty);

    await tester.enterText(countryFinder, 'ma');
    await tester.pump();

    final suggestions = find.byKey(const Key('flow-country-suggestions'));
    expect(suggestions, findsOneWidget);
    expect(
      find.descendant(of: suggestions, matching: find.byType(ListTile)).evaluate().length,
      lessThanOrEqualTo(5),
    );
    expect(find.text('Magyarország'), findsOneWidget);
    expect(find.textContaining('Adószám'), findsNothing);
  });

  testWidgets('driver shell keeps developed core actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverShellScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AimsFlowLogo), findsOneWidget);
    expect(find.text('DRIVER MODE'), findsOneWidget);
    expect(find.text('KEZDŐLAP'), findsOneWidget);
    expect(find.text('FUVAROM'), findsOneWidget);
    expect(find.text('GYORS JELZÉS'), findsOneWidget);
    expect(find.text('DOKSI'), findsOneWidget);
  });
}
