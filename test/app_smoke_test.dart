import 'package:flutter_test/flutter_test.dart';
import 'package:nailfit/main.dart';

void main() {
  testWidgets('NAILFIT home screen renders', (tester) async {
    await tester.pumpWidget(const NailFitApp());
    await tester.pumpAndSettle();

    expect(find.byType(NailFitHome), findsOneWidget);
    expect(find.text('NAIL'), findsOneWidget);
    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('Próbáld fel.\nMielőtt elkészül.'), findsOneWidget);
  });
}
