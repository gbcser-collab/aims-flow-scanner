import 'package:flutter_test/flutter_test.dart';
import 'package:nailfit/main.dart';

void main() {
  testWidgets('NAILFIT v0.8 premium home renders', (tester) async {
    await tester.pumpWidget(const NailFitApp());
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('NAIL'), findsOneWidget);
    expect(find.text('FIT'), findsOneWidget);
    expect(find.text('a hozzád illő\nkörmöket.'), findsOneWidget);
    expect(find.text('Készíts fotót'), findsOneWidget);
  });
}
