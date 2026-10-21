import 'flow_auth_service.dart';

import 'dart:convert';

import 'flow_preferences.dart';

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
  }) => FlowAccountSession(
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
    final prefs = await FlowPreferences.getInstance();
    final auth = FlowAuthService.instance.session;
    if (auth == null) return null;
    final plate = auth.plate;
    final raw = prefs.getString(_key);
    Map<String, dynamic> profile = const {};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) profile = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return FlowAccountSession(
      flowId: auth.flowId,
      expiresAt: auth.refreshExpiresAt,
      driverName: (prefs.getString('aims_driver_name') ?? '').trim(),
      plate: plate,
      currentKm: prefs.getInt('aims_driver_last_odometer_km'),
      baseLatitude: (profile['baseLatitude'] as num?)?.toDouble(),
      baseLongitude: (profile['baseLongitude'] as num?)?.toDouble(),
      baseRadiusMeters:
          (profile['baseRadiusMeters'] as num?)?.toDouble() ?? 350,
    );
  }

  Future<void> save(FlowAccountSession value) async {
    final prefs = await FlowPreferences.getInstance();
    if (value.flowId.isNotEmpty)
      await prefs.setString('aims_flow_id', value.flowId);
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
    final prefs = await FlowPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove('aims_driver_plate');
    await prefs.remove('aims_driver_name');
    await prefs.remove('aims_flow_id');
    await prefs.remove('aims_driver_local_unlock');
    await FlowAuthService.instance.logout();
  }
}
