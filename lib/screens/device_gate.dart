import 'package:flutter/material.dart';

import '../services/cmr_sync_service.dart';
import '../widgets/aims_skin.dart';

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
      final next = report.deviceState;
      setState(() {
        _deviceId = report.deviceId ?? _deviceId;
        if (next != AimsDeviceState.unreachable && next != AimsDeviceState.unknown) _state = next;
      });
    } catch (_) {
      // Existing approved/offline installations keep working when the server is temporarily unreachable.
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
        message: 'Ez a készülék már nem jogosult az AIMS Flow használatára.',
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
    final accent = revoked ? const Color(0xFFFF6B7D) : aimsCyan;
    return Scaffold(
      backgroundColor: aimsNavy,
      body: AimsBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: AimsGlassCard(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AimsFlowMark(size: 82),
                      const SizedBox(height: 16),
                      Icon(icon, color: accent, size: 54),
                      const SizedBox(height: 16),
                      Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.45)),
                      if (deviceId != null) ...[
                        const SizedBox(height: 18),
                        const Text('KÉSZÜLÉKAZONOSÍTÓ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        SelectableText(deviceId!, textAlign: TextAlign.center, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w800)),
                      ],
                      const SizedBox(height: 22),
                      AimsNeonButton(
                        label: checking ? 'Ellenőrzés…' : 'Jogosultság ellenőrzése',
                        onPressed: checking ? null : onRefresh,
                        leading: checking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
