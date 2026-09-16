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
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow Smart Scanner'),
        actions: [
          IconButton(
            tooltip: 'Szinkronizálás',
            onPressed: _sync.syncing ? null : _sync.syncNow,
            icon: _sync.syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE6B85C)))
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF171A1F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6B85C).withValues(alpha: .35)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(18))),
                    child: Padding(
                      padding: EdgeInsets.all(11),
                      child: FlutterLogo(size: 56),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AIMS FLOW • SMART • v1.0',
                          style: TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w800, letterSpacing: 1.2),
                        ),
                        SizedBox(height: 7),
                        Text('CMR Scanner + GPS', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                        SizedBox(height: 8),
                        Text(
                          'Valós dokumentum-scan, OCR, offline mentés, automatikus admin-szinkron és külön indítható aktív-fuvar GPS.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _connectionCard(),
            const SizedBox(height: 12),
            _trackingCard(),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('open-smart-scanner'),
              onPressed: _opening ? null : _openScanner,
              icon: _opening
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_opening ? 'Kamera indítása…' : 'Smart Scan indítása'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            ],
            const SizedBox(height: 18),
            const _Feature(icon: Icons.crop_free_rounded, title: 'Csak a kereten belüli dokumentum', text: 'A feldolgozás a scanner keretéhez igazodik; a környező háttér nem része a végleges CMR-képnek.'),
            const SizedBox(height: 10),
            const _Feature(icon: Icons.offline_pin_rounded, title: 'Offline biztonság', text: 'A mentések az alkalmazás privát tárhelyén maradnak; internetnél automatikusan újrapróbáljuk a szinkront.'),
            const SizedBox(height: 10),
            const _Feature(icon: Icons.location_on_rounded, title: 'Valós idő- és helyadat', text: 'A CMR mentése valós készülékidőt és engedélyezett GPS-pozíciót tud rögzíteni.'),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Text('Legutóbbi mentések', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFE6B85C).withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                  child: Text('${_history.length}', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_historyLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Center(child: CircularProgressIndicator(color: Color(0xFFE6B85C))))
            else if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  children: [
                    Icon(Icons.inbox_rounded, color: Colors.white38),
                    SizedBox(width: 12),
                    Expanded(child: Text('Még nincs mentett CMR. Az első Smart Scan után itt jelenik meg.', style: TextStyle(color: Colors.white60, height: 1.35))),
                  ],
                ),
              )
            else
              ..._history.map(_historyCard),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard() {
    final state = _sync.deviceState;
    final approved = state == 'approved';
    final revoked = state == 'revoked';
    final color = approved ? const Color(0xFF48D597) : (revoked ? Colors.redAccent : Colors.orangeAccent);
    final label = approved ? 'ADMIN KAPCSOLAT AKTÍV' : (revoked ? 'ESZKÖZ VISSZAVONVA' : 'ADMIN JÓVÁHAGYÁSRA VÁR');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(approved ? Icons.verified_rounded : (revoked ? Icons.block_rounded : Icons.hourglass_top_rounded), color: color),
          const SizedBox(width: 10),
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
      ),
    );
  }

  Widget _trackingCard() {
    final active = _tracking.active;
    final point = _tracking.latestPoint;
    return InkWell(
      onTap: _openTracking,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF13231D) : const Color(0xFF14181D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: (active ? const Color(0xFF48D597) : Colors.white24).withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            Icon(active ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, color: active ? const Color(0xFF48D597) : Colors.white54, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(active ? 'ÉLŐ GPS • ${_tracking.session?.plate ?? ''}' : 'Fuvar nyomkövetés', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? (point == null ? 'Valós GPS-jelre vár…' : '${point.speedKmh.toStringAsFixed(0)} km/h • ±${point.accuracy.toStringAsFixed(0)} m • ${_tracking.queuedPointCount} offline')
                        : 'Külön indítható, csak az aktív fuvar alatt fut.',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final primary = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR ${document.cmr.cmrNumber}' : 'Mentett CMR';
    final secondary = [document.cmr.consignee, document.cmr.deliveryPlace].whereType<String>().where((item) => item.trim().isNotEmpty).take(2).join(' • ');
    final syncText = switch (document.syncState) {
      CmrSyncState.approved => 'Jóváhagyva',
      CmrSyncState.emailed => 'E-mail elküldve',
      CmrSyncState.uploaded => 'Feltöltve',
      CmrSyncState.failed => 'Offline sor',
      CmrSyncState.pending => 'Szinkronra vár',
    };

    return Semantics(
      label: 'Mentett CMR dokumentum',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          onTap: () => _openSaved(document),
          contentPadding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 54,
              height: 64,
              child: image.existsSync() ? Image.file(image, fit: BoxFit.cover) : const ColoredBox(color: Colors.white10, child: Icon(Icons.description_rounded, color: Colors.white38)),
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
          trailing: IconButton(tooltip: 'Mentés törlése', onPressed: () => _deleteSaved(document), icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38)),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE6B85C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(color: Colors.white60, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
