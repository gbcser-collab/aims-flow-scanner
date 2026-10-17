import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FlowAccountSession {
  const FlowAccountSession({
    this.flowId = '',
    this.onboardingComplete = true,
    required this.expiresAt,
    this.driverName = '',
    this.plate = '',
    this.currentKm,
    this.baseLatitude,
    this.baseLongitude,
    this.baseRadiusMeters = 350,
  });

  final String flowId;
  final bool onboardingComplete;
  final DateTime expiresAt;
  final String driverName;
  final String plate;
  final int? currentKm;
  final double? baseLatitude;
  final double? baseLongitude;
  final double baseRadiusMeters;

  FlowAccountSession copyWith({
    bool? onboardingComplete,
    String? driverName,
    String? plate,
    int? currentKm,
  }) =>
      FlowAccountSession(
        flowId: flowId,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        expiresAt: expiresAt,
        driverName: driverName ?? this.driverName,
        plate: plate ?? this.plate,
        currentKm: currentKm ?? this.currentKm,
        baseLatitude: baseLatitude,
        baseLongitude: baseLongitude,
        baseRadiusMeters: baseRadiusMeters,
      );
}

class FlowSessionStore {
  FlowSessionStore._();
  static final instance = FlowSessionStore._();
  static const _key = 'aims_flow_local_profile_v1';

  Future<FlowAccountSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final plate = (prefs.getString('aims_driver_plate') ?? '').trim().toUpperCase();
    if (plate.isEmpty) return null;
    final raw = prefs.getString(_key);
    Map<String, dynamic> profile = const {};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) profile = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return FlowAccountSession(
      flowId: (prefs.getString('aims_flow_id') ?? '').trim(),
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 3650)),
      driverName: (prefs.getString('aims_driver_name') ?? '').trim(),
      plate: plate,
      currentKm: prefs.getInt('aims_driver_last_odometer_km'),
      baseLatitude: (profile['baseLatitude'] as num?)?.toDouble(),
      baseLongitude: (profile['baseLongitude'] as num?)?.toDouble(),
      baseRadiusMeters: (profile['baseRadiusMeters'] as num?)?.toDouble() ?? 350,
    );
  }

  Future<void> save(FlowAccountSession value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.flowId.isNotEmpty) await prefs.setString('aims_flow_id', value.flowId);
    if (value.driverName.isNotEmpty) {
      await prefs.setString('aims_driver_name', value.driverName);
    }
    if (value.plate.isNotEmpty) {
      await prefs.setString('aims_driver_plate', value.plate);
    }
    if (value.currentKm != null) {
      await prefs.setInt('aims_driver_last_odometer_km', value.currentKm!);
    }
    await prefs.setString(
      _key,
      jsonEncode({
        'baseLatitude': value.baseLatitude,
        'baseLongitude': value.baseLongitude,
        'baseRadiusMeters': value.baseRadiusMeters,
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
