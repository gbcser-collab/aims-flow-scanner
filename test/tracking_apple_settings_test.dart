import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:aims_flow_scanner/services/tracking_location_settings.dart';

void main() {
  test('iOS keeps one visible automotive background location stream', () {
    final settings = flowLocationSettings(platform: TargetPlatform.iOS,
        interval: const Duration(seconds: 60)) as AppleSettings;
    expect(settings.activityType, ActivityType.automotiveNavigation);
    expect(settings.allowBackgroundLocationUpdates, isTrue);
    expect(settings.showBackgroundLocationIndicator, isTrue);
    expect(settings.pauseLocationUpdatesAutomatically, isFalse);
    expect(settings.distanceFilter, 10);
    expect(settings.accuracy, LocationAccuracy.high);
  });
  test('stationary iOS silence avoids GPS restart loops; missing first fix retries', () {
    bool stale(TargetPlatform platform, bool received) => flowFixNeedsRestart(
      platform: platform, receivedFix: received, age: const Duration(minutes: 10),
      staleAfter: const Duration(minutes: 2));
    expect(stale(TargetPlatform.iOS, true), isFalse);
    expect(stale(TargetPlatform.iOS, false), isTrue);
    expect(stale(TargetPlatform.android, true), isTrue);
  });
  test('Android retains timed fixes without extra wake locks', () {
    final settings = flowLocationSettings(platform: TargetPlatform.android,
        interval: const Duration(seconds: 60)) as AndroidSettings;
    expect(settings.intervalDuration, const Duration(seconds: 60));
    expect(settings.distanceFilter, 0);
    expect(settings.foregroundNotificationConfig!.enableWakeLock, isFalse);
    expect(settings.foregroundNotificationConfig!.enableWifiLock, isFalse);
  });
}
