import 'package:aims_flow_scanner/main.dart';
import 'package:aims_flow_scanner/screens/driver_shell_screen.dart';
import 'package:aims_flow_scanner/services/aims_display_mode.dart';
import 'package:aims_flow_scanner/widgets/aims_flow_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aims_display_mode_v1': 'light',
    });
    await AimsDisplayModeController.instance.setMode(AimsDisplayMode.light);
  });

  testWidgets('FLOW supports a readable light theme and neutral dark theme',
      (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump();

    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(app.theme?.brightness, Brightness.light);
    expect(app.theme?.scaffoldBackgroundColor, const Color(0xFFF4F6F8));
    expect(app.theme?.colorScheme.onSurface, const Color(0xFF17212A));

    await AimsDisplayModeController.instance.setMode(AimsDisplayMode.dark);
    await tester.pump();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.brightness, Brightness.dark);
    expect(app.darkTheme?.scaffoldBackgroundColor, const Color(0xFF111315));
    expect(app.darkTheme?.colorScheme.onSurface, Colors.white);
  });

  testWidgets('AIMS Flow starts on FLOW ID and PIN login', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('SOFŐR BELÉPÉS'), findsOneWidget);
    expect(find.byKey(const Key('flow-login-flow-id')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-pin')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
    expect(find.text('6 jegyű FLOW ID'), findsOneWidget);
    expect(find.text('5 jegyű PIN'), findsOneWidget);
    expect(find.textContaining('az iroda küldi e-mailben'), findsOneWidget);
    expect(find.text('IRODAI AIMS FLOW ADMIN'), findsOneWidget);

    expect(find.byKey(const Key('flow-login-user')), findsNothing);
    expect(find.byKey(const Key('flow-login-password')), findsNothing);
    expect(find.byKey(const Key('flow-admin-toggle')), findsNothing);
  });

  testWidgets('FLOW ID and PIN fields accept digits only', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    final flowId = find.byKey(const Key('flow-login-flow-id'));
    final pin = find.byKey(const Key('flow-login-pin'));

    await tester.enterText(flowId, '12AB3456');
    await tester.enterText(pin, '1X2345');
    await tester.pump();

    expect(tester.widget<TextField>(flowId).controller?.text, '123456');
    expect(tester.widget<TextField>(pin).controller?.text, '12345');
  });

  testWidgets('display mode can be changed from the login screen',
      (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('VILÁGOS'), findsOneWidget);
    await tester.tap(find.text('VILÁGOS'));
    await tester.pump();
    expect(find.text('SÖTÉT'), findsOneWidget);
  });

  testWidgets('login has no overflow on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
  });

  testWidgets('driver shell keeps developed core actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverShellScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AimsFlowLogo), findsOneWidget);
    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.byKey(const Key('flow-next-jobs')), findsOneWidget);
    expect(find.byKey(const Key('aims-assistant-talk')), findsNothing);
    expect(find.text('Kezdő'), findsOneWidget);
    expect(find.text('Fuvar'), findsOneWidget);
    expect(find.text('Jelzés'), findsOneWidget);
    expect(find.text('Doksi'), findsOneWidget);
  });

  testWidgets('driver shell has no overflow on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: DriverShellScreen()),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(AimsFlowLogo), findsOneWidget);
    expect(find.byKey(const Key('flow-next-jobs')), findsOneWidget);
    expect(find.byKey(const Key('aims-assistant-talk')), findsNothing);
  });
}
