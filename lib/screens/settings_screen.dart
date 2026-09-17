import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/cmr_sync_service.dart';
import '../widgets/aims_skin.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;
  String? _message;

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final report = await const CmrSyncService().syncPending();
      if (!mounted) return;
      final state = report.deviceState.name.toUpperCase();
      setState(() => _message = 'Szinkron kész • eszköz: $state • sikeres: ${report.succeeded} • hibás: ${report.failed}');
    } catch (e) {
      if (mounted) setState(() => _message = 'Szinkronhiba: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Widget _tile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AimsGlassCard(
        padding: EdgeInsets.zero,
        radius: 16,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: aimsCyan),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8ED8FF)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('Beállítások'),
      ),
      body: AimsBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _tile(
              icon: Icons.cloud_sync_rounded,
              title: 'Szinkronizáció most',
              subtitle: 'CMR-ek és eszközállapot azonnali frissítése',
              onTap: _syncing ? () {} : _sync,
            ),
            _tile(
              icon: Icons.location_on_outlined,
              title: 'Helymeghatározás beállításai',
              subtitle: 'Android GPS / helyszolgáltatás megnyitása',
              onTap: () => Geolocator.openLocationSettings(),
            ),
            _tile(
              icon: Icons.settings_applications_rounded,
              title: 'Android alkalmazásengedélyek',
              subtitle: 'Kamera, hely és egyéb engedélyek kezelése',
              onTap: () => Geolocator.openAppSettings(),
            ),
            if (_syncing) ...[
              const SizedBox(height: 8),
              const Center(child: CircularProgressIndicator(color: aimsCyan)),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              AimsGlassCard(child: Text(_message!, style: const TextStyle(color: Colors.white70, height: 1.35))),
            ],
          ],
        ),
      ),
    );
  }
}
