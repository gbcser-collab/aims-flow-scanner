import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/main.dart';

void main() {
  testWidgets('NAILFIT home screen renders', (tester) async {
    await tester.pumpWidget(const NailFitApp());
    await tester.pumpAndSettle();

    expect(find.text('NAIL'), findsOneWidget);
    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('Próbáld fel.\nMielőtt elkészül.'), findsOneWidget);
    expect(find.text('Fotózás'), findsOneWidget);
    expect(find.text('Galéria'), findsOneWidget);
    expect(find.text('Nail Match'), findsOneWidget);
  });
}
