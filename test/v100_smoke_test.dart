import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow driver shell renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('AIMS FLOW'), findsWidgets);
    expect(find.text('DRIVER MODE'), findsOneWidget);
    expect(find.text('KEZDŐLAP'), findsOneWidget);
    expect(find.text('FUVAROM'), findsOneWidget);
    expect(find.text('GYORS JELZÉS'), findsOneWidget);
    expect(find.text('DOKSI'), findsOneWidget);
  });
}
