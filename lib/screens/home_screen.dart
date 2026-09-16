import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/scan_repository.dart';
import '../services/sync_coordinator.dart';
import '../services/tracking_runtime.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';
import 'tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _repository = ScanRepository();
  static const _blue = Color(0xFF1CB8FF);
  static const _blue2 = Color(0xFF0B76FF);
  static const _panel = Color(0xCC0A1727);
  final _sync = SyncCoordinator.instance;
  final _tracking = TrackingRuntime.instance;

  bool _opening = false;
  bool _historyLoading = true;
  String? _error;
  List<ScannedDocument> _history = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync.addListener(_serviceChanged);
    _tracking.addListener(_serviceChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadHistory(),
      _sync.initialize(),
      _tracking.initialize(),
    ]);
  }

  void _serviceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sync.syncNow());
      unawaited(_tracking.syncNow());
      unawaited(_loadHistory());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_serviceChanged);
    _tracking.removeListener(_serviceChanged);
    super.dispose();
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
      if (!mounted) return;
      setState(() => _historyLoading = false);
    }
  }

  Future<void> _openScanner() async {
    if (_opening) return;
    if (_sync.deviceState == 'revoked') {
      setState(() => _error = 'Ezt a készüléket az admin visszavonta. A scanner nem indítható.');
      return;
    }
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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScannerScreen(camera: selected)),
      );
      await _loadHistory();
      unawaited(_sync.syncNow());
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A kamera nem érhető el (${e.code}). Ellenőrizd a kameraengedélyt.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A scanner nem indult el: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openTracking() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackingScreen()));
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

  Future<void> _deleteSaved(ScannedDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mentett CMR törlése?'),
        content: const Text('A dokumentum képe és a mentett CMR-adatok végleg törlődnek erről a készülékről.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Törlés')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(document);
    await _loadHistory();
    await _sync.refreshPendingCount();
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      body: Stack(
        children: [
          const Positioned.fill(child: _BlueCinematicBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AIMS FLOW',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4.2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Szinkronizálás',
                      onPressed: _sync.syncing ? null : _sync.syncNow,
                      icon: _sync.syncing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _blue))
                          : const Icon(Icons.sync_rounded, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Center(child: FlutterLogo(size: 104)),
                const SizedBox(height: 12),
                const Center(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'AIMS ', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Flow', style: TextStyle(color: _blue)),
                      ],
                    ),
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -.8),
                  ),
                ),
                const SizedBox(height: 2),
                const Center(
                  child: Text(
                    'S C A N N E R',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 7),
                  ),
                ),
                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    'AIMS Flow Smart Scanner',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Gyorsabb folyamatok. Okosabb működés.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8FCFFF), letterSpacing: 1.7, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 22),
                _glassPanel(
                  child: Column(
                    children: [
                      _statusStrip(),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        key: const ValueKey('open-smart-scanner'),
                        onPressed: _opening ? null : _openScanner,
                        icon: _opening
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.document_scanner_rounded),
                        label: Text(_opening ? 'Kamera indítása…' : 'Smart Scan indítása'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: _blue2,
                          foregroundColor: Colors.white,
                          shadowColor: _blue,
                          elevation: 8,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openTracking,
                        icon: Icon(_tracking.active ? Icons.gps_fixed_rounded : Icons.location_on_outlined),
                        label: Text(_tracking.active ? 'Élő GPS megnyitása' : 'Fuvar + GPS'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: Colors.white,
                          side: BorderSide(color: _tracking.active ? const Color(0xFF4DE3A4) : _blue, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: .45)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.white)),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: const [
                    Expanded(child: _FeatureMini(icon: Icons.local_shipping_outlined, label: 'JÁRMŰVEK\nNYOMON')),
                    Expanded(child: _FeatureMini(icon: Icons.location_on_outlined, label: 'ÚTVONALAK\nVALÓS IDŐBEN')),
                    Expanded(child: _FeatureMini(icon: Icons.description_outlined, label: 'CMR\nEGYSZERŰEN')),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Legutóbbi mentések', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _blue.withValues(alpha: .35)),
                      ),
                      child: Text('${_history.length}', style: const TextStyle(color: _blue, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_historyLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Center(child: CircularProgressIndicator(color: _blue)),
                  )
                else if (_history.isEmpty)
                  _glassPanel(
                    child: const Row(
                      children: [
                        Icon(Icons.inbox_rounded, color: Colors.white38),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Még nincs mentett CMR. Az első Smart Scan után itt jelenik meg.',
                            style: TextStyle(color: Colors.white60, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._history.map(_historyCard),
                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    'A  H A T É K O N Y A B B  H O L N A P É R T',
                    style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusStrip() {
    final state = _sync.deviceState;
    final approved = state == 'approved';
    final revoked = state == 'revoked';
    final color = approved ? const Color(0xFF4DE3A4) : (revoked ? Colors.redAccent : const Color(0xFFFFC857));
    final label = approved ? 'ADMIN KAPCSOLAT AKTÍV' : (revoked ? 'ESZKÖZ VISSZAVONVA' : 'ADMIN JÓVÁHAGYÁSRA VÁR');
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: .13), shape: BoxShape.circle),
          child: Icon(approved ? Icons.verified_rounded : (revoked ? Icons.block_rounded : Icons.hourglass_top_rounded), color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(height: 3),
              Text(
                _sync.pendingCount == 0 ? 'Nincs várakozó CMR.' : '${_sync.pendingCount} CMR vár automatikus szinkronra.',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _glassPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2B79B5).withValues(alpha: .6)),
        boxShadow: [
          BoxShadow(color: _blue.withValues(alpha: .08), blurRadius: 28, spreadRadius: 1),
        ],
      ),
      child: child,
    );
  }

  Widget _historyCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final primary = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR ${document.cmr.cmrNumber}' : 'Mentett CMR';
    final secondary = [document.cmr.consignee, document.cmr.deliveryPlace]
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .take(2)
        .join(' • ');
    final syncText = switch (document.syncState) {
      CmrSyncState.approved => 'Jóváhagyva',
      CmrSyncState.emailed => 'E-mail elküldve',
      CmrSyncState.uploaded => 'Feltöltve',
      CmrSyncState.failed => 'Offline sor',
      CmrSyncState.pending => 'Szinkronra vár',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF24557D).withValues(alpha: .6)),
      ),
      child: ListTile(
        onTap: () => _openSaved(document),
        contentPadding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 54,
            height: 64,
            child: image.existsSync()
                ? Image.file(image, fit: BoxFit.cover)
                : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_rounded, color: Colors.white38)),
          ),
        ),
        title: Text(primary, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${secondary.isEmpty ? '' : '$secondary\n'}${_formatDate(document.createdAt)} • $syncText',
            style: const TextStyle(color: Colors.white54, height: 1.3),
          ),
        ),
        isThreeLine: secondary.isNotEmpty,
        trailing: IconButton(
          tooltip: 'Mentés törlése',
          onPressed: () => _deleteSaved(document),
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
        ),
      ),
    );
  }
}

class _BlueCinematicBackground extends StatelessWidget {
  const _BlueCinematicBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071E3D), Color(0xFF041427), Color(0xFF02070E)],
          stops: [0, .48, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            left: -110,
            child: Container(
              width: 390,
              height: 390,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF0E7CFF).withValues(alpha: .38), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            right: -160,
            top: 250,
            child: Transform.rotate(
              angle: -.35,
              child: Container(
                width: 360,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(80),
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xFF00B8FF).withValues(alpha: .18), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureMini extends StatelessWidget {
  const _FeatureMini({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF7FCBFF), size: 26),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 9, height: 1.35, letterSpacing: 1.1, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
