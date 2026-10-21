import 'package:aims_flow_scanner/main.dart';
import 'package:aims_flow_scanner/services/aims_display_mode.dart';
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

  testWidgets('AIMS Flow renders FLOW ID and PIN entry screen',
      (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('SOFŐR BELÉPÉS'), findsOneWidget);
    expect(find.byKey(const Key('flow-login-flow-id')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-pin')), findsOneWidget);
    expect(find.byKey(const Key('flow-login-submit')), findsOneWidget);
    expect(find.text('6 jegyű FLOW ID'), findsOneWidget);
    expect(find.text('5 jegyű PIN'), findsOneWidget);
    expect(find.textContaining('az iroda küldi e-mailben'), findsOneWidget);
  });
}
