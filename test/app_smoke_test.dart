import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow Smart Scanner private CMR home renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('AIMS FLOW • SMART • PRIVATE CMR'), findsOneWidget);
    expect(find.text('CMR Scanner'), findsOneWidget);
    expect(find.text('Smart Scan PRO indítása'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('CMR-ek az appban'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CMR-ek az appban'), findsOneWidget);
  });
}
