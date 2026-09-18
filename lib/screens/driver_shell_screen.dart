import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/aims_locale.dart';
import '../services/aims_voice_command.dart';
import '../services/aims_voice_service.dart';
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
  static const _prefsDriverName = 'aims_driver_name';
  static const _prefsHandsFree = 'aims_hands_free';

  final _api = const DriverApiService();
  final _tracking = VehicleTrackingService.instance;
  final _push = DriverPushService.instance;
  late final AimsVoiceService _voice;

  StreamSubscription<DriverPushEvent>? _pushSub;
  StreamSubscription<AimsVoiceState>? _voiceSub;
  StreamSubscription<VehicleTrackingStatus>? _trackingSub;

  int _index = 0;
  String _plate = '';
  String _driverName = '';
  List<DriverJob> _jobs = const [];
  bool _loading = true;
  bool _actionBusy = false;
  String? _message;
  VehicleTrackingStatus? _trackingStatus;
  AimsVoiceState _voiceState = const AimsVoiceState(
    enabled: false,
    mode: AimsVoiceMode.off,
    message: 'AIMS Hands-Free kikapcsolva.',
  );
  bool _handsFreeBusy = false;

  DriverJob? get _job => _jobs.isEmpty ? null : _jobs.first;
  DriverStop? get _stop => _job?.currentStop;

  String _l(String hu, String en, String de) => switch (
        AimsLocaleController.instance.languageCode
      ) {
        'en' => en,
        'de' => de,
        _ => hu,
      };

  @override
  void initState() {
    super.initState();
    _voice = AimsVoiceService(
      onCommand: _handleVoiceCommand,
      driverNameProvider: () => _driverName,
    );
    _voiceSub = _voice.states.listen((state) {
      if (mounted) setState(() => _voiceState = state);
    });
    _pushSub = _push.events.listen(_handlePush);
    _trackingSub = _tracking.statusStream.listen((status) {
      if (mounted) setState(() => _trackingStatus = status);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var plate = (prefs.getString(_prefsPlate) ?? '').trim().toUpperCase();
    final driverName = (prefs.getString(_prefsDriverName) ?? '').trim();

    final status = await _tracking.currentStatus();
    if (plate.isEmpty && status.vehicleLabel.trim().isNotEmpty) {
      plate = status.vehicleLabel.trim().toUpperCase();
    }

    if (!mounted) return;
    setState(() {
      _plate = plate;
      _driverName = driverName;
      _trackingStatus = status;
    });

    if (_plate.isEmpty) {
      setState(() {
        _loading = false;
        _message = 'Nincs bejelentkezett rendszám. Lépj be újra.';
      });
    } else {
      await _tracking.setVehicleLabel(_plate);
      await _activateDriverServices();
    }

    final handsFree = prefs.getBool(_prefsHandsFree) ?? false;
    if (handsFree && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_setHandsFree(true));
      });
    }

    final pending = _push.takePendingLaunch();
    if (pending != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePush(pending));
    }
  }

  Future<void> _activateDriverServices() async {
    if (_plate.isEmpty) return;

    String? pushError;
    String? trackingError;

    // Push registration must not depend on location/background permissions.
    try {
      await _push.registerForPlate(_plate);
    } catch (e) {
      pushError = e.toString().replaceFirst('Bad state: ', '');
    }

    try {
      await _tracking.setVehicleLabel(_plate);
      final status = await _tracking.currentStatus();
      if (!status.enabled) {
        await _tracking.enableWithPermission();
      } else {
        await _tracking.startIfEnabled();
      }
    } catch (e) {
      trackingError = e.toString().replaceFirst('Bad state: ', '');
    }

    await _refreshJobs();

    if (!mounted) return;
    final issues = <String>[
      if (pushError != null) 'Push: $pushError',
      if (trackingError != null) 'GPS: $trackingError',
    ];
    if (issues.isNotEmpty) {
      setState(() => _message = issues.join(' • '));
    }
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
    if (stop == null) {
      _snack('Nincs megnyitható következő cím.');
      return;
    }
    await _openMapsForStop(stop);
  }

  Future<void> _openMapsForStop(DriverStop stop) async {
    if (stop.address.trim().isEmpty) {
      _snack('Nincs megnyitható cím.');
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

  DriverStop? _nextStopOfType(String type) {
    final job = _job;
    if (job == null) return null;
    for (final stop in job.stops) {
      if (!stop.completed && stop.type == type) return stop;
    }
    return null;
  }

  Future<String> _markStop(
    DriverStop stop,
    String action, {
    required String expectedType,
  }) async {
    if (stop.type != expectedType) {
      return expectedType == 'pickup'
          ? _l(
              'A következő megálló nem felrakó.',
              'The next stop is not a pickup.',
              'Der nächste Stopp ist keine Abholung.',
            )
          : _l(
              'A következő megálló nem lerakó.',
              'The next stop is not a delivery.',
              'Der nächste Stopp ist keine Zustellung.',
            );
    }
    try {
      await _api.updateStop(
        plate: _plate,
        stopId: stop.id,
        action: action,
        source: 'voice',
      );
      await _refreshJobs();
      if (action == 'arrived') {
        return expectedType == 'pickup'
            ? _l(
                'Megérkezés a felrakóra rögzítve.',
                'Arrival at pickup recorded.',
                'Ankunft an der Ladestelle gespeichert.',
              )
            : _l(
                'Megérkezés a lerakóra rögzítve.',
                'Arrival at delivery recorded.',
                'Ankunft an der Entladestelle gespeichert.',
              );
      }
      return expectedType == 'pickup'
          ? _l(
              'Felrakás kész. Jöhet a következő megálló.',
              'Pickup complete. Ready for the next stop.',
              'Beladung fertig. Weiter zum nächsten Stopp.',
            )
          : _l(
              'Lerakás kész. Rögzítettem.',
              'Delivery complete. Recorded.',
              'Entladung fertig. Gespeichert.',
            );
    } catch (_) {
      return _l(
        'A stop állapotát nem sikerült rögzíteni.',
        'The stop status could not be saved.',
        'Der Stoppstatus konnte nicht gespeichert werden.',
      );
    }
  }

  Future<String> _callCurrentContact() async {
    final stop = _stop;
    if (stop == null) {
      return _l(
        'Nincs aktív megálló.',
        'There is no active stop.',
        'Es gibt keinen aktiven Stopp.',
      );
    }
    final phone = stop.phone.trim();
    if (phone.isEmpty) {
      return _l(
        'Ehhez a megállóhoz nincs telefonszám megadva.',
        'No phone number is available for this stop.',
        'Für diesen Stopp ist keine Telefonnummer hinterlegt.',
      );
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return _l(
        'A telefonhívást nem sikerült elindítani.',
        'The phone call could not be started.',
        'Der Anruf konnte nicht gestartet werden.',
      );
    }
    return _l(
      'Hívom a kapcsolattartót.',
      'Calling the contact person.',
      'Ich rufe den Ansprechpartner an.',
    );
  }

  String _jobVoiceSummary() {
    final job = _job;
    if (job == null) {
      return _l(
        'Nincs aktív fuvar.',
        'There is no active job.',
        'Es gibt keinen aktiven Auftrag.',
      );
    }
    final stop = job.currentStop;
    if (stop == null) {
      return _l(
        'A fuvar minden megállója kész.',
        'All stops on the job are complete.',
        'Alle Stopps des Auftrags sind abgeschlossen.',
      );
    }
    final company = stop.company.trim();
    final companyPart = company.isEmpty ? '' : ' $company.';
    if (AimsLocaleController.instance.languageCode == 'en') {
      final kind = stop.type == 'pickup' ? 'pickup' : 'delivery';
      return 'Active job: ${job.reference}. Next $kind.$companyPart Address: ${stop.address}.';
    }
    if (AimsLocaleController.instance.languageCode == 'de') {
      final kind = stop.type == 'pickup' ? 'Abholung' : 'Zustellung';
      return 'Aktiver Auftrag: ${job.reference}. Nächster Stopp: $kind.$companyPart Adresse: ${stop.address}.';
    }
    final kind = stop.type == 'pickup' ? 'felrakó' : 'lerakó';
    return 'Aktív fuvar: ${job.reference}. Következő $kind.$companyPart Cím: ${stop.address}.';
  }

  Future<String> _handleVoiceCommand(AimsVoiceCommand command) async {
    final current = _stop;
    final noStop = _l(
      'Nincs aktív megálló.',
      'There is no active stop.',
      'Es gibt keinen aktiven Stopp.',
    );

    switch (command.intent) {
      case AimsVoiceIntent.showJob:
        if (mounted) setState(() => _index = 1);
        return _jobVoiceSummary();
      case AimsVoiceIntent.navigatePickup:
        final stop = _nextStopOfType('pickup');
        if (stop == null) {
          return _l('Nincs következő felrakó.', 'There is no next pickup.',
              'Es gibt keine nächste Abholung.');
        }
        await _openMapsForStop(stop);
        return _l('Navigáció indítása a felrakóra.',
            'Starting navigation to the pickup.',
            'Navigation zur Ladestelle wird gestartet.');
      case AimsVoiceIntent.navigateDelivery:
        final stop = _nextStopOfType('delivery');
        if (stop == null) {
          return _l('Nincs következő lerakó.', 'There is no next delivery.',
              'Es gibt keine nächste Zustellung.');
        }
        await _openMapsForStop(stop);
        return _l('Navigáció indítása a lerakóra.',
            'Starting navigation to the delivery.',
            'Navigation zur Entladestelle wird gestartet.');
      case AimsVoiceIntent.arrivePickup:
        if (current == null) return noStop;
        return _markStop(current, 'arrived', expectedType: 'pickup');
      case AimsVoiceIntent.arriveDelivery:
        if (current == null) return noStop;
        return _markStop(current, 'arrived', expectedType: 'delivery');
      case AimsVoiceIntent.pickupComplete:
        if (current == null) return noStop;
        return _markStop(current, 'completed', expectedType: 'pickup');
      case AimsVoiceIntent.deliveryComplete:
        if (current == null) return noStop;
        return _markStop(current, 'completed', expectedType: 'delivery');
      case AimsVoiceIntent.nextAddress:
        if (current == null) {
          return _l('Nincs következő cím.', 'There is no next address.',
              'Es gibt keine nächste Adresse.');
        }
        final company = current.company.trim();
        if (AimsLocaleController.instance.languageCode == 'en') {
          return company.isEmpty
              ? 'The next address is ${current.address}.'
              : 'The next stop is $company. Address: ${current.address}.';
        }
        if (AimsLocaleController.instance.languageCode == 'de') {
          return company.isEmpty
              ? 'Die nächste Adresse ist ${current.address}.'
              : 'Der nächste Stopp ist $company. Adresse: ${current.address}.';
        }
        return company.isEmpty
            ? 'A következő cím: ${current.address}.'
            : 'A következő megálló $company. Cím: ${current.address}.';
      case AimsVoiceIntent.callContact:
        return _callCurrentContact();
      case AimsVoiceIntent.delaySignal:
        await _sendSignal('Késés', message: 'Voice command');
        return _l('A késés jelzést elküldtem a főnökségnek.',
            'The delay notice was sent to the office.',
            'Die Verspätungsmeldung wurde an die Disposition gesendet.');
      case AimsVoiceIntent.fuelReceipt:
        unawaited(_openFuelReceipt());
        return _l('Megnyitottam a tankolási bizonylatot.',
            'I opened the fuel receipt scanner.',
            'Der Tankbeleg-Scanner ist geöffnet.');
      case AimsVoiceIntent.cmrDocument:
        unawaited(_openCmrScanner());
        return _l('Megnyitottam a CMR scannert.',
            'I opened the CMR scanner.', 'Der CMR-Scanner ist geöffnet.');
      case AimsVoiceIntent.technicalIssue:
        await _sendSignal('Műszaki hiba', message: 'Voice command');
        return _l('A műszaki hibát jeleztem a főnökségnek.',
            'The technical issue was reported to the office.',
            'Das technische Problem wurde an die Disposition gemeldet.');
      case AimsVoiceIntent.readJobDetails:
        return _jobVoiceSummary();
      case AimsVoiceIntent.waitingSignal:
        await _sendSignal('Várakozás', message: 'Voice command');
        return _l('A várakozást jeleztem.', 'The waiting status was reported.',
            'Die Wartezeit wurde gemeldet.');
      case AimsVoiceIntent.urgentSignal:
        await _sendSignal('Baleset / sürgős',
            urgent: true, message: 'Voice command');
        return _l('Sürgős jelzést küldtem.', 'I sent an urgent alert.',
            'Ich habe eine dringende Meldung gesendet.');
      case AimsVoiceIntent.unknown:
        return AimsLocaleController.instance.t('not_understood');
    }
  }

  Future<void> _setHandsFree(bool enabled) async {
    if (_handsFreeBusy) return;
    setState(() => _handsFreeBusy = true);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (enabled) {
        final ok = await _voice.enableHandsFree();
        await prefs.setBool(_prefsHandsFree, ok);
        if (!ok && mounted) {
          _snack('A hangfelismerés nem indítható. Ellenőrizd a mikrofon engedélyt.');
        }
      } else {
        await _voice.disableHandsFree();
        await prefs.setBool(_prefsHandsFree, false);
      }
    } finally {
      if (mounted) setState(() => _handsFreeBusy = false);
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
    _voiceSub?.cancel();
    unawaited(_voice.dispose());
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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: AimsLocaleController.instance.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_shipping_outlined),
            selectedIcon: const Icon(Icons.local_shipping),
            label: AimsLocaleController.instance.t('my_job'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.campaign_outlined),
            selectedIcon: const Icon(Icons.campaign),
            label: AimsLocaleController.instance.t('quick_signal'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.description_outlined),
            selectedIcon: const Icon(Icons.description),
            label: AimsLocaleController.instance.t('docs'),
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
          const AimsLanguageSelector(compact: true),
          const SizedBox(width: 8),
          _status(
            _trackingStatus?.running == true
                ? _l('GPS AKTÍV', 'GPS ACTIVE', 'GPS AKTIV')
                : 'GPS',
            _trackingStatus?.running == true ? _green : Colors.white38,
          ),
        ],
      );

  Widget _home() {
    final job = _job;
    final stop = _stop;
    final currentCompany = stop?.company.trim().isNotEmpty == true
        ? stop!.company
        : (job?.reference ??
            _l('Nincs aktív fuvar', 'No active job', 'Kein aktiver Auftrag'));

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
                    ? _l(
                        'Új munka érkezésekor a Flow itt azonnal szól.',
                        'Flow notifies you here immediately when a new job arrives.',
                        'Flow meldet hier sofort einen neuen Auftrag.',
                      )
                    : _l(
                        'AKTÍV FUVAR · ${job.reference} · ${job.stops.length} stop',
                        'ACTIVE JOB · ${job.reference} · ${job.stops.length} stops',
                        'AKTIVER AUFTRAG · ${job.reference} · ${job.stops.length} Stopps',
                      ),
                style: const TextStyle(
                  color: _blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 18),
              if (job == null) ...[
                Text(
                  _l('Nincs teendőd.', 'Nothing to do.', 'Keine Aufgabe.'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _l(
                    'A nyomkövetés és az értesítések a háttérben működnek.',
                    'Tracking and notifications continue in the background.',
                    'Tracking und Benachrichtigungen laufen im Hintergrund.',
                  ),
                  style: const TextStyle(color: Colors.white54, height: 1.35),
                ),
              ] else ...[
                Text(
                  _l('KÖVETKEZŐ LÉPÉS', 'NEXT STEP', 'NÄCHSTER SCHRITT'),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  stop?.type == 'delivery'
                      ? _l(
                          'Indulás a lerakóra',
                          'Go to delivery',
                          'Zur Entladestelle fahren',
                        )
                      : _l(
                          'Indulás a felrakóra',
                          'Go to pickup',
                          'Zur Ladestelle fahren',
                        ),
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
                  label: Text(
                    _l(
                      'NAVIGÁCIÓ INDÍTÁSA',
                      'START NAVIGATION',
                      'NAVIGATION STARTEN',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      _l('JÁRMŰ', 'VEHICLE', 'FAHRZEUG'),
                      _plate.isEmpty ? '—' : _plate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metric(
                      _l('KÖVETÉS', 'TRACKING', 'TRACKING'),
                      _trackingStatus?.running == true
                          ? _l('AKTÍV', 'ACTIVE', 'AKTIV')
                          : _l('INDÍTÁS', 'START', 'STARTEN'),
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
        Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: _blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _l(
                  'Új fuvarnál hangos push érkezik. Lezárt képernyőn is jelzi, amíg vissza nem igazolod.',
                  'A new job triggers an audible push. It also appears on the lock screen until you acknowledge it.',
                  'Bei einem neuen Auftrag kommt eine hörbare Push-Meldung. Sie bleibt auch auf dem Sperrbildschirm sichtbar, bis du sie bestätigst.',
                ),
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _voicePanel(),
    ]);
  }

  Widget _voicePanel() => _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _voiceState.enabled ? Icons.mic_rounded : Icons.mic_off_outlined,
                  color: _voiceState.enabled ? _green : Colors.white38,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AIMS HANDS-FREE',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        _driverName.isEmpty
                            ? 'Ébresztőszó: „AIMS”'
                            : 'Sofőr: $_driverName • ébresztőszó: „AIMS”',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('aims-hands-free-toggle'),
                  value: _voiceState.enabled,
                  onChanged: _handsFreeBusy ? null : _setHandsFree,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _voiceState.message,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            if (_voiceState.lastHeard.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                'Hallottam: ${_voiceState.lastHeard}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handsFreeBusy
                        ? null
                        : () => unawaited(_voice.triggerAssistant()),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('MONDD MOST'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        unawaited(_voice.requestAndroidAssistantRole()),
                    icon: const Icon(Icons.assistant_outlined),
                    label: const Text('ANDROID ASSZISZTENS'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Hands-Free módban a Flow háttérszolgáltatással fut, és az „AIMS” szó után várja a parancsot.',
              style: TextStyle(color: Colors.white38, height: 1.35, fontSize: 10),
            ),
          ],
        ),
      );

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
                    stop.completed
                        ? 'KÉSZ'
                        : stop.arrived
                            ? 'MEGÉRKEZETT'
                            : (stop.type == 'delivery' ? 'LERAKÓ' : 'FELRAKÓ'),
                    style: TextStyle(
                      color: stop.completed || stop.arrived ? _green : _blue,
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
