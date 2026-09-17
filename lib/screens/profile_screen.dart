import 'package:flutter/material.dart';

import '../services/cmr_sync_service.dart';
import '../services/device_identity_service.dart';
import '../services/local_auth_service.dart';
import '../widgets/aims_skin.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _deviceId = 'Betöltés…';
  String _deviceState = 'ELLENŐRZÉS…';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      final credentials = await const DeviceIdentityService().getOrCreateCredentials();
      final report = await const CmrSyncService().syncPending();
      if (!mounted) return;
      setState(() {
        _deviceId = credentials.id;
        _deviceState = report.deviceState.name.toUpperCase();
      });
    } catch (_) {
      if (mounted) setState(() => _deviceState = 'OFFLINE');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('Profil'),
      ),
      body: AimsBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Center(child: AimsFlowMark(size: 86)),
            const SizedBox(height: 12),
            const Center(child: Text('AIMS FLOW', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1))),
            const Center(child: Text('DRIVER OPERATIONS', style: TextStyle(color: Color(0xFF8EC9FF), fontSize: 11, letterSpacing: 3))),
            const SizedBox(height: 22),
            AimsGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Eszközállapot', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(_deviceState == 'APPROVED' ? Icons.verified_rounded : Icons.shield_outlined, color: _deviceState == 'APPROVED' ? aimsMint : aimsCyan),
                      const SizedBox(width: 8),
                      Text(_deviceState, style: TextStyle(color: _deviceState == 'APPROVED' ? aimsMint : aimsCyan, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Készülékazonosító', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 5),
                  SelectableText(_deviceId, style: const TextStyle(color: Color(0xFFB7E6FF), fontWeight: FontWeight.w700, fontSize: 12)),
                  if (_busy) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(color: aimsCyan),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            AimsNeonButton(
              label: 'Eszközállapot frissítése',
              onPressed: _busy ? null : _load,
              secondary: true,
              leading: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF9BAB),
                  side: const BorderSide(color: Color(0xFFB9374F)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  LocalAuthService.instance.logout();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Kijelentkezés', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
