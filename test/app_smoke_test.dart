import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/main.dart';

void main() {
  testWidgets('NAILFIT home screen renders and scrolls', (tester) async {
    await tester.pumpWidget(const NailFitApp());
    await tester.pumpAndSettle();

    expect(find.byType(NailFitHome), findsOneWidget);
    expect(find.text('NAIL'), findsOneWidget);
    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('Próbáld fel.\nMielőtt elkészül.'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Fotózás'), findsOneWidget);
    expect(find.text('Galéria'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -950));
    await tester.pumpAndSettle();
    expect(find.text('Nail Match'), findsOneWidget);
  });
}
