import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/admin_center_screen.dart';
import 'screens/home_screen.dart';
import 'services/admin_push_service.dart';
import 'services/vehicle_tracking_service.dart';
import 'widgets/tracking_status_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminPushService.instance.initialize();
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F2),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      // Device approval is intentionally no longer an application gate.
      // Access control is moving to account-based authentication and roles.
      home: const _TrackingShell(),
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
  final _push = AdminPushService.instance;
  StreamSubscription<VehicleTrackingStatus>? _subscription;
  StreamSubscription<AdminPushEvent>? _pushSubscription;
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
    _pushSubscription = _push.events.listen(_handlePushEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = _push.takePendingInitialEvent();
      if (initial != null && mounted) _openAdminCenter();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pushSubscription?.cancel();
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

  void _openAdminCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminCenterScreen()),
    );
  }

  void _handlePushEvent(AdminPushEvent event) {
    if (!mounted) return;
    if (event.openedFromNotification) {
      _openAdminCenter();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          event.body.isEmpty
              ? event.title
              : '${event.title}\n${event.body}',
        ),
        action: SnackBarAction(
          label: 'Megnyitás',
          onPressed: _openAdminCenter,
        ),
        duration: const Duration(seconds: 8),
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
              backgroundColor: active
                  ? const Color(0xFF48D597)
                  : const Color(0xFF252A30),
              foregroundColor: active ? Colors.black : Colors.white,
              tooltip: active
                  ? 'Nyomkövetés aktív'
                  : 'Nyomkövetés beállítása',
              child: Icon(
                active ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
