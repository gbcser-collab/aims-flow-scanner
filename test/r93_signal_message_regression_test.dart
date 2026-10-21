import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aims_flow_scanner/services/flow_auth_service.dart';
import 'package:aims_flow_scanner/screens/flow_login_screen.dart';
import 'support/driver_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installDriverFixture);
  tearDown(() => FlowAuthService.instance.session = null);

  testWidgets(
    'R93 quick signal and office message do not crash the widget tree',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverShellScreen(
            initialPlate: 'SIP-115',
            initialDriverName: 'Teszt Sofőr',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(DriverShellScreen), findsOneWidget);

      // Select the actual navigation destination instead of tapping its label.
      // This keeps the regression test independent from translated label text
      // and verifies the same callback path used on a real phone.
      final signalDestination = find.byIcon(Icons.campaign_outlined);
      expect(signalDestination, findsOneWidget);
      await tester.tap(signalDestination);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Gyors jelzés'), findsOneWidget);
      expect(find.text('Késés'), findsOneWidget);

      await tester.tap(find.text('Késés'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // The office message panel sits below the quick-signal grid in a
      // lazily-built ListView, so scroll it into the viewport before finding
      // its controls. This tests the real screen instead of assuming all
      // off-screen list children are already mounted.
      await tester.scrollUntilVisible(
        find.byKey(const Key('flow-office-message-input')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('flow-office-message-input')), findsOneWidget);
      expect(find.byKey(const Key('flow-office-message-send')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('flow-office-message-input')),
        'R93 üzenetküldés regresszióteszt',
      );
      await tester.tap(find.byKey(const Key('flow-office-message-send')));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.byType(DriverShellScreen), findsOneWidget);
    },
  );

  testWidgets(
    'R105 shell rejects constructor identity and legacy local profile without a session',
    (tester) async {
      FlowAuthService.instance.session = null;
      SharedPreferences.setMockInitialValues({
        'aims_user_role': 'driver',
        'aims_driver_name': 'Teszt Sofőr',
        'aims_hands_free': false,
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DriverShellScreen(
            initialPlate: 'SIP-115',
            initialDriverName: 'Teszt Sofőr',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(DriverShellScreen), findsNothing);
      expect(find.byType(FlowLoginScreen), findsOneWidget);
    },
  );
}
