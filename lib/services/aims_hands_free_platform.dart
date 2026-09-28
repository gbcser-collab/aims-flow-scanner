import 'package:flutter/services.dart';

/// Minimal native bridge retained for the tracking country-code fallback.
///
/// Interactive voice-assistant features were intentionally removed in R105.
class AimsHandsFreePlatform {
  AimsHandsFreePlatform._();

  static const MethodChannel _channel =
      MethodChannel('hu.logisticaims.aims_flow/hands_free');

  static Future<String?> networkCountryCode() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'networkCountry',
      );
      final code = (result?['network'] ?? '').toString().trim().toUpperCase();
      if (RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
