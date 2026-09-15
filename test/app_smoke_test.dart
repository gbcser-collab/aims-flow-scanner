import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/main.dart';

void main() {
  testWidgets('AIMS Flow Smart Scanner v0.7 home renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pumpAndSettle();

    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('AIMS FLOW • SMART • v0.7'), findsOneWidget);
    expect(find.text('CMR Scanner'), findsOneWidget);
    expect(find.text('Smart Scan indítása'), findsOneWidget);
    expect(find.text('Legutóbbi mentések'), findsOneWidget);
  });
}
