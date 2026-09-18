import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/device_gate.dart';
import 'screens/home_screen.dart';
import 'services/vehicle_tracking_service.dart';
import 'widgets/tracking_status_card.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AimsFlowApp());
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE6B85C);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIMS Flow',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F5F2),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: const DeviceGate(child: _TrackingShell()),
    );
  }
}

class _TrackingShell extends StatefulWidget {
  const _TrackingShell();

  @override
  State<_TrackingShell> createState() => _TrackingShellState();
}

class _TrackingShellState extends State<_TrackingShell> {
  final _tracking = VehicleTrackingService.instance;
  StreamSubscription<VehicleTrackingStatus>? _subscription;
  VehicleTrackingStatus? _status;

  @override
  void initState() {
    super.initState();
    _tracking.currentStatus().then((status) {
      if (!mounted) return;
      setState(() => _status = status);
      unawaited(_tracking.startIfEnabled());
    });
    _subscription = _tracking.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _showTracking() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C0F13),
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 26),
          child: TrackingStatusCard(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _status?.enabled == true && _status?.running == true;
    return Stack(
      children: [
        const HomeScreen(),
        Positioned(
          right: 14,
          bottom: 14,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'tracking-status',
              onPressed: _showTracking,
              backgroundColor: active ? const Color(0xFF48D597) : const Color(0xFF252A30),
              foregroundColor: active ? Colors.black : Colors.white,
              tooltip: active ? 'Nyomkövetés aktív' : 'Nyomkövetés beállítása',
              child: Icon(active ? Icons.gps_fixed_rounded : Icons.gps_off_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
