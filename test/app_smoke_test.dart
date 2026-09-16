import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow Smart Scanner v1.0 home renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('AIMS FLOW • SMART • v1.0'), findsOneWidget);
    expect(find.text('CMR Scanner + GPS'), findsOneWidget);
    expect(find.byType(FlutterLogo), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Smart Scan indítása'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smart Scan indítása'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Legutóbbi mentések'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Legutóbbi mentések'), findsOneWidget);
  });
}
