import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow renders secure entry screen', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('DRIVER OPERATIONS'), findsOneWidget);
    expect(find.text('Belépés'), findsOneWidget);
    expect(find.textContaining('Nincs készülék-jóváhagyás'), findsOneWidget);
  });
}
