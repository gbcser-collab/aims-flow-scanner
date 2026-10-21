import 'package:aims_flow_scanner/services/flow_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Rendering fixture only. Authentication is tested separately through mocked HTTP;
// production code has no test-login switch or locally trusted profile fallback.
void installDriverFixture() {
  final session = FlowAuthSession(
    refreshToken: 'b' * 64,
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    subjectId: 'test-driver',
    tenantId: 'test-tenant',
    flowId: '004271',
    assignmentId: 'test-assignment',
    plate: 'SIP115',
    displayName: 'Teszt Sofőr',
    language: 'hu',
    deviceId: 'd' * 64,
  );
  FlowAuthService.instance.session = session;
  SharedPreferences.setMockInitialValues({
    'aims_hands_free': false,
    'flow_v2_${session.scope}_aims_driver_last_odometer_km': 100000,
  });
}
