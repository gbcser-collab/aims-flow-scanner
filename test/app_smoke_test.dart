import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/main.dart';

void main() {
  testWidgets('AIMS Flow Smart Scanner home renders', (tester) async {
    await tester.pumpWidget(const AimsFlowApp());
    await tester.pumpAndSettle();

    expect(find.text('AIMS Flow Smart Scanner'), findsOneWidget);
    expect(find.text('CMR Scanner'), findsOneWidget);
    expect(find.text('Smart Scan indítása'), findsOneWidget);
  });
}
