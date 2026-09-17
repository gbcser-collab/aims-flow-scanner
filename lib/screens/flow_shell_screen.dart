import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/sync_coordinator.dart';
import '../services/tracking_runtime.dart';
import 'home_screen.dart';
import 'tracking_screen.dart';

class FlowShellScreen extends StatefulWidget {
  const FlowShellScreen({super.key});

  @override
  State<FlowShellScreen> createState() => _FlowShellScreenState();
}

class _FlowShellScreenState extends State<FlowShellScreen>
    with WidgetsBindingObserver {
  static const _blue = Color(0xFF1CB8FF);
  static const _green = Color(0xFF4DE3A4);
  static const _amber = Color(0xFFFFC857);
  static const _panel = Color(0xE6081725);

  final _sync = SyncCoordinator.instance;
  final _tracking = TrackingRuntime.instance;

  int _index = 0;
  int _step = 0;
  bool _loading = true;
  bool _shiftStarted = false;
  bool _online = true;
  DateTime? _waitingStartedAt;
  int _offlineQueue = 0;
  int _incidentCount = 0;
  int _proofCount = 0;
  int _adminMessages = 0;
  String _reference = 'AF-260917-04';
  String _origin = 'Győr';
  String _destination = 'Brno';
  String _priority = 'EXPRESS';
  String _driverNote = '';

  final Map<String, bool> _checklist = {
    'Jármű külső állapota': false,
    'Gumik és világítás': false,
    'Kötelező felszerelés': false,
    'Fuvarokmányok': false,
    'Rakományrögzítés': false,
  };

  final List<String> _events = [];
  Timer? _clock;

  static const List<String> _steps = [
    'Fuvar átvétele',
    'Felrakó megközelítése',
    'Felrakás dokumentálása',
    'Úton a lerakóra',
    'Lerakás dokumentálása',
    'CMR ellenőrzése',
    'Fuvar lezárása',
    'Admin jóváhagyásra vár',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync.addListener(_serviceChanged);
    _tracking.addListener(_serviceChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _waitingStartedAt != null) setState(() {});
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([
      _sync.initialize(),
      _tracking.initialize(),
      _loadState(),
    ]);
    if (!mounted) return;
    if (_events.isEmpty) {
      _events.add(_eventText('AIMS Flow műveleti rendszer elindult'));
    }
    setState(() => _loading = false);
  }

  void _serviceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sync.syncNow());
      unawaited(_tracking.syncNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_serviceChanged);
    _tracking.removeListener(_serviceChanged);
    _clock?.cancel();
    super.dispose();
  }

  String _eventText(String value) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)} · $value';
  }

  void _log(String value) {
    setState(() {
      _events.insert(0, _eventText(value));
      if (_events.length > 100) _events.removeRange(100, _events.length);
      if (!_online) _offlineQueue++;
    });
    unawaited(_saveState());
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/aims_flow_state.json');
  }

  Future<void> _loadState() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _step = (data['step'] as num?)?.toInt().clamp(0, _steps.length - 1) ?? 0;
      _shiftStarted = data['shiftStarted'] == true;
      _online = data['online'] != false;
      _offlineQueue = (data['offlineQueue'] as num?)?.toInt() ?? 0;
      _incidentCount = (data['incidentCount'] as num?)?.toInt() ?? 0;
      _proofCount = (data['proofCount'] as num?)?.toInt() ?? 0;
      _adminMessages = (data['adminMessages'] as num?)?.toInt() ?? 0;
      _reference = data['reference'] as String? ?? _reference;
      _origin = data['origin'] as String? ?? _origin;
      _destination = data['destination'] as String? ?? _destination;
      _priority = data['priority'] as String? ?? _priority;
      _driverNote = data['driverNote'] as String? ?? '';
      final waiting = data['waitingStartedAt'] as String?;
      _waitingStartedAt = waiting == null ? null : DateTime.tryParse(waiting);
      final rawChecklist = data['checklist'];
      if (rawChecklist is Map<String, dynamic>) {
        for (final key in _checklist.keys.toList()) {
          _checklist[key] = rawChecklist[key] == true;
        }
      }
      final rawEvents = data['events'];
      if (rawEvents is List) {
        _events
          ..clear()
          ..addAll(rawEvents.whereType<String>().take(100));
      }
    } catch (_) {
      // Corrupt local state must never block the driver app.
    }
  }

  Future<void> _saveState() async {
    try {
      final file = await _stateFile();
      await file.writeAsString(jsonEncode({
        'step': _step,
        'shiftStarted': _shiftStarted,
        'online': _online,
        'offlineQueue': _offlineQueue,
        'incidentCount': _incidentCount,
        'proofCount': _proofCount,
        'adminMessages': _adminMessages,
        'reference': _reference,
        'origin': _origin,
        'destination': _destination,
        'priority': _priority,
        'driverNote': _driverNote,
        'waitingStartedAt': _waitingStartedAt?.toIso8601String(),
        'checklist': _checklist,
        'events': _events,
      }));
    } catch (_) {
      // Best-effort persistence. Operational UI remains usable offline.
    }
  }

  void _advance() {
    if (!_shiftStarted) {
      _snack('Előbb indítsd el a műszakot.');
      return;
    }
    if (_step == 0 && _checklist.values.any((done) => !done)) {
      _snack('A fuvar indításához töltsd ki a sofőr checklistet.');
      return;
    }
    if (_step >= _steps.length - 1) {
      _snack('A fuvar admin jóváhagyásra vár.');
      return;
    }
    setState(() => _step++);
    _log('Fuvarállapot: ${_steps[_step]}');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editFreight() async {
    final ref = TextEditingController(text: _reference);
    final from = TextEditingController(text: _origin);
    final to = TextEditingController(text: _destination);
    final note = TextEditingController(text: _driverNote);
    String priority = _priority;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Fuvar adatlap'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: ref, decoration: const InputDecoration(labelText: 'Referencia')),
                const SizedBox(height: 10),
                TextField(controller: from, decoration: const InputDecoration(labelText: 'Felrakó')),
                const SizedBox(height: 10),
                TextField(controller: to, decoration: const InputDecoration(labelText: 'Lerakó')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Prioritás'),
                  items: const [
                    DropdownMenuItem(value: 'EXPRESS', child: Text('Express')),
                    DropdownMenuItem(value: 'DEDICATED', child: Text('Dedicated')),
                    DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
                  ],
                  onChanged: (value) => setLocalState(() => priority = value ?? priority),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Sofőr megjegyzés'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mentés')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        _reference = ref.text.trim().isEmpty ? _reference : ref.text.trim();
        _origin = from.text.trim().isEmpty ? _origin : from.text.trim();
        _destination = to.text.trim().isEmpty ? _destination : to.text.trim();
        _priority = priority;
        _driverNote = note.text.trim();
      });
      _log('Fuvar adatlap frissítve');
    }
    ref.dispose();
    from.dispose();
    to.dispose();
    note.dispose();
  }

  Future<void> _openChecklist() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sofőr checklist', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('A fuvar első indítását csak teljes ellenőrzés után engedi a Flow.', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 12),
                ..._checklist.keys.map((key) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(key),
                      value: _checklist[key],
                      onChanged: (value) {
                        setState(() => _checklist[key] = value == true);
                        setSheetState(() {});
                        unawaited(_saveState());
                      },
                    )),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _log(_checklist.values.every((v) => v) ? 'Checklist teljesítve' : 'Checklist részben kitöltve');
                  },
                  child: const Text('ELLENŐRZÉS MENTÉSE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reportIncident() async {
    final note = TextEditingController();
    String type = 'Várakozás';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Incidens jelentése'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'Várakozás', child: Text('Várakozás')),
                  DropdownMenuItem(value: 'Sérülés', child: Text('Sérülés')),
                  DropdownMenuItem(value: 'Címhiba', child: Text('Címhiba')),
                  DropdownMenuItem(value: 'Műszaki hiba', child: Text('Műszaki hiba')),
                  DropdownMenuItem(value: 'Egyéb', child: Text('Egyéb')),
                ],
                onChanged: (value) => setLocalState(() => type = value ?? type),
              ),
              const SizedBox(height: 12),
              TextField(controller: note, maxLines: 4, decoration: const InputDecoration(labelText: 'Leírás')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rögzítés')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() => _incidentCount++);
      final suffix = note.text.trim().isEmpty ? '' : ' · ${note.text.trim()}';
      _log('Incidens: $type$suffix');
    }
    note.dispose();
  }

  void _toggleWaiting() {
    if (_waitingStartedAt == null) {
      setState(() => _waitingStartedAt = DateTime.now());
      _log('Várakozás indítva');
    } else {
      final duration = DateTime.now().difference(_waitingStartedAt!);
      setState(() => _waitingStartedAt = null);
      _log('Várakozás lezárva · ${_formatDuration(duration)}');
    }
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get _waitingText {
    final start = _waitingStartedAt;
    if (start == null) return 'NINCS';
    return _formatDuration(DateTime.now().difference(start));
  }

  void _toggleShift() {
    setState(() => _shiftStarted = !_shiftStarted);
    _log(_shiftStarted ? 'Műszak elindítva' : 'Műszak lezárva');
  }

  void _toggleConnection() {
    setState(() {
      _online = !_online;
      if (_online && _offlineQueue > 0) {
        _events.insert(0, _eventText('Kapcsolat visszatért · $_offlineQueue offline esemény szinkronra kész'));
      }
    });
    unawaited(_saveState());
  }

  void _createProof() {
    setState(() => _proofCount++);
    _log('Bizonyítékcsomag #$_proofCount rögzítve');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _blue)));
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _operations(),
          const HomeScreen(),
          _flow(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: const Color(0xFF030D16),
        indicatorColor: _blue.withValues(alpha: .18),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'FUVAR'),
          NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner), label: 'SCANNER'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'FLOW'),
        ],
      ),
    );
  }

  Widget _operations() {
    final checklistDone = _checklist.values.where((value) => value).length;
    final progress = (_step + 1) / _steps.length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _sync.syncNow();
            await _tracking.syncNow();
            if (_online && _offlineQueue > 0) {
              setState(() => _offlineQueue = 0);
              _log('Offline sor szinkronizálva');
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AIMS FLOW', style: TextStyle(letterSpacing: 3.5, color: Colors.white60, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('DRIVER OPERATIONS', style: TextStyle(fontSize: 10, color: _blue, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _toggleConnection,
                    borderRadius: BorderRadius.circular(99),
                    child: _status(_online ? 'ONLINE' : 'OFFLINE', _online ? _green : _amber),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toggleShift,
                      icon: Icon(_shiftStarted ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                      label: Text(_shiftStarted ? 'MŰSZAK LEZÁRÁSA' : 'MŰSZAK INDÍTÁSA'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _editFreight, tooltip: 'Fuvar szerkesztése', icon: const Icon(Icons.edit_note_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('$_priority · $_reference', style: const TextStyle(color: _blue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2))),
                        Text('${(_step + 1)}/${_steps.length}', style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_steps[_step], style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(_driverNote.isEmpty ? 'A Flow az aktuális fuvarállapotból adja a következő teendőt.' : _driverNote, style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoutePoint(_origin.toUpperCase(), 'Felrakó'),
                        const Icon(Icons.arrow_forward_rounded, color: _blue),
                        _RoutePoint(_destination.toUpperCase(), 'Lerakó'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: const BorderRadius.all(Radius.circular(99))),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _metric('GPS', _tracking.active ? 'AKTÍV' : 'KÉSZ')),
                        const SizedBox(width: 8),
                        Expanded(child: _metric('CHECK', '$checklistDone/${_checklist.length}')),
                        const SizedBox(width: 8),
                        Expanded(child: _metric('QUEUE', '$_offlineQueue')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(onPressed: _advance, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('FUVAR FOLYTATÁSA')),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _summaryStrip(),
              const SizedBox(height: 16),
              const Text('MŰVELETI KÖZPONT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                childAspectRatio: 1.34,
                children: [
                  _action(Icons.gps_fixed, 'Élő GPS', _tracking.active ? 'Aktív fuvar követése.' : 'Valós helyadatok és fuvarút.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen()))),
                  _action(Icons.fact_check_outlined, 'Checklist', '$checklistDone/${_checklist.length} ellenőrzés kész.', _openChecklist),
                  _action(Icons.warning_amber_rounded, 'Incidens', '$_incidentCount rögzített esemény.', _reportIncident),
                  _action(Icons.timer_outlined, 'Várakozás', _waitingStartedAt == null ? 'Állásidő indítása.' : 'Fut: $_waitingText', _toggleWaiting),
                  _action(Icons.photo_library_outlined, 'Bizonyíték', '$_proofCount csomag · CMR + GPS + idő.', _createProof),
                  _action(Icons.mark_unread_chat_alt_outlined, 'Admin', _adminMessages == 0 ? 'Nincs új üzenet.' : '$_adminMessages új üzenet.', () => _log('Admin kommunikáció megnyitva')),
                  _action(Icons.sos_outlined, 'SOS', 'Gyors segítségkérés admin felé.', () {
                    setState(() => _incidentCount++);
                    _log('SOS segítségkérés rögzítve');
                  }),
                  _action(Icons.sync_rounded, 'Szinkron', _online ? 'Adatok naprakészek.' : 'Offline sor: $_offlineQueue', () async {
                    if (!_online) {
                      _snack('Offline módban a rendszer helyben tárol.');
                      return;
                    }
                    await _sync.syncNow();
                    await _tracking.syncNow();
                    setState(() => _offlineQueue = 0);
                    _log('Kézi szinkron lefutott');
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryStrip() {
    return Row(
      children: [
        Expanded(child: _miniSummary(Icons.route_rounded, 'ÁLLAPOT', _step >= 6 ? 'ZÁRÁS' : 'FOLYAMATBAN')),
        const SizedBox(width: 8),
        Expanded(child: _miniSummary(Icons.timer_outlined, 'VÁRAKOZÁS', _waitingText)),
        const SizedBox(width: 8),
        Expanded(child: _miniSummary(Icons.shield_outlined, 'BIZONYÍTÉK', '$_proofCount')),
      ],
    );
  }

  Widget _flow() {
    final deviceState = _sync.deviceState;
    final deviceText = switch (deviceState) {
      'approved' => 'Jóváhagyva',
      'revoked' => 'Visszavonva',
      _ => 'Függőben',
    };
    return Container(
      color: const Color(0xFF020813),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('FLOW', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Fuvar eseménynapló, offline állapot és rendszerdiagnosztika', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _panel(Column(children: [
              _health(Icons.gps_fixed, 'GPS', _tracking.active ? 'Aktív' : 'Kész', _green),
              _health(Icons.cloud_done_outlined, 'Kapcsolat', _online ? 'Online' : 'Offline', _online ? _green : _amber),
              _health(Icons.storage_outlined, 'Offline sor', '$_offlineQueue', _offlineQueue == 0 ? _green : _amber),
              _health(Icons.verified_user_outlined, 'Admin eszköz', deviceText, deviceState == 'revoked' ? Colors.redAccent : _green),
              _health(Icons.document_scanner_outlined, 'CMR motor', 'Kész', _green),
              _health(Icons.fact_check_outlined, 'Checklist', '${_checklist.values.where((v) => v).length}/${_checklist.length}', _green),
            ])),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _events.clear()), icon: const Icon(Icons.delete_sweep_outlined), label: const Text('NAPLÓ TÖRLÉSE'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _saveState, icon: const Icon(Icons.save_outlined), label: const Text('MENTÉS'))),
              ],
            ),
            const SizedBox(height: 14),
            if (_events.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nincs esemény.', style: TextStyle(color: Colors.white38))))
            else
              ..._events.map((event) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF081725), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF173B54))),
                    child: Row(children: [const Icon(Icons.bolt_rounded, color: _blue, size: 18), const SizedBox(width: 10), Expanded(child: Text(event, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF24557D))),
        child: child,
      );

  Widget _status(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: .35))),
        child: Text('● $text', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      );

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF06131F), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFF173B54))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
        ]),
      );

  Widget _miniSummary(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF071725), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF173B54))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _blue, size: 18),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _action(IconData icon, String title, String detail, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF071725), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF173B54))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _blue, size: 21),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ]),
        ),
      );

  Widget _health(IconData icon, String title, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(icon, color: _blue),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint(this.city, this.label);

  final String city;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(city, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
}
