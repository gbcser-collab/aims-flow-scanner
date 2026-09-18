import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/driver_api_service.dart';
import '../services/driver_push_service.dart';
import '../services/vehicle_tracking_service.dart';
import 'fuel_receipt_screen.dart';
import 'scanner_screen.dart';

class DriverShellScreen extends StatefulWidget {
  const DriverShellScreen({super.key});

  @override
  State<DriverShellScreen> createState() => _DriverShellScreenState();
}

class _DriverShellScreenState extends State<DriverShellScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _green = Color(0xFF4DE3A4);
  static const _panelColor = Color(0xFF071725);
  static const _prefsPlate = 'aims_driver_plate';

  final _api = const DriverApiService();
  final _tracking = VehicleTrackingService.instance;
  final _push = DriverPushService.instance;

  StreamSubscription<DriverPushEvent>? _pushSub;
  StreamSubscription<VehicleTrackingStatus>? _trackingSub;

  int _index = 0;
  String _plate = '';
  List<DriverJob> _jobs = const [];
  bool _loading = true;
  bool _actionBusy = false;
  String? _message;
  VehicleTrackingStatus? _trackingStatus;

  DriverJob? get _job => _jobs.isEmpty ? null : _jobs.first;
  DriverStop? get _stop => _job?.currentStop;

  @override
  void initState() {
    super.initState();
    _pushSub = _push.events.listen(_handlePush);
    _trackingSub = _tracking.statusStream.listen((status) {
      if (mounted) setState(() => _trackingStatus = status);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var plate = (prefs.getString(_prefsPlate) ?? '').trim().toUpperCase();

    final status = await _tracking.currentStatus();
    if (plate.isEmpty && status.vehicleLabel.trim().isNotEmpty) {
      plate = status.vehicleLabel.trim().toUpperCase();
    }

    if (!mounted) return;
    setState(() {
      _plate = plate;
      _trackingStatus = status;
    });

    if (_plate.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askPlate());
    } else {
      await _activateDriverServices();
    }

    final pending = _push.takePendingLaunch();
    if (pending != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePush(pending));
    }
  }

  Future<void> _askPlate() async {
    final controller = TextEditingController(text: _plate);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: const Text('Jármű beállítása'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Rendszám',
            hintText: 'pl. SIP-115',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final value = controller.text.trim().toUpperCase();
              if (value.length >= 4) Navigator.pop(context, value);
            },
            child: const Text('MENTÉS'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPlate, result);
    await _tracking.setVehicleLabel(result);
    setState(() => _plate = result);
    await _activateDriverServices();
  }

  Future<void> _activateDriverServices() async {
    if (_plate.isEmpty) return;
    try {
      await _tracking.setVehicleLabel(_plate);
      final status = await _tracking.currentStatus();
      if (!status.enabled) {
        await _tracking.enableWithPermission();
      } else {
        await _tracking.startIfEnabled();
      }
      await _push.registerForPlate(_plate);
    } catch (e) {
      if (mounted) setState(() => _message = 'Háttérszolgáltatás: $e');
    }
    await _refreshJobs();
  }

  Future<void> _refreshJobs() async {
    if (_plate.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final jobs = await _api.fetchJobs(_plate);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _message = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Fuvaradatok nem frissültek: $e';
      });
    }
  }

  Future<void> _handlePush(DriverPushEvent event) async {
    if (!mounted) return;
    if (event.data['type']?.toString() != 'driver_job') return;
    await _refreshJobs();
    if (!mounted) return;

    final jobId = event.jobId;
    if (event.actionId == 'seen_job' && jobId > 0) {
      await _ack(jobId, 'seen', closeDialog: false);
      return;
    }
    _showJobDialog(jobId: jobId);
  }

  Future<void> _showJobDialog({int? jobId}) async {
    DriverJob? job;
    if (jobId != null && jobId > 0) {
      for (final item in _jobs) {
        if (item.id == jobId) {
          job = item;
          break;
        }
      }
    }
    job ??= _job;
    if (job == null || !mounted) return;

    final first = job.stops.isEmpty ? null : job.stops.first;
    final last = job.stops.isEmpty ? null : job.stops.last;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: const Text(
          'ÚJ FUVAR ÉRKEZETT',
          style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first?.company.isNotEmpty == true ? first!.company : job!.reference,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '${first?.address ?? '—'}\n→\n${last?.address ?? '—'}',
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              '${job!.stops.length} megálló · ${job.reference}',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _actionBusy
                ? null
                : () => _ack(job!.id, 'seen', closeDialog: true),
            child: const Text('LÁTTAM'),
          ),
          FilledButton(
            onPressed: _actionBusy
                ? null
                : () => _ack(job!.id, 'accepted', closeDialog: true),
            child: const Text('ELFOGADOM'),
          ),
        ],
      ),
    );
  }

  Future<void> _ack(
    int jobId,
    String action, {
    required bool closeDialog,
  }) async {
    if (_actionBusy || _plate.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      await _api.acknowledge(plate: _plate, jobId: jobId, action: action);
      if (closeDialog && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await _refreshJobs();
      if (mounted) {
        _snack(action == 'accepted'
            ? 'Fuvar elfogadva.'
            : 'Visszaigazolva: LÁTTAM.');
      }
    } catch (e) {
      if (mounted) _snack('Visszaigazolási hiba: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openMaps() async {
    final stop = _stop;
    if (stop == null || stop.address.trim().isEmpty) {
      _snack('Nincs megnyitható következő cím.');
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(stop.address)}&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('A Google Maps nem nyitható meg.');
    }
  }

  Future<CameraDescription?> _backCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;
    final backs =
        cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
    return backs.isNotEmpty ? backs.first : cameras.first;
  }

  Future<void> _openCmrScanner() async {
    try {
      final camera = await _backCamera();
      if (!mounted) return;
      if (camera == null) {
        _snack('Nem található kamera.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScannerScreen(camera: camera)),
      );
    } catch (e) {
      _snack('A scanner nem indult el: $e');
    }
  }

  Future<void> _openFuelReceipt() async {
    try {
      final camera = await _backCamera();
      if (!mounted) return;
      if (camera == null) {
        _snack('Nem található kamera.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FuelReceiptScreen(camera: camera)),
      );
    } catch (e) {
      _snack('A bizonylat scanner nem indult el: $e');
    }
  }

  Future<void> _sendSignal(
    String type, {
    bool urgent = false,
    String? message,
  }) async {
    if (_plate.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      final status = await _tracking.currentStatus();
      final p = status.lastPosition;
      await _api.sendSignal(
        plate: _plate,
        type: type,
        urgent: urgent,
        message: message,
        latitude: p?.latitude,
        longitude: p?.longitude,
      );
      if (mounted) _snack('Jelzés elküldve a főnökségnek.');
    } catch (e) {
      if (mounted) _snack('A jelzés nem ment el: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _snack(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _trackingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      body: IndexedStack(
        index: _index,
        children: [
          _home(),
          _trip(),
          _quickSignal(),
          _documents(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: const Color(0xFF030D16),
        indicatorColor: _blue.withValues(alpha: .18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'KEZDŐLAP',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'FUVAROM',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'GYORS JELZÉS',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'DOKSI',
          ),
        ],
      ),
    );
  }

  Widget _page(List<Widget> children) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshJobs,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: children,
            ),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AIMS FLOW',
                  style: TextStyle(
                    letterSpacing: 3.4,
                    color: Colors.white70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'DRIVER MODE',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _status(
            _trackingStatus?.running == true ? 'GPS AKTÍV' : 'GPS',
            _trackingStatus?.running == true ? _green : Colors.white38,
          ),
        ],
      );

  Widget _home() {
    final job = _job;
    final stop = _stop;
    final currentCompany = stop?.company.trim().isNotEmpty == true
        ? stop!.company
        : (job?.reference ?? 'Nincs aktív fuvar');

    return _page([
      _header(),
      const SizedBox(height: 16),
      if (_loading)
        const LinearProgressIndicator(minHeight: 2)
      else
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentCompany,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                job == null
                    ? 'Új munka érkezésekor a Flow itt azonnal szól.'
                    : 'AKTÍV FUVAR · ${job.reference} · ${job.stops.length} stop',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 18),
              if (job == null) ...[
                const Text(
                  'Nincs teendőd.',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                const Text(
                  'A nyomkövetés és az értesítések a háttérben működnek.',
                  style: TextStyle(color: Colors.white54, height: 1.35),
                ),
              ] else ...[
                const Text(
                  'KÖVETKEZŐ LÉPÉS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  stop?.type == 'delivery'
                      ? 'Indulás a lerakóra'
                      : 'Indulás a felrakóra',
                  style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  stop?.address ?? '—',
                  style: const TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openMaps,
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('NAVIGÁCIÓ INDÍTÁSA'),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _metric('JÁRMŰ', _plate.isEmpty ? '—' : _plate)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metric(
                      'KÖVETÉS',
                      _trackingStatus?.running == true ? 'AKTÍV' : 'INDÍTÁS',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (_message != null) ...[
        const SizedBox(height: 10),
        _info(_message!),
      ],
      const SizedBox(height: 12),
      _panel(
        const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: _blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Új fuvarnál hangos push érkezik. Lezárt képernyőn is jelzi, amíg vissza nem igazolod.',
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _trip() {
    final job = _job;
    return _page([
      _header(),
      const SizedBox(height: 16),
      const Text(
        'Fuvarom',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        job == null ? 'Nincs aktív fuvar.' : job.reference,
        style: const TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 14),
      if (job == null)
        _panel(const Text('A következő kiosztott fuvar itt jelenik meg.'))
      else ...[
        ...job.stops.map((stop) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _stopCard(stop),
            )),
        const SizedBox(height: 4),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nyomkövetés',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                _trackingStatus?.lastPosition == null
                    ? 'GPS-pozícióra vár.'
                    : 'Útvonal mentve · utolsó pont elküldve a szervernek.',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 10),
              Text(
                '15 és 30 perc hiteles tétlenségnél a főnökség push értesítést kap. A GPS-zaj nem nullázza az időzítőt.',
                style: const TextStyle(color: Colors.white38, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _quickSignal() => _page([
        _header(),
        const SizedBox(height: 16),
        const Text(
          'Gyors jelzés',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Egy koppintás. A rendszám, fuvar, időpont és GPS-hely automatikusan mellé kerül.',
          style: TextStyle(color: Colors.white54, height: 1.4),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.18,
          children: [
            _signal(Icons.timer_outlined, 'Várakozás', 'Rakodás / telephely',
                () => _sendSignal('Várakozás')),
            _signal(Icons.location_off_outlined, 'Cím / rakodás',
                'Nem található / nem engednek be',
                () => _sendSignal('Cím / rakodás')),
            _signal(Icons.build_outlined, 'Műszaki hiba', 'Autó / gumi / motor',
                () => _sendSignal('Műszaki hiba')),
            _signal(Icons.sos_outlined, 'Sürgős', 'Baleset / azonnali figyelem',
                () => _sendSignal('Baleset / sürgős', urgent: true)),
            _signal(Icons.more_horiz_rounded, 'Egyéb', 'Írd le röviden',
                _otherSignal),
          ],
        ),
      ]);

  Widget _documents() => _page([
        _header(),
        const SizedBox(height: 16),
        const Text(
          'Dokumentum',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Fotózd le, a Flow feldolgozza és továbbítja.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            children: [
              FilledButton.icon(
                onPressed: _openCmrScanner,
                icon: const Icon(Icons.document_scanner_rounded),
                label: const Text('CMR / DOKUMENTUM'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openFuelReceipt,
                icon: const Icon(Icons.local_gas_station_outlined),
                label: const Text('TANKOLÁSI BIZONYLAT'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _blue),
                ),
              ),
            ],
          ),
        ),
      ]);

  Future<void> _otherSignal() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: const Text('Egyéb jelzés'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Mi történt?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('MÉGSE'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('KÜLDÉS'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.isNotEmpty) {
      await _sendSignal('Egyéb', message: text);
    }
  }

  Widget _stopCard(DriverStop stop) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: stop.arrived ? _green.withValues(alpha: .45) : const Color(0xFF173B54),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: stop.arrived
                  ? _green.withValues(alpha: .13)
                  : _blue.withValues(alpha: .13),
              child: Text(
                '${stop.order}',
                style: TextStyle(
                  color: stop.arrived ? _green : _blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.company.isEmpty ? 'Megálló' : stop.company,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stop.address,
                    style: const TextStyle(color: Colors.white54, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stop.arrived
                        ? 'MEGÉRKEZÉS RÖGZÍTVE'
                        : (stop.type == 'delivery' ? 'LERAKÓ' : 'FELRAKÓ'),
                    style: TextStyle(
                      color: stop.arrived ? _green : _blue,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _signal(
    IconData icon,
    String title,
    String detail,
    VoidCallback onTap,
  ) =>
      InkWell(
        onTap: _actionBusy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF173B54)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: title == 'Sürgős' ? Colors.redAccent : _blue),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      );

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xCC081725),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF24557D)),
        ),
        child: child,
      );

  Widget _status(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(
          '● $text',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF06131F),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF173B54)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ],
        ),
      );

  Widget _info(String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.withValues(alpha: .28)),
        ),
        child: Text(value, style: const TextStyle(color: Colors.white70)),
      );
}
