import 'package:aims_flow_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AIMS Flow Smart Scanner brutal home renders its primary controls', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('AIMS FLOW'), findsOneWidget);
    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('Gyorsabb folyamatok. Okosabb működés.'), findsOneWidget);
    expect(find.byType(FlutterLogo), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Smart Scan indítása'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smart Scan indítása'), findsOneWidget);

    expect(
      find.textContaining('GPS'),
      findsAtLeastNWidgets(1),
      reason: 'A home screen must expose the GPS workflow next to Smart Scan.',
    );

    await tester.scrollUntilVisible(
      find.text('Legutóbbi mentések'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Legutóbbi mentések'), findsOneWidget);
  });
}
