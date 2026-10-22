import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/tracking_platform.dart';
import '../services/vehicle_tracking_service.dart';
import 'flow_sync_details_screen.dart';

class FlowTrackingSettingsScreen extends StatefulWidget {
  const FlowTrackingSettingsScreen({super.key, required this.translate});
  final FlowSyncTranslate translate;
  @override
  State<FlowTrackingSettingsScreen> createState() => _FlowTrackingSettingsScreenState();
}

class _FlowTrackingSettingsScreenState extends State<FlowTrackingSettingsScreen>
    with WidgetsBindingObserver {
  final _tracking = VehicleTrackingService.instance;
  VehicleTrackingStatus? _status;
  Map<String, dynamic> _device = {};
  LocationPermission? _permission;
  LocationAccuracyStatus? _accuracy;
  bool? _locationEnabled;
  bool _busy = false;
  String? _error;
  FlowSyncTranslate get _l => widget.translate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh({bool retry = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (retry) await _tracking.enableWithPermission();
      final status = await _tracking.currentStatus();
      final permission = await Geolocator.checkPermission();
      final enabled = await Geolocator.isLocationServiceEnabled();
      final accuracy = await Geolocator.getLocationAccuracy();
      final device = await TrackingPlatform.readiness();
      if (mounted) setState(() {
        _status = status; _permission = permission; _locationEnabled = enabled;
        _accuracy = accuracy; _device = device;
      });
    } catch (_) {
      if (mounted) setState(() => _error = _l('Az állapot nem olvasható. Próbáld újra.',
        'Status unavailable. Try again.', 'Status nicht verfügbar. Erneut versuchen.'));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _settings({bool battery = false, bool location = false}) async {
    try {
      final opened = location ? await Geolocator.openLocationSettings() :
          await TrackingPlatform.openSettings(battery: battery);
      if (!opened) throw StateError('unavailable');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l(
        'Nyisd meg a telefon Beállítások → Alkalmazások → AIMS FLOW menüjét.',
        'Open phone Settings → Apps → AIMS FLOW.',
        'Öffne Einstellungen → Apps → AIMS FLOW.'))));
    }
  }

  Widget _row(String title, String detail, bool? good, {VoidCallback? action}) =>
      Card(child: ListTile(contentPadding: const EdgeInsets.all(14),
        leading: Icon(good == null ? Icons.help_outline : good ? Icons.check_circle_outline : Icons.info_outline,
          color: good == true ? Colors.green : Theme.of(context).colorScheme.primary),
        title: Text(title), subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(detail)),
        trailing: action == null ? null : const Icon(Icons.chevron_right), onTap: action));

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final granted = _permission == LocationPermission.always || _permission == LocationPermission.whileInUse;
    final fresh = s?.lastFixAt != null && DateTime.now().difference(s!.lastFixAt!) <
        Duration(seconds: s.stationary ? 210 : 120);
    return Scaffold(appBar: AppBar(title: Text(_l('Megbízható követés', 'Reliable tracking', 'Zuverlässige Ortung')),
      actions: [IconButton(onPressed: _busy ? null : () => _refresh(), icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_l('A követés az aktív munkanap alatt működik, lezáráskor leáll.',
          'Tracking runs during the active workday and stops when it is closed.',
          'Die Ortung läuft während des aktiven Arbeitstags und endet beim Abschluss.')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!)),
        const SizedBox(height: 12),
        _row(_l('Nyomkövetés', 'Tracking', 'Ortung'), s == null ? '—' :
          !s.enabled ? _l('Várakozás az aktív munkanapra.', 'Waiting for an active workday.', 'Warten auf einen aktiven Arbeitstag.') :
          s.running && fresh ? (s.stationary ? _l('Állás érzékelve · takarékos rögzítés.',
            'Stationary · reduced recording.', 'Stillstand · reduzierte Aufzeichnung.') :
            _l('Aktív · friss GPS-helyzet.', 'Active · fresh GPS position.', 'Aktiv · aktuelle GPS-Position.')) :
          _l('Friss GPS-helyzetre vár. Ellenőrizd az alábbi beállításokat.',
            'Waiting for a fresh GPS position. Check the settings below.',
            'Warten auf eine aktuelle GPS-Position. Einstellungen unten prüfen.'),
          s == null ? null : s.running && fresh),
        _row(_l('Pontos helymeghatározás', 'Precise location', 'Genauer Standort'),
          _l('A telefon helymeghatározása és a pontos helyengedély legyen bekapcsolva.',
            'Enable location services and precise location permission.',
            'Standortdienste und die Berechtigung für den genauen Standort aktivieren.'),
          _locationEnabled == null ? null : _locationEnabled! && granted && _accuracy == LocationAccuracyStatus.precise,
          action: () => _settings(location: _locationEnabled == false)),
        _row(_l('Helyhozzáférés mindig', 'Always allow location', 'Standort immer erlauben'),
          _l('Engedélyezd a helyhozzáférést mindig, hogy a GPS a háttérben is újraindulhasson. A munkanapon kívül nem követünk.',
            'Allow location all the time so GPS can recover in the background. Tracking remains limited to the workday.',
            'Standort immer erlauben, damit GPS im Hintergrund wieder anlaufen kann. Ortung nur während des Arbeitstags.'),
          _permission == null ? null : _permission == LocationPermission.always, action: () => _settings()),
        _row(_l('Akkumulátor és háttérfutás', 'Battery and background activity', 'Akku und Hintergrundaktivität'),
          Platform.isIOS ? _l(
            'iPhone-on engedélyezd a Mindig és a Pontos hely beállítást. A munkanap előtt nyisd meg az appot. Alacsony töltöttségnél az iOS korlátozhatja a háttérműveleteket.',
            'On iPhone enable Always and Precise Location. Open the app before the workday. Low Power Mode may limit background activity.',
            'Auf dem iPhone Immer und Genauer Standort aktivieren. Vor dem Arbeitstag die App öffnen. Der Stromsparmodus kann Hintergrundaktivität begrenzen.') :
          _l('Ha a telefon leállítja a követést: az AIMS FLOW akkumulátorhasználata legyen „Korlátlan”, és ne kerüljön alvó alkalmazások közé.',
            'If the phone stops tracking, set AIMS FLOW battery use to Unrestricted and exclude it from sleeping apps.',
            'Wenn das Telefon die Ortung beendet: Akkunutzung für AIMS FLOW auf Uneingeschränkt stellen und nicht in Standby-Apps aufnehmen.'),
          _device.isEmpty ? null : _device['batteryOptimized'] != true &&
            _device['backgroundRestricted'] != true && _device['powerSave'] != true,
          action: () => _settings(battery: true)),
        _row(Platform.isIOS ? _l('Értesítések', 'Notifications', 'Mitteilungen') : _l('Látható követési értesítés', 'Visible tracking notification', 'Sichtbare Ortungsbenachrichtigung'),
          Platform.isIOS ? _l('A háttérkövetést az iOS helyzetjelzője mutatja. A fuvarértesítésekhez külön push-beállítás kell.', 'iOS shows its location indicator during background tracking. Job alerts require push configuration.', 'iOS zeigt die Standortanzeige bei Hintergrundortung. Auftragsmeldungen benötigen eine Push-Konfiguration.') :
          _l('Az értesítésből visszanyithatod az alkalmazást.', 'Reopen the app from its notification.',
            'Die App kann über die Benachrichtigung geöffnet werden.'),
          _device['notifications'] as bool?, action: () => _settings()),
        if (s != null) _row(_l('Mentett GPS-adatok', 'Saved GPS data', 'Gespeicherte GPS-Daten'),
          '${s.queueDepth} ${_l('pont vár küldésre.', 'point(s) waiting to upload.', 'Punkt(e) warten auf Übertragung.')}\n'
          '${Platform.isIOS ? _l('iOS: 10 méteres elmozdulásszűrés; az időközt a rendszer szabályozza.', 'iOS: 10 m displacement filter; timing is controlled by the system.', 'iOS: 10-m-Bewegungsfilter; Zeitabstand durch das System.') : '${_l('Kért mérési időköz', 'Requested sampling interval', 'Angefordertes Messintervall')}: ${s.sampleSeconds} s'}', true),
        if (s?.lastError != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(s!.lastError!)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : () => _refresh(retry: true), icon: const Icon(Icons.gps_fixed),
          label: Text(_l('Követés ellenőrzése és indítása', 'Check and start tracking', 'Ortung prüfen und starten'))),
        const SizedBox(height: 16),
        Text(_l('Kényszerített leállítás, kikapcsolt telefon vagy visszavont engedély után nyisd meg újra az appot. '
          'A helymeghatározás energiát használ; a tényleges fogyasztás a telefontól és a térerőtől függ.',
          'After force-stop, power-off or permission revocation, reopen the app. Location uses energy; '
          'actual consumption depends on the phone and signal.',
          'Nach erzwungenem Stopp, Ausschalten oder Berechtigungsentzug die App erneut öffnen. '
          'Ortung verbraucht Energie; der Verbrauch hängt vom Telefon und Empfang ab.')),
      ])));
  }
}
