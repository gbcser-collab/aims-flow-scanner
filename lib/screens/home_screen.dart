import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/cmr_sync_service.dart';
import '../services/scan_repository.dart';
import '../services/tracking_runtime.dart';
import '../widgets/aims_flow_skin.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';
import 'tracking_screen.dart';
import 'utility_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _repository = ScanRepository();
  static const _sync = CmrSyncService();
  final _tracking = TrackingRuntime.instance;

  bool _opening = false;
  bool _syncing = false;
  String? _error;
  AimsDeviceState _deviceState = AimsDeviceState.unknown;
  List<ScannedDocument> _history = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tracking.addListener(_serviceChanged);
    unawaited(_tracking.initialize());
    unawaited(_loadLocal());
    unawaited(_syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracking.removeListener(_serviceChanged);
    super.dispose();
  }

  void _serviceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadLocal());
      unawaited(_syncNow());
      unawaited(_tracking.syncNow());
    }
  }

  Future<void> _loadLocal() async {
    try {
      final items = await _repository.loadAll();
      if (mounted) setState(() => _history = items);
    } catch (_) {}
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final report = await _sync.syncPending();
      if (mounted) setState(() => _deviceState = report.deviceState);
      await _loadLocal();
    } catch (_) {
      if (mounted) setState(() => _deviceState = AimsDeviceState.unreachable);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openScanner() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'Nem található használható kamera.');
        return;
      }
      final backs = cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      final selected = backs.isNotEmpty ? backs.first : cameras.first;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerScreen(camera: selected)));
      await _loadLocal();
      unawaited(_syncNow());
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'A kamera nem érhető el (${e.code}). Ellenőrizd a kameraengedélyt.');
    } catch (e) {
      if (mounted) setState(() => _error = 'A scanner nem indult el: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openTracking() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackingScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _openSaved(ScannedDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanReviewScreen(processedImagePath: document.imagePath, quality: document.quality, cmr: document.cmr, savedDocument: document)),
    );
    await _loadLocal();
  }

  String _deviceText() {
    return switch (_deviceState) {
      AimsDeviceState.approved => 'Rendben',
      AimsDeviceState.pending => 'Jóváhagyásra vár',
      AimsDeviceState.revoked => 'Visszavonva',
      AimsDeviceState.unreachable => 'Offline',
      AimsDeviceState.unknown => 'Ellenőrzés',
    };
  }

  @override
  Widget build(BuildContext context) {
    final recent = _history.take(3).toList();
    return Scaffold(
      backgroundColor: AimsFlowSkin.background,
      body: AimsFlowBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 108),
            children: [
              Row(
                children: [
                  const Expanded(child: AimsFlowBrand(compact: true)),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _syncing ? null : _syncNow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AimsFlowSkin.panelSolid.withValues(alpha: .76),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AimsFlowSkin.cyan.withValues(alpha: .65)),
                      ),
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: _deviceState == AimsDeviceState.revoked ? Colors.redAccent : AimsFlowSkin.green, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(_syncing ? 'Frissítés…' : 'Online', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 5),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: AimsFlowSkin.paleBlue),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              const Text('Üdvözlünk!', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Készen állsz a következő fuvarra.', style: TextStyle(color: Color(0xFFC9EAFF), fontSize: 18)),
              const SizedBox(height: 14),
              const Text('G Y O R S A B B  F O L Y A M A T O K.\nO K O S A B B  M Ű K Ö D É S.', style: TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 10.5, height: 1.8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              AimsGlowButton(label: 'Smart Scan indítása', icon: Icons.center_focus_strong_rounded, onPressed: _openScanner, busy: _opening),
              const SizedBox(height: 10),
              _secondaryButton(icon: Icons.route_outlined, label: 'Fuvar + GPS', onTap: _openTracking),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                decoration: AimsFlowSkin.glass(radius: 18, alpha: .72),
                child: Row(children: [
                  Expanded(child: _statusItem(Icons.cloud_outlined, 'Szinkronizáció', _syncing ? 'Frissítés' : 'Naprakész', _syncing ? AimsFlowSkin.paleBlue : AimsFlowSkin.green)),
                  _divider(),
                  Expanded(child: _statusItem(Icons.storage_rounded, 'Szerverkapcsolat', _deviceState == AimsDeviceState.unreachable ? 'Offline' : 'Online', _deviceState == AimsDeviceState.unreachable ? Colors.orangeAccent : AimsFlowSkin.green)),
                  _divider(),
                  Expanded(child: _statusItem(Icons.shield_outlined, 'Admin státusz', _deviceText(), _deviceState == AimsDeviceState.revoked ? Colors.redAccent : AimsFlowSkin.green)),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .14), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.redAccent.withValues(alpha: .5))), child: Text(_error!, style: const TextStyle(color: Colors.white))),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _feature(Icons.description_outlined, 'CMR\nszkennelés', _openScanner)),
                const SizedBox(width: 8),
                Expanded(child: _feature(Icons.local_shipping_outlined, 'Fuvarok\nmegtekintése', _openTracking)),
                const SizedBox(width: 8),
                Expanded(child: _feature(Icons.navigation_outlined, 'Navigáció', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NavigationScreen())))),
                const SizedBox(width: 8),
                Expanded(child: _feature(Icons.settings_outlined, 'Beállítások', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())))),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AimsFlowSkin.glass(radius: 18, alpha: .73),
                child: Column(children: [
                  Row(children: [
                    const Expanded(child: Text('Legutóbbi CMR-ek', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
                    TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CmrHistoryScreen())), child: const Text('Összes megtekintése →')),
                  ]),
                  if (recent.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('Még nincs mentett CMR.', style: TextStyle(color: Colors.white60)))
                  else
                    ...recent.map(_recentCard),
                ]),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomNavigation(),
    );
  }

  Widget _secondaryButton({required IconData icon, required String label, required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: AimsFlowSkin.glass(radius: 18, alpha: .68),
          child: Row(children: [Icon(icon, color: AimsFlowSkin.paleBlue, size: 28), Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))), const Icon(Icons.arrow_forward_rounded, color: AimsFlowSkin.paleBlue)]),
        ),
      );

  Widget _statusItem(IconData icon, String label, String value, Color valueColor) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(children: [
          Icon(icon, color: AimsFlowSkin.paleBlue, size: 28),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          const SizedBox(height: 3),
          Text(value, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _divider() => Container(width: 1, height: 68, color: AimsFlowSkin.paleBlue.withValues(alpha: .28));

  Widget _feature(IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          height: 116,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
          decoration: AimsFlowSkin.glass(radius: 17, alpha: .70),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: AimsFlowSkin.cyan, size: 32),
            const SizedBox(height: 9),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _recentCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final title = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR-${document.cmr.cmrNumber}' : 'Mentett CMR';
    final route = [document.cmr.loadingPlace, document.cmr.deliveryPlace].whereType<String>().where((e) => e.trim().isNotEmpty).join(' → ');
    final processed = document.deliveryState == CmrDeliveryState.approved || document.deliveryState == CmrDeliveryState.emailed || document.deliveryState == CmrDeliveryState.uploaded;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: const Color(0xFF0A2741).withValues(alpha: .78), borderRadius: BorderRadius.circular(14), border: Border.all(color: AimsFlowSkin.cyan.withValues(alpha: .35))),
      child: ListTile(
        onTap: () => _openSaved(document),
        leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 42, height: 50, child: image.existsSync() ? Image.file(image, fit: BoxFit.cover) : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_outlined, color: AimsFlowSkin.cyan)))),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        subtitle: Text(route.isEmpty ? 'CMR dokumentum' : route, style: const TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 12)),
        trailing: SizedBox(width: 95, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: processed ? AimsFlowSkin.green : AimsFlowSkin.cyan, shape: BoxShape.circle)), const SizedBox(width: 5), Flexible(child: Text(processed ? 'Feldolgozva' : 'Feldolgozás alatt', maxLines: 2, style: TextStyle(color: processed ? AimsFlowSkin.green : AimsFlowSkin.cyan, fontSize: 10, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded, color: AimsFlowSkin.paleBlue)])),
      ),
    );
  }

  Widget _bottomNavigation() => Container(
        decoration: BoxDecoration(color: const Color(0xFF04101E).withValues(alpha: .97), border: Border(top: BorderSide(color: AimsFlowSkin.cyan.withValues(alpha: .4)))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 78,
            child: Row(children: [
              Expanded(child: _navItem(Icons.home_outlined, 'Kezdőlap', true, () {})),
              Expanded(child: _navItem(Icons.local_shipping_outlined, 'Fuvarok', false, _openTracking)),
              Expanded(child: _navItem(Icons.description_outlined, 'CMR-ek', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CmrHistoryScreen())))),
              Expanded(child: _navItem(Icons.person_outline_rounded, 'Profil', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())))),
            ]),
          ),
        ),
      );

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: active ? Colors.white : AimsFlowSkin.paleBlue, size: 27, shadows: active ? [const Shadow(color: AimsFlowSkin.cyan, blurRadius: 12)] : null),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: active ? Colors.white : AimsFlowSkin.paleBlue, fontSize: 11, fontWeight: active ? FontWeight.w900 : FontWeight.w500)),
        ]),
      );
}
