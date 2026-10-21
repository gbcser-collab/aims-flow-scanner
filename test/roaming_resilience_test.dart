import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/roaming_resilience.dart';

void main() {
  test('network retry recovers quickly and stays bounded', () {
    expect(RoamingResilience.retryDelay(0), Duration.zero);
    expect(RoamingResilience.retryDelay(1), const Duration(seconds: 1));
    expect(RoamingResilience.retryDelay(2), const Duration(seconds: 2));
    expect(RoamingResilience.retryDelay(3), const Duration(seconds: 4));
    expect(RoamingResilience.retryDelay(4), const Duration(seconds: 8));
    expect(RoamingResilience.retryDelay(5), const Duration(seconds: 12));
    expect(RoamingResilience.retryDelay(6), const Duration(seconds: 20));
    expect(RoamingResilience.retryDelay(7), const Duration(seconds: 30));
    expect(RoamingResilience.retryDelay(100), const Duration(seconds: 30));
  });
}
