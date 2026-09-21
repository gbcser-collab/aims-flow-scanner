import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AimsDisplayMode { auto, light, dark }

class AimsDisplayModeController extends ChangeNotifier {
  AimsDisplayModeController._();

  static final AimsDisplayModeController instance =
      AimsDisplayModeController._();

  static const _prefsKey = 'aims_display_mode_v1';
  static const _channel =
      MethodChannel('hu.logisticaims.aims_flow/hands_free');

  AimsDisplayMode _mode = AimsDisplayMode.auto;
  bool _resolvedDark = true;
  double? _latitude;
  double? _longitude;

  AimsDisplayMode get mode => _mode;
  bool get isDark => _mode == AimsDisplayMode.dark ||
      (_mode == AimsDisplayMode.auto && _resolvedDark);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _mode = AimsDisplayMode.values.where((m) => m.name == saved).firstOrNull ??
        AimsDisplayMode.auto;
    _recalculate();
    await _applyBrightness();
  }

  Future<void> setMode(AimsDisplayMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
    _recalculate(notify: true);
    await _applyBrightness();
  }

  Future<void> cycleMode() async {
    final next = switch (_mode) {
      AimsDisplayMode.auto => AimsDisplayMode.light,
      AimsDisplayMode.light => AimsDisplayMode.dark,
      AimsDisplayMode.dark => AimsDisplayMode.auto,
    };
    await setMode(next);
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return;
    }
    _latitude = latitude;
    _longitude = longitude;
    final before = _resolvedDark;
    _recalculate();
    if (before != _resolvedDark && _mode == AimsDisplayMode.auto) {
      notifyListeners();
      await _applyBrightness();
    }
  }

  void refreshTime() {
    final before = _resolvedDark;
    _recalculate();
    if (before != _resolvedDark && _mode == AimsDisplayMode.auto) {
      notifyListeners();
      _applyBrightness();
    }
  }

  void _recalculate({bool notify = false}) {
    final now = DateTime.now();
    final lat = _latitude;
    final lon = _longitude;
    _resolvedDark = lat != null && lon != null
        ? _solarNight(now.toUtc(), lat, lon)
        : now.hour < 7 || now.hour >= 19;
    if (notify) notifyListeners();
  }

  bool _solarNight(DateTime utc, double latitude, double longitude) {
    final start = DateTime.utc(utc.year, 1, 1);
    final day = utc.difference(start).inDays + 1;
    final hour = utc.hour + utc.minute / 60 + utc.second / 3600;
    final gamma =
        2 * math.pi / 365 * (day - 1 + (hour - 12) / 24);
    final equationOfTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));
    final declination = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);
    var trueSolarMinutes =
        (utc.hour * 60 + utc.minute + utc.second / 60) +
            equationOfTime +
            4 * longitude;
    trueSolarMinutes %= 1440;
    if (trueSolarMinutes < 0) trueSolarMinutes += 1440;
    var hourAngle = trueSolarMinutes / 4 - 180;
    if (hourAngle < -180) hourAngle += 360;

    final lat = latitude * math.pi / 180;
    final ha = hourAngle * math.pi / 180;
    final cosZenith = math.sin(lat) * math.sin(declination) +
        math.cos(lat) * math.cos(declination) * math.cos(ha);
    final elevation =
        90 - math.acos(cosZenith.clamp(-1.0, 1.0)) * 180 / math.pi;
    return elevation < -3;
  }

  Future<void> _applyBrightness() async {
    try {
      if (isDark) {
        await _channel.invokeMethod<void>('applyNightBrightnessCap', {
          'cap': 0.35,
        });
      } else {
        await _channel.invokeMethod<void>('resetAppBrightness');
      }
    } catch (_) {
      // Brightness control is best effort. Theme mode still works.
    }
  }

  String label(String languageCode) => switch ((_mode, languageCode)) {
        (AimsDisplayMode.auto, 'en') => 'AUTO',
        (AimsDisplayMode.auto, 'de') => 'AUTO',
        (AimsDisplayMode.auto, _) => 'AUTO',
        (AimsDisplayMode.light, 'en') => 'LIGHT',
        (AimsDisplayMode.light, 'de') => 'HELL',
        (AimsDisplayMode.light, _) => 'VILÁGOS',
        (AimsDisplayMode.dark, 'en') => 'DARK',
        (AimsDisplayMode.dark, 'de') => 'DUNKEL',
        (AimsDisplayMode.dark, _) => 'SÖTÉT',
      };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
