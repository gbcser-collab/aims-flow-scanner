import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/cmr_sync_service.dart';
import '../services/gps_tracking_service.dart';
import '../services/scan_repository.dart';
import '../widgets/aims_skin.dart';
import 'cmr_list_screen.dart';
import 'gps_screen.dart';
import 'navigation_screen.dart';
import 'profile_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _repository = ScanRepository();
  static const _sync = CmrSyncService();
  final _gps = GpsTrackingService.instance;

  bool _opening = false;
  bool _syncing = false;
  bool _historyLoading = true;
  String? _error;
  CmrSyncReport? _report;
  List<ScannedDocument> _history = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gps.addListener(_gpsChanged);
    unawaited(_gps.initialize());
    unawaited(_loadHistory());
    unawaited(_syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gps.removeListener(_gpsChanged);
    super.dispose();
  }

  void _gpsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadHistory());
      unawaited(_syncNow());
    }
  }

  Future<void> _loadHistory() async {
    try {
      final items = await _repository.loadAll();
      if (!mounted) return;
      setState(() {
        _history = items;
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    try {
      await _repository.purgeExpiredApproved();
      final report = await _sync.syncPending();
      if (mounted) setState(() => _report = report);
      await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _error = 'Szinkronhiba: $e');
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
      final backs = cameras.where((camera) => camera.lensDirection == CameraLensDirection.back).toList();
      final selected = backs.isNotEmpty ? backs.first : cameras.first;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerScreen(camera: selected)));
      await _loadHistory();
      unawaited(_syncNow());
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'A kamera nem érhető el (${e.code}). Ellenőrizd a kameraengedélyt.');
    } catch (e) {
      if (mounted) setState(() => _error = 'A scanner nem indult el: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _loadHistory();
  }

  Future<void> _openSaved(ScannedDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          processedImagePath: document.imagePath,
          quality: document.quality,
          cmr: document.cmr,
          savedDocument: document,
        ),
      ),
    );
    await _loadHistory();
  }

  bool get _online {
    final report = _report;
    if (report == null) return false;
    return !report.notConfigured && report.deviceState != AimsDeviceState.unreachable;
  }

  String get _adminLabel {
    switch (_report?.deviceState) {
      case AimsDeviceState.approved:
        return 'Rendben';
      case AimsDeviceState.pending:
        return 'Jóváhagyásra vár';
      case AimsDeviceState.revoked:
        return 'Visszavonva';
      case AimsDeviceState.unreachable:
        return 'Offline';
      default:
        return 'Ellenőrzés';
    }
  }

  String _stateLabel(ScannedDocument document) {
    switch (document.deliveryState) {
      case CmrDeliveryState.approved:
        return 'Feldolgozva';
      case CmrDeliveryState.emailed:
        return 'E-mail elküldve';
      case CmrDeliveryState.uploaded:
        return 'Feltöltve';
      case CmrDeliveryState.queued:
        return 'Szinkronra vár';
      case CmrDeliveryState.syncError:
        return 'Offline sor';
      case CmrDeliveryState.localOnly:
        return 'Helyben mentve';
    }
  }

  Color _stateColor(ScannedDocument document) {
    return document.deliveryState == CmrDeliveryState.approved ? aimsMint : aimsCyan;
  }

  String _route(ScannedDocument document) {
    return [document.cmr.loadingPlace, document.cmr.deliveryPlace]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' → ');
  }

  String _relativeDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final sameDay = now.year == local.year && now.month == local.month && now.day == local.day;
    if (sameDay) return 'Ma $time';
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday = yesterday.year == local.year && yesterday.month == local.month && yesterday.day == local.day;
    if (wasYesterday) return 'Tegnap $time';
    return '${local.month}.${two(local.day)} $time';
  }

  Widget _statusColumn(IconData icon, String title, String value, {String? small}) {
    final good = value == 'Naprakész' || value == 'Online' || value == 'Rendben';
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF9EDBFF), size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFFC4E5FF), fontSize: 11)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: good ? aimsMint : aimsCyan)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: good ? aimsMint : aimsCyan, fontWeight: FontWeight.w800, fontSize: 12))),
                  ],
                ),
                if (small != null) Text(small, style: const TextStyle(color: Colors.white54, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: AimsGlassCard(
          padding: EdgeInsets.zero,
          radius: 16,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 116,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: aimsCyan, size: 34),
                  const SizedBox(height: 10),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final number = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR-${document.cmr.cmrNumber}' : 'Mentett CMR';
    final route = _route(document);
    final stateColor = _stateColor(document);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xB50A2447),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF247AC0).withValues(alpha: .8)),
        ),
        child: ListTile(
          onTap: () => _openSaved(document),
          contentPadding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 42,
              height: 50,
              child: image.existsSync()
                  ? Image.file(image, fit: BoxFit.cover)
                  : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_outlined, color: aimsCyan)),
            ),
          ),
          title: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
          subtitle: Text(route.isEmpty ? 'CMR dokumentum' : route, style: const TextStyle(color: Color(0xFF9FD5FF), fontSize: 12)),
          trailing: SizedBox(
            width: 118,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor)),
                          const SizedBox(width: 5),
                          Flexible(child: Text(_stateLabel(document), overflow: TextOverflow.ellipsis, style: TextStyle(color: stateColor, fontSize: 10, fontWeight: FontWeight.w700))),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(_relativeDate(document.createdAt), style: const TextStyle(color: Color(0xFF84BFF4), fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF9EDBFF)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNav() {
    Widget item(IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: selected ? Colors.white : const Color(0xFFA0CDEF), size: 28, shadows: selected ? const [Shadow(color: aimsCyan, blurRadius: 14)] : null),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFFA0CDEF), fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0061A35),
        border: Border(top: BorderSide(color: aimsCyan.withValues(alpha: .55))),
        boxShadow: [BoxShadow(color: aimsBlue.withValues(alpha: .18), blurRadius: 18)],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            item(Icons.home_outlined, 'Kezdőlap', () {}, selected: true),
            item(Icons.local_shipping_outlined, 'Fuvarok', () => _push(const GpsScreen())),
            item(Icons.description_outlined, 'CMR-ek', () => _push(const CmrListScreen())),
            item(Icons.person_outline_rounded, 'Profil', () => _push(const ProfileScreen())),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = _history.take(3).toList();
    final syncLabel = _syncing ? 'Frissítés…' : (_report?.failed ?? 0) > 0 ? 'Várakozik' : 'Naprakész';
    final serverLabel = _online ? 'Online' : 'Offline';
    return Scaffold(
      backgroundColor: aimsNavy,
      bottomNavigationBar: _bottomNav(),
      body: AimsBackdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            children: [
              const AimsFakeStatusBar(),
              const SizedBox(height: 22),
              Row(
                children: [
                  const AimsFlowMark(size: 56),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AIMS FLOW', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        Text('D R I V E R   O P E R A T I O N S', style: TextStyle(color: Color(0xFF8EC9FF), fontSize: 8, letterSpacing: 1.7)),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: _syncNow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xBB0A2E59),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: aimsBlue),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: _online ? aimsMint : const Color(0xFFFFC85B))),
                          const SizedBox(width: 8),
                          Text(_online ? 'Online' : 'Offline', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Text('Üdvözlünk!', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -.6)),
              const SizedBox(height: 3),
              const Text('Készen állsz a következő fuvarra.', style: TextStyle(color: Color(0xFFB9DEFF), fontSize: 18)),
              const SizedBox(height: 18),
              const Text('G Y O R S A B B   F O L Y A M A T O K .\nO K O S A B B   M Ű K Ö D É S .', style: TextStyle(color: Color(0xFF8EC9FF), fontSize: 10, height: 1.65, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              AimsNeonButton(
                label: _opening ? 'Kamera indítása…' : 'Smart Scan indítása',
                onPressed: _opening ? null : _openScanner,
                leading: _opening
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner_outlined, color: Colors.white, size: 31),
              ),
              const SizedBox(height: 12),
              AimsNeonButton(
                label: _gps.active ? 'Élő GPS megnyitása' : 'Fuvar + GPS',
                onPressed: () => _push(const GpsScreen()),
                secondary: true,
                leading: Icon(_gps.active ? Icons.gps_fixed_rounded : Icons.route_outlined, color: const Color(0xFFC5E8FF), size: 29),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              AimsGlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
                radius: 16,
                child: Row(
                  children: [
                    _statusColumn(Icons.cloud_outlined, 'Szinkronizáció', syncLabel, small: _syncing ? null : 'CMR: ${_history.length}'),
                    Container(width: 1, height: 55, color: const Color(0xFF2D6D9D)),
                    const SizedBox(width: 9),
                    _statusColumn(Icons.storage_rounded, 'Szerverkapcsolat', serverLabel),
                    Container(width: 1, height: 55, color: const Color(0xFF2D6D9D)),
                    const SizedBox(width: 9),
                    _statusColumn(Icons.verified_user_outlined, 'Admin státusz', _adminLabel),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _actionTile(Icons.description_outlined, 'CMR\nszkennelés', _openScanner),
                  _actionTile(Icons.list_alt_rounded, 'Fuvarok\nmegtekintése', () => _push(const GpsScreen())),
                  _actionTile(Icons.navigation_rounded, 'Navigáció', () => _push(const NavigationScreen())),
                  _actionTile(Icons.settings_outlined, 'Beállítások', () => _push(const SettingsScreen())),
                ],
              ),
              const SizedBox(height: 14),
              AimsGlassCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                radius: 18,
                child: Column(
                  children: [
                    AimsSectionTitle(
                      'Legutóbbi CMR-ek',
                      trailing: TextButton(
                        onPressed: () => _push(const CmrListScreen()),
                        child: const Text('Összes megtekintése →', style: TextStyle(color: Color(0xFF9FD5FF), fontSize: 11)),
                      ),
                    ),
                    if (_historyLoading)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(color: aimsCyan),
                      )
                    else if (recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('Még nincs mentett CMR.', style: TextStyle(color: Colors.white60)),
                      )
                    else
                      ...recent.map(_historyCard),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
