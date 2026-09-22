import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'aims_user_role': 'driver',
      'aims_driver_plate': 'SIP-115',
      'aims_driver_name': 'Teszt Sofőr',
      'aims_hands_free': false,
    });
  });

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

      Future<void> expectSignalSheet({
        required String tile,
        required String title,
        required List<String> options,
      }) async {
        final tileFinder = find.text(tile);
        expect(tileFinder, findsOneWidget);
        await tester.ensureVisible(tileFinder);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(tileFinder);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(title), findsOneWidget);
        for (final option in options) {
          expect(find.text(option), findsOneWidget);
        }

        Navigator.of(tester.element(find.text(title))).pop();
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
        expect(find.byType(DriverShellScreen), findsOneWidget);
      }

      await expectSignalSheet(
        tile: 'Késés',
        title: 'KÉSÉS OKA',
        options: ['FORGALOM', 'CSÚSZÁS'],
      );
      await expectSignalSheet(
        tile: 'Várakozás',
        title: 'MIÉRT VÁRSZ?',
        options: ['RAKODÁSRA VÁROK', 'TELEPHELYEN VÁROK'],
      );
      await expectSignalSheet(
        tile: 'Cím / rakodás',
        title: 'MI A PROBLÉMA?',
        options: ['NEM TALÁLHATÓ', 'NEM ENGEDNEK BE'],
      );
      await expectSignalSheet(
        tile: 'Műszaki hiba',
        title: 'MI HIBÁSODOTT MEG?',
        options: ['AUTÓ', 'GUMI', 'MOTOR'],
      );
      await expectSignalSheet(
        tile: 'Sürgős',
        title: 'SOS / SÜRGŐS',
        options: ['SOS – AZONNALI SEGÍTSÉG', 'BALESET'],
      );

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
    'R93 shell accepts login identity directly without redirecting',
    (tester) async {
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

      // The stability contract is that a valid identity supplied by login
      // keeps the shell mounted and does not tear down the widget tree.
      expect(tester.takeException(), isNull);
      expect(find.byType(DriverShellScreen), findsOneWidget);
      // NavigationBar renders the selected destination with selectedIcon.
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    },
  );
}
