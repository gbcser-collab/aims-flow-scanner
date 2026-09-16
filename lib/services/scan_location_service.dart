import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/scan_models.dart';

class ScanLocationService {
  const ScanLocationService();

  Future<ScanLocation?> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) return null;
      return ScanLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
