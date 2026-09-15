import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/main.dart';

void main() {
  testWidgets('AIMS Flow home screen renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pumpAndSettle();

    expect(find.text('AIMS Flow Scanner'), findsOneWidget);
    expect(find.text('CMR Scanner'), findsOneWidget);
    expect(find.text('Scanner megnyitása'), findsOneWidget);
  });
}
