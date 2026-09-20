import 'package:geolocator/geolocator.dart';

import '../models/tracking_models.dart';
import 'roaming_resilience.dart';

class LocationCaptureService {
  const LocationCaptureService();

  Future<LocationStamp?> capture({bool requestPermission = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null ||
        !RoamingResilience.validCoordinates(
          position.latitude,
          position.longitude,
        ) ||
        !RoamingResilience.isFresh(
          position.timestamp,
          DateTime.now(),
        )) {
      return null;
    }

    return LocationStamp(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: RoamingResilience.finiteOrZero(position.accuracy),
      capturedAt: position.timestamp,
    );
  }
}