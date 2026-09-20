import 'dart:async';

import 'package:flutter/services.dart';

class AimsHandsFreePlatform {
  AimsHandsFreePlatform._();

  static const MethodChannel _channel =
      MethodChannel('hu.logisticaims.aims_flow/hands_free');

  static final StreamController<void> _assistantInvoked =
      StreamController<void>.broadcast();

  static bool _handlerInstalled = false;

  static Stream<void> get assistantInvoked {
    _installHandler();
    return _assistantInvoked.stream;
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'assistantInvoked') {
        _assistantInvoked.add(null);
      }
    });
  }

  static Future<bool> start() async {
    _installHandler();
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    _installHandler();
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> isRunning() async {
    _installHandler();
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> networkCountryCode() async {
    _installHandler();
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

  static Future<bool> requestAssistantRole() async {
    _installHandler();
    try {
      return await _channel.invokeMethod<bool>('requestAssistantRole') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}