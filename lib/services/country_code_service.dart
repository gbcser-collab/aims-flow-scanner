import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'aims_hands_free_platform.dart';

class CountryCodeService {
  CountryCodeService._();

  static final CountryCodeService instance = CountryCodeService._();
  final Geocoding _geocoding = Geocoding();
  Future<String?>? _inFlight;
  DateTime? _lastLookupAt;
  DateTime? _lastResolvedAt;
  double? _lastLatitude;
  double? _lastLongitude;
  String? _lastCountryCode;

  Future<String?> resolve(Position position) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final now = DateTime.now();
    final lastLookup = _lastLookupAt;
    final lastLat = _lastLatitude;
    final lastLng = _lastLongitude;
    final distance = lastLat == null || lastLng == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lastLat,
            lastLng,
            position.latitude,
            position.longitude,
          );

    final canReuse = _lastCountryCode != null &&
        lastLookup != null &&
        now.difference(lastLookup) < const Duration(seconds: 45) &&
        distance < 1200;
    if (canReuse) return Future<String?>.value(_lastCountryCode);

    final completer = Completer<String?>();
    _inFlight = completer.future;
    unawaited(_resolveFresh(position, now).then(
      completer.complete,
      onError: (_) => completer.complete(_fallback(now)),
    ).whenComplete(() {
      _inFlight = null;
    }));
    return completer.future;
  }

  Future<String?> _resolveFresh(Position position, DateTime now) async {
    _lastLookupAt = now;
    _lastLatitude = position.latitude;
    _lastLongitude = position.longitude;

    try {
      final places = await _geocoding
          .placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          )
          .timeout(const Duration(seconds: 6));
      if (places.isEmpty) return await _networkOrCache(now);
      final code = (places.first.isoCountryCode ?? '').trim().toUpperCase();
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
        return await _networkOrCache(now);
      }
      _lastCountryCode = code;
      _lastResolvedAt = now;
      return code;
    } catch (_) {
      return await _networkOrCache(now);
    }
  }

  Future<String?> _networkOrCache(DateTime now) async {
    final network = await AimsHandsFreePlatform.networkCountryCode();
    if (network != null) {
      _lastCountryCode = network;
      _lastResolvedAt = now;
      return network;
    }
    return _fallback(now);
  }

  String? _fallback(DateTime now) {
    final resolvedAt = _lastResolvedAt;
    if (_lastCountryCode == null || resolvedAt == null) return null;
    if (now.difference(resolvedAt) > const Duration(minutes: 10)) return null;
    return _lastCountryCode;
  }
}