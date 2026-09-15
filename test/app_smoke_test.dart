import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailfit/main.dart';

void main() {
  testWidgets('NAILFIT v0.7 premium home renders', (tester) async {
    await tester.pumpWidget(const NailFitApp());
    await tester.pumpAndSettle();

    expect(find.byType(NailFitHome), findsOneWidget);
    expect(find.text('NAIL'), findsWidgets);
    expect(find.text('FIT'), findsWidgets);
    expect(find.text('a hozzád illő\nkörmöket.'), findsOneWidget);
    expect(find.text('Készíts fotót'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsWidgets);
  });
}
