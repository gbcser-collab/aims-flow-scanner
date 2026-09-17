import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow operations shell renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('FUVAR'), findsWidgets);
    expect(find.text('SCANNER'), findsWidgets);
    expect(find.text('FLOW'), findsWidgets);
    expect(find.text('AIMS FLOW'), findsWidgets);
    expect(find.text('DRIVER OPERATIONS'), findsOneWidget);
  });
}
