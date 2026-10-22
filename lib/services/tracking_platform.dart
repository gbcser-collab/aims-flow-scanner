import 'dart:io';
import 'package:flutter/services.dart';

class TrackingPlatform {
  static const _channel = MethodChannel('hu.logisticaims.aims_flow/hands_free');

  static Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('setTrackingActive', {'active': active});
  }

  static Future<Map<String, dynamic>> readiness() async {
    if (!Platform.isAndroid) return {};
    return Map<String, dynamic>.from(
      await _channel.invokeMapMethod<String, dynamic>('trackingReadiness') ?? {});
  }

  static Future<bool> openSettings({bool battery = false}) async =>
      await _channel.invokeMethod<bool>(battery ? 'openBatterySettings' : 'openAppSettings') ?? false;
}
