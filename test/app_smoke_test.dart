import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailfit/main.dart';

Future<void> openAllTabs(WidgetTester tester) async {
  expect(find.text('NAIL'), findsOneWidget);
  expect(find.text('FIT'), findsOneWidget);
  expect(find.byKey(const ValueKey('hero-camera')), findsOneWidget);
  expect(tester.takeException(), isNull);

  await tester.tap(find.byKey(const ValueKey('nav-1')));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.text('Kéz szkennelése'), findsOneWidget);
  expect(tester.takeException(), isNull);

  await tester.tap(find.byKey(const ValueKey('nav-2')));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.text('Próbáld fel'), findsOneWidget);
  expect(tester.takeException(), isNull);

  await tester.tap(find.byKey(const ValueKey('nav-3')));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.textContaining('kedvenc stílus'), findsOneWidget);
  expect(tester.takeException(), isNull);

  await tester.tap(find.byKey(const ValueKey('nav-4')));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.text('Saját profil'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('NAILFIT functional shell renders all five tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const NailFitApp());
    await tester.pump(const Duration(milliseconds: 350));
    await openAllTabs(tester);
  });

  testWidgets('NAILFIT stays overflow-free on compact Android viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const NailFitApp());
    await tester.pump(const Duration(milliseconds: 350));
    await openAllTabs(tester);
  });
}
