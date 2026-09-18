import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/scan_models.dart';
import '../services/cmr_sync_service.dart';
import '../services/scan_repository.dart';
import 'fuel_receipt_screen.dart';
import 'scan_review_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _repository = ScanRepository();
  static const _sync = CmrSyncService();

  bool _opening = false;
  bool _openingFuel = false;
  bool _historyLoading = true;
  bool _syncing = false;
  String? _error;
  String _query = '';
  List<ScannedDocument> _history = const [];

  List<ScannedDocument> get _filteredHistory {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _history;
    return _history.where((document) {
      final cmr = document.cmr;
      final haystack = [
        cmr.cmrNumber,
        cmr.shipper,
        cmr.consignee,
        cmr.loadingPlace,
        cmr.deliveryPlace,
        cmr.date,
        cmr.plate,
        cmr.goodsDescription,
        document.deliveryState.name,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (mounted) setState(() => _syncing = true);
    try {
      await _repository.purgeExpiredApproved();
      await _sync.syncPending();
      await _loadHistory();
    } finally {
      if (mounted) setState(() => _syncing = false);
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
      if (!mounted) return;
      setState(() => _historyLoading = false);
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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScannerScreen(camera: selected)),
      );
      await _refreshAll();
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

  Future<void> _openFuelReceipt() async {
    if (_openingFuel) return;
    setState(() {
      _openingFuel = true;
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
        MaterialPageRoute(builder: (_) => FuelReceiptScreen(camera: selected)),
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A kamera nem érhető el (${e.code}).');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'A tankolási scanner nem indult el: $e');
    } finally {
      if (mounted) setState(() => _openingFuel = false);
    }
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
    await _refreshAll();
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  String _stateLabel(ScannedDocument document) {
    switch (document.deliveryState) {
      case CmrDeliveryState.localOnly:
        return 'APPBAN';
      case CmrDeliveryState.queued:
        return 'KÜLDÉSRE VÁR';
      case CmrDeliveryState.uploaded:
        return 'FELTÖLTVE';
      case CmrDeliveryState.emailed:
        return 'E-MAIL ELKÜLDVE';
      case CmrDeliveryState.approved:
        return 'JÓVÁHAGYVA';
      case CmrDeliveryState.syncError:
        return 'ÚJRAPRÓBÁLÁS';
    }
  }

  Color _stateColor(ScannedDocument document) {
    if (document.deliveryState == CmrDeliveryState.approved) return const Color(0xFF48D597);
    if (document.deliveryState == CmrDeliveryState.syncError) return Colors.orangeAccent;
    return const Color(0xFFE6B85C);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHistory;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow Smart Scanner'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              tooltip: 'Szinkron és frissítés',
              onPressed: _refreshAll,
              icon: const Icon(Icons.cloud_sync_rounded),
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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AIMS FLOW • SMART • PRIVATE CMR',
                    style: TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                  SizedBox(height: 8),
                  Text('CMR Scanner', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10),
                  Text(
                    'A CMR automatikusan az alkalmazás privát tárhelyére kerül. Nem mentjük a Galériába vagy a Letöltések közé. Admin jóváhagyás után 15 nappal automatikusan törlődik a helyi példány.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('open-smart-scanner'),
              onPressed: _opening ? null : _openScanner,
              icon: _opening
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_opening ? 'Kamera indítása…' : 'Smart Scan PRO indítása'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: const Color(0xFFE6B85C),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('open-fuel-receipt'),
              onPressed: _openingFuel ? null : _openFuelReceipt,
              icon: _openingFuel
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.local_gas_station_rounded),
              label: Text(_openingFuel ? 'Kamera indítása…' : 'Tankolási bizonylat küldése'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: const Color(0xFFE6B85C),
                side: const BorderSide(color: Color(0xFFE6B85C)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: .4)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('CMR-ek az appban', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFE6B85C).withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                  child: Text('${_history.length}', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Keresés CMR szám, rendszám, cég, hely, áru…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Keresés törlése',
                          onPressed: () => setState(() => _query = ''),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF14181D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_historyLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE6B85C))),
              )
            else if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.white38),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Még nincs CMR a privát alkalmazástárhelyen.', style: TextStyle(color: Colors.white60, height: 1.35)),
                    ),
                  ],
                ),
              )
            else if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
                child: const Text('Nincs a keresésnek megfelelő CMR.', style: TextStyle(color: Colors.white60)),
              )
            else
              ...filtered.map(_historyCard),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(ScannedDocument document) {
    final image = File(document.imagePath);
    final primary = document.cmr.cmrNumber?.trim().isNotEmpty == true ? 'CMR ${document.cmr.cmrNumber}' : 'Mentett CMR';
    final secondary = [document.cmr.plate, document.cmr.consignee, document.cmr.deliveryPlace]
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .take(3)
        .join(' • ');
    final statusColor = _stateColor(document);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _openSaved(document),
        contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (secondary.isNotEmpty) Text(secondary, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 3),
              Text(_formatDate(document.createdAt), style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 5),
              Text(_stateLabel(document), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .4)),
              if (document.deleteAfter != null)
                Text('Törlés: ${_formatDate(document.deleteAfter!)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: Icon(Icons.chevron_right_rounded, color: statusColor),
      ),
    );
  }
}
