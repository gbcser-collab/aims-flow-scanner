import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

LocationSettings flowLocationSettings({
  required TargetPlatform platform,
  required Duration interval,
}) {
  if (platform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  }
  if (platform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: interval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'AIMS FLOW – munkanapkövetés',
        notificationText: 'A helyzet a munkanap lezárásáig frissül. Megnyitás: részletek.',
        enableWakeLock: false,
        enableWifiLock: false,
        setOngoing: true,
      ),
    );
  }
  return const LocationSettings(accuracy: LocationAccuracy.high);
}

// With an iOS displacement filter, a stationary phone need not emit fixes.
// Silence after a fix is not an error; service/error/done events still recover.
bool flowFixNeedsRestart({
  required TargetPlatform platform,
  required bool receivedFix,
  required Duration age,
  required Duration staleAfter,
}) => !(platform == TargetPlatform.iOS && receivedFix) && age > staleAfter;
