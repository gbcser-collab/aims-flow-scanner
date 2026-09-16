import 'dart:async';

import 'package:flutter/material.dart';

import '../models/freight_models.dart';
import '../services/driver_flow_controller.dart';
import '../services/sync_coordinator.dart';
import '../services/tracking_runtime.dart';
import 'home_screen.dart';
import 'tracking_screen.dart';

class FlowShellScreen extends StatefulWidget {
  const FlowShellScreen({super.key});

  @override
  State<FlowShellScreen> createState() => _FlowShellScreenState();
}

class _FlowShellScreenState extends State<FlowShellScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _green = Color(0xFF4DE3A4);
  static const _amber = Color(0xFFFFC857);
  static const _red = Color(0xFFFF657A);

  final _flow = DriverFlowController.instance;
  final _sync = SyncCoordinator.instance;
  final _tracking = TrackingRuntime.instance;

  int _index = 0;
  String _eventFilter = 'all';
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _flow.addListener(_changed);
    _sync.addListener(_changed);
    _tracking.addListener(_changed);
    unawaited(_flow.initialize());
    unawaited(_sync.initialize());
    unawaited(_tracking.initialize());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _flow.state.waitingActive) setState(() {});
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _flow.removeListener(_changed);
    _sync.removeListener(_changed);
    _tracking.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _operations(),
          const HomeScreen(),
          _flowView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: const Color(0xFF030D16),
        indicatorColor: _blue.withValues(alpha: .18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'FUVAR',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'SCANNER',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'FLOW',
          ),
        ],
      ),
    );
  }

  Widget _operations() {
    final state = _flow.state;
    final waiting = state.waitingDuration(DateTime.now());
    final queue = _sync.pendingCount + _tracking.queuedPointCount;
    final connectionColor = _sync.deviceState == 'approved' ? _green : (_sync.deviceState == 'revoked' ? _red : _amber);
    final connectionText = _sync.deviceState == 'approved' ? 'ONLINE' : (_sync.deviceState == 'revoked' ? 'TILTOTT' : 'OFFLINE KÉSZ');

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
            await Future.wait([_sync.syncNow(), _tracking.syncNow()]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/aims_flow_logo.png', width: 46, height: 46, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AIMS FLOW', style: TextStyle(letterSpacing: 3.3, fontSize: 15, fontWeight: FontWeight.w900)),
                        SizedBox(height: 2),
                        Text('DRIVER OPERATIONS', style: TextStyle(color: _blue, fontSize: 10, letterSpacing: 1.7, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  _status(connectionText, connectionColor),
                ],
              ),
              const SizedBox(height: 20),
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(state.reference, style: const TextStyle(color: _blue, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                              const SizedBox(height: 7),
                              Text(state.stage.label, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _editFreight, tooltip: 'Fuvar szerkesztése', icon: const Icon(Icons.edit_outlined, color: Colors.white60)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _routePoint(state.pickup, 'FELRAKÓ')),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, color: _blue),
                        ),
                        Expanded(child: _routePoint(state.delivery, 'LERAKÓ', right: true)),
                      ],
                    ),
                    if (state.plate.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Jármű: ${state.plate}', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: state.stage.progress,
                      minHeight: 6,
                      borderRadius: const BorderRadius.all(Radius.circular(99)),
                      backgroundColor: Colors.white10,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _metric('GPS', _tracking.active ? 'AKTÍV' : 'KÉSZ', _tracking.active ? _green : _blue)),
                        const SizedBox(width: 8),
                        Expanded(child: _metric('CMR', _sync.pendingCount == 0 ? 'RENDBEN' : '${_sync.pendingCount} SORBAN', _sync.pendingCount == 0 ? _green : _amber)),
                        const SizedBox(width: 8),
                        Expanded(child: _metric('QUEUE', '$queue', queue == 0 ? _green : _amber)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: state.stage.canDriverAdvance ? _advance : null,
                      icon: Icon(state.stage == FreightStage.cmrReview ? Icons.verified_outlined : Icons.arrow_forward_rounded),
                      label: Text(state.stage.nextAction),
                    ),
                    if (state.stage == FreightStage.accepted && !state.checklistComplete) ...[
                      const SizedBox(height: 9),
                      Text(
                        'Indulás előtt még ${state.checklist.length - state.completedChecklistItems} checklist pont hiányzik.',
                        style: const TextStyle(color: _amber, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              if (state.waitingActive) ...[
                const SizedBox(height: 12),
                _liveBanner(Icons.timer_rounded, 'VÁRAKOZÁS FUT', _duration(waiting), _amber, onTap: _flow.stopWaiting),
              ],
              if (_sync.lastError != null) ...[
                const SizedBox(height: 12),
                _liveBanner(Icons.cloud_off_rounded, 'OFFLINE SOR', _sync.lastError!, _amber, onTap: _sync.syncNow),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Text('MŰVELETI KÖZPONT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1))),
                  Text('${_readiness(state)}% READY', style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                childAspectRatio: 1.37,
                children: [
                  _action(Icons.document_scanner_rounded, 'CMR Scanner', '${_sync.pendingCount} dokumentum vár', () => setState(() => _index = 1), badge: _sync.pendingCount),
                  _action(Icons.gps_fixed, 'Élő GPS', _tracking.active ? 'Nyomkövetés aktív' : 'Fuvar követése', _openTracking, active: _tracking.active),
                  _action(Icons.fact_check_outlined, 'Checklist', '${state.completedChecklistItems}/${state.checklist.length} kész', _showChecklist, active: state.checklistComplete),
                  _action(Icons.warning_amber_rounded, 'Incidens', '${state.incidents.length} rögzítve', _showIncident, badge: state.incidents.where((e) => e.critical).length),
                  _action(Icons.timer_outlined, 'Várakozás', state.waitingActive ? _duration(waiting) : _duration(Duration(seconds: state.accumulatedWaitingSeconds)), _toggleWaiting, active: state.waitingActive),
                  _action(Icons.photo_library_outlined, 'Bizonyíték', '${state.evidenceCount} elem + CMR', _showEvidence),
                  _action(Icons.sticky_note_2_outlined, 'Jegyzet', '${state.notes.length} megjegyzés', _showNote),
                  _action(Icons.sync_rounded, 'Szinkron', _sync.syncing ? 'Folyamatban…' : 'Kézi újrapróbálás', _sync.syncing ? null : _manualSync),
                  _action(Icons.sos_rounded, 'SOS', 'Kritikus segítségkérés', _showSos, danger: true),
                  _action(Icons.route_rounded, 'Fuvaradatok', '${state.pickup} → ${state.delivery}', _editFreight),
                ],
              ),
              const SizedBox(height: 18),
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('KÖVETKEZŐ LÉPÉS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    const SizedBox(height: 7),
                    Text(state.stage.nextAction, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    Text(_nextStepHint(state), style: const TextStyle(color: Colors.white54, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flowView() {
    final state = _flow.state;
    final events = state.events.where((event) {
      if (_eventFilter == 'all') return true;
      if (_eventFilter == 'critical') return event.level == FlowEventLevel.critical || event.level == FlowEventLevel.warning;
      if (_eventFilter == 'success') return event.level == FlowEventLevel.success;
      return true;
    }).toList();

    return Container(
      color: const Color(0xFF020813),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            const Text('FLOW', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Fuvar eseménynapló, offline sor és rendszerállapot', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _panel(
              Column(
                children: [
                  _health(Icons.gps_fixed, 'GPS', _tracking.active ? 'Aktív' : 'Kész', _tracking.active ? _green : _blue),
                  _health(Icons.cloud_done_outlined, 'Admin kapcsolat', _sync.deviceState.toUpperCase(), _sync.deviceState == 'approved' ? _green : _amber),
                  _health(Icons.storage_outlined, 'Offline sor', '${_sync.pendingCount + _tracking.queuedPointCount} elem', _sync.pendingCount + _tracking.queuedPointCount == 0 ? _green : _amber),
                  _health(Icons.document_scanner_outlined, 'CMR motor', 'Kész', _green),
                  _health(Icons.save_outlined, 'Helyi mentés', _flow.saving ? 'Mentés…' : 'Rendben', _flow.saving ? _amber : _green),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Összes'),
                  const SizedBox(width: 8),
                  _filterChip('critical', 'Figyelmeztetés'),
                  const SizedBox(width: 8),
                  _filterChip('success', 'Sikeres'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (events.isEmpty)
              _panel(const Text('Ehhez a szűrőhöz még nincs esemény.', style: TextStyle(color: Colors.white54)))
            else
              ...events.map(_eventCard),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _manualSync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('TELJES SZINKRON MOST'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _advance() async {
    final before = _flow.state.stage;
    final moved = await _flow.advanceStage();
    if (!mounted) return;
    if (!moved && before == FreightStage.accepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Előbb fejezd be az indulás előtti checklistet.')));
      await _showChecklist();
      return;
    }
    if (_flow.state.stage == FreightStage.toPickup || _flow.state.stage == FreightStage.toDelivery) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Útszakasz aktív. Az Élő GPS indítható a műveleti központból.')));
    }
  }

  Future<void> _openTracking() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrackingScreen()));
  }

  Future<void> _manualSync() async {
    await Future.wait([_sync.syncNow(), _tracking.syncNow()]);
    await _flow.addEvent('Kézi szinkron', detail: 'CMR és GPS sor újrapróbálva.', level: FlowEventLevel.success);
  }

  Future<void> _toggleWaiting() async {
    if (_flow.state.waitingActive) {
      await _flow.stopWaiting();
    } else {
      await _flow.startWaiting();
    }
  }

  Future<void> _showChecklist() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) {
          final state = _flow.state;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Indulás előtti checklist', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${state.completedChecklistItems}/${state.checklist.length} ellenőrzés kész', style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  ...state.checklist.entries.map(
                    (entry) => CheckboxListTile(
                      value: entry.value,
                      contentPadding: EdgeInsets.zero,
                      activeColor: _blue,
                      title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                      onChanged: (value) async {
                        await _flow.setChecklistItem(entry.key, value == true);
                        if (context.mounted) localSetState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: state.checklistComplete ? () => Navigator.pop(context) : null,
                    child: Text(state.checklistComplete ? 'CHECKLIST KÉSZ' : 'MÉG VAN HIÁNYZÓ PONT'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showIncident() async {
    var kind = IncidentKind.waiting;
    var critical = false;
    final note = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Incidens rögzítése', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                DropdownButtonFormField<IncidentKind>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Típus'),
                  items: IncidentKind.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                  onChanged: (value) => localSetState(() => kind = value ?? kind),
                ),
                const SizedBox(height: 12),
                TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Mi történt?', hintText: 'Rövid, tényszerű leírás')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: critical,
                  title: const Text('Kritikus / azonnali admin figyelem'),
                  onChanged: (value) => localSetState(() => critical = value),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await _flow.addIncident(kind: kind, note: note.text, critical: critical);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.report_gmailerrorred_rounded),
                  label: const Text('INCIDENS MENTÉSE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    note.dispose();
  }

  Future<void> _showSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SOS segítségkérés'),
        content: const Text('Kritikus eseményt rögzítünk a fuvarhoz. Ezt csak valódi műveleti probléma esetén használd.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SOS RÖGZÍTÉSE')),
        ],
      ),
    );
    if (confirmed == true) {
      await _flow.addIncident(kind: IncidentKind.other, note: 'SOS segítségkérés a sofőrtől', critical: true);
    }
  }

  Future<void> _showEvidence() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fuvar bizonyítékcsomag', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _evidenceLine(Icons.document_scanner_outlined, 'CMR dokumentumok', '${_sync.pendingCount} offline / függő'),
              _evidenceLine(Icons.gps_fixed, 'GPS pontok', '${_tracking.session?.points.length ?? 0} rögzítve'),
              _evidenceLine(Icons.photo_library_outlined, 'Fotó / egyéb bizonyíték', '${_flow.state.evidenceCount} elem'),
              _evidenceLine(Icons.warning_amber_rounded, 'Incidensek', '${_flow.state.incidents.length} esemény'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await _flow.addEvidence(label: 'Kézi bizonyítékjegy');
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('BIZONYÍTÉKJEGY HOZZÁADÁSA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNote() async {
    final note = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fuvarjegyzet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: note, maxLines: 4, autofocus: true, decoration: const InputDecoration(labelText: 'Megjegyzés')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await _flow.addNote(note.text);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('JEGYZET MENTÉSE'),
              ),
            ],
          ),
        ),
      ),
    );
    note.dispose();
  }

  Future<void> _editFreight() async {
    final state = _flow.state;
    final reference = TextEditingController(text: state.reference);
    final plate = TextEditingController(text: state.plate);
    final pickup = TextEditingController(text: state.pickup);
    final delivery = TextEditingController(text: state.delivery);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071522),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fuvar adatai', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              TextField(controller: reference, decoration: const InputDecoration(labelText: 'Fuvar referencia')),
              const SizedBox(height: 10),
              TextField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Rendszám')),
              const SizedBox(height: 10),
              TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Felrakó')),
              const SizedBox(height: 10),
              TextField(controller: delivery, decoration: const InputDecoration(labelText: 'Lerakó')),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  await _flow.setJobDetails(reference: reference.text, plate: plate.text, pickup: pickup.text, delivery: delivery.text);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('FUVAR MENTÉSE'),
              ),
            ],
          ),
        ),
      ),
    );

    reference.dispose();
    plate.dispose();
    pickup.dispose();
    delivery.dispose();
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xCC081725),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF24557D)),
          boxShadow: [BoxShadow(color: _blue.withValues(alpha: .06), blurRadius: 28)],
        ),
        child: child,
      );

  Widget _status(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text('● $text', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );

  Widget _routePoint(String value, String label, {bool right = false}) => Column(
        crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(value, textAlign: right ? TextAlign.right : TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.1)),
        ],
      );

  Widget _metric(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF06131F), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFF173B54))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),
          ],
        ),
      );

  Widget _action(
    IconData icon,
    String title,
    String detail,
    VoidCallback? onTap, {
    bool active = false,
    bool danger = false,
    int badge = 0,
  }) {
    final accent = danger ? _red : (active ? _green : _blue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF071725),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: active || danger ? .65 : .26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 21),
                const Spacer(),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                    child: Text('$badge', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 9, height: 1.25)),
          ],
        ),
      ),
    );
  }

  Widget _liveBanner(IconData icon, String title, String detail, Color color, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .32))),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      );

  Widget _health(IconData icon, String title, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(icon, color: _blue),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),
          ],
        ),
      );

  Widget _filterChip(String key, String label) => ChoiceChip(
        label: Text(label),
        selected: _eventFilter == key,
        onSelected: (_) => setState(() => _eventFilter = key),
      );

  Widget _eventCard(FlowEvent event) {
    final color = switch (event.level) {
      FlowEventLevel.info => _blue,
      FlowEventLevel.warning => _amber,
      FlowEventLevel.critical => _red,
      FlowEventLevel.success => _green,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF081725), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .28))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(event.title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(_clock(event.createdAt), style: const TextStyle(color: Colors.white30, fontSize: 9))]),
                if (event.detail?.isNotEmpty == true) ...[const SizedBox(height: 3), Text(event.detail!, style: const TextStyle(color: Colors.white50, fontSize: 11, height: 1.3))],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _evidenceLine(IconData icon, String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [Icon(icon, color: _blue, size: 20), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(color: Colors.white54, fontSize: 11))]),
      );

  int _readiness(FreightOperationState state) {
    var score = 25;
    if (state.checklistComplete) score += 25;
    if (_tracking.active || state.stage.index < FreightStage.toPickup.index) score += 15;
    if (_sync.deviceState == 'approved') score += 15;
    if (_sync.pendingCount == 0) score += 10;
    if (state.incidents.where((e) => e.critical).isEmpty) score += 10;
    return score.clamp(0, 100).toInt();
  }

  String _nextStepHint(FreightOperationState state) {
    return switch (state.stage) {
      FreightStage.assigned => 'Ellenőrizd a fuvar adatait, majd fogadd el a megbízást.',
      FreightStage.accepted => 'Töltsd ki az indulás előtti checklistet. Enélkül az app nem enged tovább.',
      FreightStage.toPickup => 'Kapcsold be az Élő GPS-t és haladj a felrakóhelyre.',
      FreightStage.atPickup => 'Dokumentáld a felrakást, ellenőrizd a rakományt és a CMR-t.',
      FreightStage.loaded => 'Indítsd el a lerakó felé tartó szakaszt.',
      FreightStage.toDelivery => 'Tartsd aktívan a GPS-t, problémánál használj incidensjelentést.',
      FreightStage.atDelivery => 'Dokumentáld a lerakást és készítsd elő a POD/CMR bizonyítékot.',
      FreightStage.cmrReview => 'Szkenneld a CMR-t, ellenőrizd az olvashatóságot, majd zárd le a fuvart.',
      FreightStage.completed => 'A sofőri folyamat kész. Az admin jóváhagyására vár.',
      FreightStage.adminApproved => 'A fuvar teljesen lezárt és jóváhagyott.',
    };
  }

  static String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _duration(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60);
    final s = value.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
