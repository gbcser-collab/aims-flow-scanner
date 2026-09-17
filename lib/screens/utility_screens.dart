import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/scan_models.dart';
import '../services/cmr_sync_service.dart';
import '../services/device_identity_service.dart';
import '../services/scan_repository.dart';
import '../widgets/aims_flow_skin.dart';
import 'scan_review_screen.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _destination = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _openMaps() async {
    final destination = _destination.text.trim();
    if (destination.isEmpty) {
      setState(() => _error = 'Add meg az úti célt.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      } catch (_) {}
      final origin = position == null ? '' : '&origin=${position.latitude},${position.longitude}';
      final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}$origin&travelmode=driving');
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('A térkép nem nyitható meg.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BasePage(
        title: 'Navigáció',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.navigation_rounded, color: AimsFlowSkin.cyan, size: 58),
          const SizedBox(height: 16),
          const Text('Úti cél', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 10),
          TextField(
            controller: _destination,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cím, város vagy telephely',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: AimsFlowSkin.panelSolid,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AimsFlowSkin.cyan)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AimsFlowSkin.cyan, width: 1.5)),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 14),
          AimsGlowButton(label: 'Útvonal indítása', icon: Icons.map_outlined, onPressed: _openMaps, busy: _busy),
        ]),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final report = await const CmrSyncService().syncPending();
      if (mounted) setState(() => _message = 'Szinkron kész • eszköz: ${report.deviceState.name}');
    } catch (e) {
      if (mounted) setState(() => _message = 'Szinkron hiba: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BasePage(
        title: 'Beállítások',
        child: Column(children: [
          _SettingTile(icon: Icons.cloud_sync_rounded, title: 'Szinkronizálás most', subtitle: 'CMR és admin státusz frissítése', onTap: _busy ? null : _sync),
          _SettingTile(icon: Icons.location_on_outlined, title: 'Helymeghatározás beállításai', subtitle: 'GPS engedély és helyszolgáltatás', onTap: Geolocator.openLocationSettings),
          _SettingTile(icon: Icons.settings_applications_outlined, title: 'Android alkalmazásbeállítások', subtitle: 'Engedélyek és rendszerbeállítások', onTap: Geolocator.openAppSettings),
          if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!, style: const TextStyle(color: AimsFlowSkin.paleBlue))),
        ]),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _deviceId;
  String _status = 'ellenőrzés…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = await const DeviceIdentityService().getOrCreateId();
    var status = 'offline';
    try {
      final report = await const CmrSyncService().syncPending();
      status = report.deviceState.name;
    } catch (_) {}
    if (mounted) setState(() {
      _deviceId = id;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) => _BasePage(
        title: 'Profil',
        child: Column(children: [
          const CircleAvatar(radius: 38, backgroundColor: Color(0xFF0E3454), child: Icon(Icons.person_rounded, color: AimsFlowSkin.cyan, size: 42)),
          const SizedBox(height: 14),
          const Text('AIMS Flow felhasználó', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 21)),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AimsFlowSkin.glass(radius: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ESZKÖZ STÁTUSZ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(_status.toUpperCase(), style: const TextStyle(color: AimsFlowSkin.green, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              const Text('KÉSZÜLÉKAZONOSÍTÓ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              SelectableText(_deviceId ?? '—', style: const TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Frissítés')),
        ]),
      );
}

class CmrHistoryScreen extends StatefulWidget {
  const CmrHistoryScreen({super.key});

  @override
  State<CmrHistoryScreen> createState() => _CmrHistoryScreenState();
}

class _CmrHistoryScreenState extends State<CmrHistoryScreen> {
  final _repository = const ScanRepository();
  List<ScannedDocument>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repository.loadAll();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) => _BasePage(
        title: 'CMR-ek',
        child: _items == null
            ? const Center(child: CircularProgressIndicator(color: AimsFlowSkin.cyan))
            : _items!.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Még nincs mentett CMR.', style: TextStyle(color: Colors.white60)))
                : Column(children: _items!.map(_card).toList()),
      );

  Widget _card(ScannedDocument document) {
    final image = File(document.imagePath);
    final title = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR-${document.cmr.cmrNumber}' : 'Mentett CMR';
    final route = [document.cmr.loadingPlace, document.cmr.deliveryPlace].whereType<String>().where((e) => e.trim().isNotEmpty).join(' → ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AimsFlowSkin.glass(radius: 16, alpha: .68),
      child: ListTile(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanReviewScreen(processedImagePath: document.imagePath, quality: document.quality, cmr: document.cmr, savedDocument: document)));
          await _load();
        },
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(width: 48, height: 58, child: image.existsSync() ? Image.file(image, fit: BoxFit.cover) : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_outlined, color: AimsFlowSkin.cyan))),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        subtitle: Text(route.isEmpty ? document.createdAt.toLocal().toString() : route, style: const TextStyle(color: AimsFlowSkin.paleBlue)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AimsFlowSkin.cyan),
      ),
    );
  }
}

class _BasePage extends StatelessWidget {
  const _BasePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AimsFlowSkin.background,
        appBar: AppBar(backgroundColor: AimsFlowSkin.background, foregroundColor: Colors.white, title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
        body: AimsFlowBackground(child: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [child]))),
      );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: AimsFlowSkin.glass(radius: 16, alpha: .68),
        child: ListTile(
          onTap: onTap == null ? null : () => onTap!(),
          leading: Icon(icon, color: AimsFlowSkin.cyan),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AimsFlowSkin.paleBlue),
        ),
      );
}
