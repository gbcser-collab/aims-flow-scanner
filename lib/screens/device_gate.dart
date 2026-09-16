import 'package:flutter/material.dart';

import '../services/cmr_sync_service.dart';

class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> with WidgetsBindingObserver {
  static const _sync = CmrSyncService();

  AimsDeviceState _state = AimsDeviceState.unknown;
  String? _deviceId;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (mounted) setState(() => _checking = true);
    try {
      final report = await _sync.syncPending();
      if (!mounted) return;

      // If the server cannot be reached we keep the last known decision.
      // This preserves offline scanning for an already usable installation.
      final next = report.deviceState;
      setState(() {
        _deviceId = report.deviceId ?? _deviceId;
        if (next != AimsDeviceState.unreachable && next != AimsDeviceState.unknown) {
          _state = next;
        }
      });
    } catch (_) {
      // Network/server failures must not destroy offline scanner availability.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == AimsDeviceState.pending) {
      return _DeviceLockScreen(
        icon: Icons.hourglass_top_rounded,
        title: 'Készülék jóváhagyásra vár',
        message: 'Ez az AIMS Flow telepítés még nincs engedélyezve. Az admin felületen jóvá kell hagyni ezt a készüléket.',
        deviceId: _deviceId,
        checking: _checking,
        onRefresh: _check,
      );
    }

    if (_state == AimsDeviceState.revoked) {
      return _DeviceLockScreen(
        icon: Icons.phonelink_erase_rounded,
        title: 'Hozzáférés visszavonva',
        message: 'Ez a készülék már nem jogosult az AIMS Flow használatára. Az alkalmazást távolítsd el a készülékről.',
        deviceId: _deviceId,
        checking: _checking,
        onRefresh: _check,
        revoked: true,
      );
    }

    return widget.child;
  }
}

class _DeviceLockScreen extends StatelessWidget {
  const _DeviceLockScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.deviceId,
    required this.checking,
    required this.onRefresh,
    this.revoked = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? deviceId;
  final bool checking;
  final VoidCallback onRefresh;
  final bool revoked;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE6B85C);
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFF171A1F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: (revoked ? Colors.redAccent : gold).withValues(alpha: .42)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: revoked ? Colors.redAccent : gold, size: 58),
                  const SizedBox(height: 18),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.45)),
                  if (deviceId != null) ...[
                    const SizedBox(height: 18),
                    const Text('KÉSZÜLÉKAZONOSÍTÓ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    SelectableText(deviceId!, textAlign: TextAlign.center, style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: checking ? null : onRefresh,
                    icon: checking
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: Text(checking ? 'Ellenőrzés…' : 'Jogosultság ellenőrzése'),
                    style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
