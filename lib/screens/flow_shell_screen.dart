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
  static const blue = Color(0xFF1CB8FF);
  static const green = Color(0xFF4DE3A4);
  static const amber = Color(0xFFFFC857);
  static const panelColor = Color(0xE6081725);

  static const steps = <String>[
    'Fuvar átvétele',
    'Felrakó megközelítése',
    'Felrakás dokumentálása',
    'Úton a lerakóra',
    'Lerakás dokumentálása',
    'CMR ellenőrzése',
    'Fuvar lezárása',
    'Admin jóváhagyásra vár',
  ];

  final sync = SyncCoordinator.instance;
  final tracking = TrackingRuntime.instance;
  final events = <String>[];
  final checklist = <String, bool>{
    'Jármű külső állapota': false,
    'Gumik és világítás': false,
    'Kötelező felszerelés': false,
    'Fuvarokmányok': false,
    'Rakományrögzítés': false,
  };

  int tab = 0;
  int step = 0;
  int offlineQueue = 0;
  int incidents = 0;
  int proofs = 0;
  int adminMessages = 0;
  bool loading = true;
  bool shiftStarted = false;
  bool online = true;
  DateTime? waitingStartedAt;
  String reference = 'AF-260917-04';
  String origin = 'Győr';
  String destination = 'Brno';
  String priority = 'EXPRESS';
  String driverNote = '';
  Timer? clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync.addListener(_serviceChanged);
    tracking.addListener(_serviceChanged);
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && waitingStartedAt != null) setState(() {});
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([sync.initialize(), tracking.initialize(), _loadState()]);
    if (!mounted) return;
    if (events.isEmpty) events.add(_stamp('AIMS Flow elindult'));
    setState(() => loading = false);
  }

  void _serviceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sync.syncNow());
      unawaited(tracking.syncNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sync.removeListener(_serviceChanged);
    tracking.removeListener(_serviceChanged);
    clock?.cancel();
    super.dispose();
  }

  String _stamp(String text) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)} · $text';
  }

  void _log(String text) {
    setState(() {
      events.insert(0, _stamp(text));
      if (events.length > 100) events.removeRange(100, events.length);
      if (!online) offlineQueue++;
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
      step = ((data['step'] as num?)?.toInt() ?? 0).clamp(0, steps.length - 1).toInt();
      offlineQueue = (data['offlineQueue'] as num?)?.toInt() ?? 0;
      incidents = (data['incidents'] as num?)?.toInt() ?? 0;
      proofs = (data['proofs'] as num?)?.toInt() ?? 0;
      adminMessages = (data['adminMessages'] as num?)?.toInt() ?? 0;
      shiftStarted = data['shiftStarted'] == true;
      online = data['online'] != false;
      reference = data['reference'] as String? ?? reference;
      origin = data['origin'] as String? ?? origin;
      destination = data['destination'] as String? ?? destination;
      priority = data['priority'] as String? ?? priority;
      driverNote = data['driverNote'] as String? ?? '';
      final waiting = data['waitingStartedAt'] as String?;
      waitingStartedAt = waiting == null ? null : DateTime.tryParse(waiting);
      final savedChecklist = data['checklist'];
      if (savedChecklist is Map<String, dynamic>) {
        for (final key in checklist.keys.toList()) {
          checklist[key] = savedChecklist[key] == true;
        }
      }
      final savedEvents = data['events'];
      if (savedEvents is List) events.addAll(savedEvents.whereType<String>().take(100));
    } catch (_) {
      // Corrupt local state must not prevent app startup.
    }
  }

  Future<void> _saveState() async {
    try {
      final file = await _stateFile();
      await file.writeAsString(jsonEncode({
        'step': step,
        'offlineQueue': offlineQueue,
        'incidents': incidents,
        'proofs': proofs,
        'adminMessages': adminMessages,
        'shiftStarted': shiftStarted,
        'online': online,
        'reference': reference,
        'origin': origin,
        'destination': destination,
        'priority': priority,
        'driverNote': driverNote,
        'waitingStartedAt': waitingStartedAt?.toIso8601String(),
        'checklist': checklist,
        'events': events,
      }));
    } catch (_) {
      // Best-effort local persistence.
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _advance() {
    if (!shiftStarted) {
      _snack('Előbb indítsd el a műszakot.');
      return;
    }
    if (step == 0 && checklist.values.any((done) => !done)) {
      _snack('A fuvar indításához töltsd ki a checklistet.');
      return;
    }
    if (step >= steps.length - 1) {
      _snack('A fuvar admin jóváhagyásra vár.');
      return;
    }
    setState(() => step++);
    _log('Fuvarállapot: ${steps[step]}');
  }

  void _toggleShift() {
    setState(() => shiftStarted = !shiftStarted);
    _log(shiftStarted ? 'Műszak elindítva' : 'Műszak lezárva');
  }

  void _toggleConnection() {
    setState(() => online = !online);
    _log(online ? 'Kapcsolat visszatért' : 'Offline mód aktiválva');
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get waitingText => waitingStartedAt == null
      ? 'NINCS'
      : _formatDuration(DateTime.now().difference(waitingStartedAt!));

  void _toggleWaiting() {
    if (waitingStartedAt == null) {
      setState(() => waitingStartedAt = DateTime.now());
      _log('Várakozás indítva');
    } else {
      final duration = DateTime.now().difference(waitingStartedAt!);
      setState(() => waitingStartedAt = null);
      _log('Várakozás lezárva · ${_formatDuration(duration)}');
    }
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
                const Text('A Flow csak teljes ellenőrzés után engedi tovább a fuvar indítását.', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 10),
                ...checklist.keys.map((key) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(key),
                      value: checklist[key],
                      onChanged: (value) {
                        setState(() => checklist[key] = value == true);
                        setSheetState(() {});
                        unawaited(_saveState());
                      },
                    )),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _log(checklist.values.every((v) => v) ? 'Checklist teljesítve' : 'Checklist részben kitöltve');
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

  Future<void> _editFreight() async {
    final ref = TextEditingController(text: reference);
    final from = TextEditingController(text: origin);
    final to = TextEditingController(text: destination);
    final note = TextEditingController(text: driverNote);
    String selectedPriority = priority;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) => AlertDialog(
          title: const Text('Fuvar adatlap'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'Referencia')),
              const SizedBox(height: 10),
              TextField(controller: from, decoration: const InputDecoration(labelText: 'Felrakó')),
              const SizedBox(height: 10),
              TextField(controller: to, decoration: const InputDecoration(labelText: 'Lerakó')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedPriority,
                decoration: const InputDecoration(labelText: 'Prioritás'),
                items: const [
                  DropdownMenuItem(value: 'EXPRESS', child: Text('Express')),
                  DropdownMenuItem(value: 'DEDICATED', child: Text('Dedicated')),
                  DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
                ],
                onChanged: (value) => localSetState(() => selectedPriority = value ?? selectedPriority),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Sofőr megjegyzés')),
            ]),
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
        if (ref.text.trim().isNotEmpty) reference = ref.text.trim();
        if (from.text.trim().isNotEmpty) origin = from.text.trim();
        if (to.text.trim().isNotEmpty) destination = to.text.trim();
        priority = selectedPriority;
        driverNote = note.text.trim();
      });
      _log('Fuvar adatlap frissítve');
    }
    ref.dispose();
    from.dispose();
    to.dispose();
    note.dispose();
  }

  Future<void> _reportIncident() async {
    final note = TextEditingController();
    String type = 'Várakozás';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) => AlertDialog(
          title: const Text('Incidens jelentése'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              items: const [
                DropdownMenuItem(value: 'Várakozás', child: Text('Várakozás')),
                DropdownMenuItem(value: 'Sérülés', child: Text('Sérülés')),
                DropdownMenuItem(value: 'Címhiba', child: Text('Címhiba')),
                DropdownMenuItem(value: 'Műszaki hiba', child: Text('Műszaki hiba')),
                DropdownMenuItem(value: 'Egyéb', child: Text('Egyéb')),
              ],
              onChanged: (value) => localSetState(() => type = value ?? type),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, maxLines: 4, decoration: const InputDecoration(labelText: 'Leírás')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rögzítés')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() => incidents++);
      final suffix = note.text.trim().isEmpty ? '' : ' · ${note.text.trim()}';
      _log('Incidens: $type$suffix');
    }
    note.dispose();
  }

  void _createProof() {
    setState(() => proofs++);
    _log('Bizonyítékcsomag #$proofs rögzítve');
  }

  Future<void> _manualSync() async {
    if (!online) {
      _snack('Offline módban az események helyben tárolódnak.');
      return;
    }
    await sync.syncNow();
    await tracking.syncNow();
    setState(() => offlineQueue = 0);
    _log('Kézi szinkron lefutott');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: blue)));
    }
    return Scaffold(
      body: IndexedStack(index: tab, children: [_operations(), const HomeScreen(), _flow()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        backgroundColor: const Color(0xFF030D16),
        indicatorColor: blue.withValues(alpha: .18),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'FUVAR'),
          NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner), label: 'SCANNER'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'FLOW'),
        ],
      ),
    );
  }

  Widget _operations() {
    final done = checklist.values.where((v) => v).length;
    final progress = (step + 1) / steps.length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)]),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _manualSync,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              Row(children: [
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('AIMS FLOW', style: TextStyle(letterSpacing: 3.5, color: Colors.white60, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('DRIVER OPERATIONS', style: TextStyle(fontSize: 10, color: blue, fontWeight: FontWeight.w800)),
                ])),
                InkWell(onTap: _toggleConnection, borderRadius: BorderRadius.circular(99), child: _status(online ? 'ONLINE' : 'OFFLINE', online ? green : amber)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _toggleShift, icon: Icon(shiftStarted ? Icons.stop_circle_outlined : Icons.play_circle_outline), label: Text(shiftStarted ? 'MŰSZAK LEZÁRÁSA' : 'MŰSZAK INDÍTÁSA'))),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _editFreight, tooltip: 'Fuvar szerkesztése', icon: const Icon(Icons.edit_note_rounded)),
              ]),
              const SizedBox(height: 14),
              _panelBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('$priority · $reference', style: const TextStyle(color: blue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2))),
                  Text('${step + 1}/${steps.length}', style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Text(steps[step], style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(driverNote.isEmpty ? 'A Flow az aktuális fuvarállapotból adja a következő teendőt.' : driverNote, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_RoutePoint(origin.toUpperCase(), 'Felrakó'), const Icon(Icons.arrow_forward_rounded, color: blue), _RoutePoint(destination.toUpperCase(), 'Lerakó')]),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: const BorderRadius.all(Radius.circular(99))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _metric('GPS', tracking.active ? 'AKTÍV' : 'KÉSZ')),
                  const SizedBox(width: 8),
                  Expanded(child: _metric('CHECK', '$done/${checklist.length}')),
                  const SizedBox(width: 8),
                  Expanded(child: _metric('QUEUE', '$offlineQueue')),
                ]),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _advance, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('FUVAR FOLYTATÁSA')),
              ])),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _summary(Icons.route_rounded, 'ÁLLAPOT', step >= 6 ? 'ZÁRÁS' : 'FOLYAMATBAN')),
                const SizedBox(width: 8),
                Expanded(child: _summary(Icons.timer_outlined, 'VÁRAKOZÁS', waitingText)),
                const SizedBox(width: 8),
                Expanded(child: _summary(Icons.shield_outlined, 'BIZONYÍTÉK', '$proofs')),
              ]),
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
                  _action(Icons.gps_fixed, 'Élő GPS', tracking.active ? 'Aktív fuvar követése.' : 'Valós helyadatok és fuvarút.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen()))),
                  _action(Icons.fact_check_outlined, 'Checklist', '$done/${checklist.length} ellenőrzés kész.', _openChecklist),
                  _action(Icons.warning_amber_rounded, 'Incidens', '$incidents rögzített esemény.', _reportIncident),
                  _action(Icons.timer_outlined, 'Várakozás', waitingStartedAt == null ? 'Állásidő indítása.' : 'Fut: $waitingText', _toggleWaiting),
                  _action(Icons.photo_library_outlined, 'Bizonyíték', '$proofs csomag · CMR + GPS + idő.', _createProof),
                  _action(Icons.mark_unread_chat_alt_outlined, 'Admin', adminMessages == 0 ? 'Nincs új üzenet.' : '$adminMessages új üzenet.', () => _log('Admin kommunikáció megnyitva')),
                  _action(Icons.sos_outlined, 'SOS', 'Gyors segítségkérés admin felé.', () {
                    setState(() => incidents++);
                    _log('SOS segítségkérés rögzítve');
                  }),
                  _action(Icons.sync_rounded, 'Szinkron', online ? 'Adatok naprakészek.' : 'Offline sor: $offlineQueue', _manualSync),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flow() {
    final deviceText = switch (sync.deviceState) {
      'approved' => 'Jóváhagyva',
      'revoked' => 'Visszavonva',
      _ => 'Függőben',
    };
    return Container(
      color: const Color(0xFF020813),
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(18), children: [
          const Text('FLOW', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Fuvar eseménynapló, offline állapot és rendszerdiagnosztika', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          _panelBox(Column(children: [
            _health(Icons.gps_fixed, 'GPS', tracking.active ? 'Aktív' : 'Kész', green),
            _health(Icons.cloud_done_outlined, 'Kapcsolat', online ? 'Online' : 'Offline', online ? green : amber),
            _health(Icons.storage_outlined, 'Offline sor', '$offlineQueue', offlineQueue == 0 ? green : amber),
            _health(Icons.verified_user_outlined, 'Admin eszköz', deviceText, sync.deviceState == 'revoked' ? Colors.redAccent : green),
            _health(Icons.document_scanner_outlined, 'CMR motor', 'Kész', green),
            _health(Icons.fact_check_outlined, 'Checklist', '${checklist.values.where((v) => v).length}/${checklist.length}', green),
          ])),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () {
              setState(events.clear);
              unawaited(_saveState());
            }, icon: const Icon(Icons.delete_sweep_outlined), label: const Text('NAPLÓ TÖRLÉSE'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _saveState, icon: const Icon(Icons.save_outlined), label: const Text('MENTÉS'))),
          ]),
          const SizedBox(height: 14),
          if (events.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nincs esemény.', style: TextStyle(color: Colors.white38))))
          else
            ...events.map((event) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFF081725), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF173B54))),
                  child: Row(children: [const Icon(Icons.bolt_rounded, color: blue, size: 18), const SizedBox(width: 10), Expanded(child: Text(event, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                )),
        ]),
      ),
    );
  }

  Widget _panelBox(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF24557D))),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11))]),
      );

  Widget _summary(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF071725), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF173B54))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: blue, size: 18), const SizedBox(height: 7), Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))]),
      );

  Widget _action(IconData icon, String title, String detail, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF071725), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF173B54))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: blue, size: 21), const Spacer(), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 9))]),
        ),
      );

  Widget _health(IconData icon, String title, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [Icon(icon, color: blue), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900))]),
      );
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint(this.city, this.label);
  final String city;
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(city, style: const TextStyle(fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10))]);
}
