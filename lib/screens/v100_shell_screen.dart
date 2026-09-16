import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'tracking_screen.dart';

class V100ShellScreen extends StatefulWidget {
  const V100ShellScreen({super.key});

  @override
  State<V100ShellScreen> createState() => _V100ShellScreenState();
}

class _V100ShellScreenState extends State<V100ShellScreen> {
  static const _blue = Color(0xFF1CB8FF);
  int _index = 0;
  int _step = 0;
  final List<String> _events = ['V100 natív műveleti rendszer elindult'];
  final List<String> _steps = const [
    'Fuvar átvétele',
    'Felrakó megközelítése',
    'Felrakás dokumentálása',
    'Úton a lerakóra',
    'Lerakás dokumentálása',
    'CMR ellenőrzése',
    'Fuvar lezárása',
  ];

  void _advance() {
    setState(() {
      _step = (_step + 1) % _steps.length;
      _events.insert(0, _steps[_step]);
    });
  }

  void _openAction(String title, String detail) {
    showModalBottomSheet<void>(
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
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: Colors.white60, height: 1.45)),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  setState(() => _events.insert(0, '$title · rögzítve'));
                  Navigator.pop(context);
                },
                child: const Text('MŰVELET RÖGZÍTÉSE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)]),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AIMS FLOW', style: TextStyle(letterSpacing: 3.5, color: Colors.white60, fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('V100 · DRIVER OPERATIONS', style: TextStyle(fontSize: 10, color: _blue, fontWeight: FontWeight.w800)),
              ])),
              _status('ONLINE', const Color(0xFF4DE3A4)),
            ]),
            const SizedBox(height: 22),
            _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AKTÍV FUVAR · EXPRESS', style: TextStyle(color: _blue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(_steps[_step], style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              const Text('A rendszer az aktuális fuvarállapotból adja a következő teendőt.', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 18),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _RoutePoint('GYŐR', 'Felrakó'), Icon(Icons.arrow_forward_rounded, color: _blue), _RoutePoint('BRNO', 'Lerakó'),
              ]),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: .56, minHeight: 5, borderRadius: BorderRadius.all(Radius.circular(99))),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: _metric('GPS', 'AKTÍV')), const SizedBox(width: 8), Expanded(child: _metric('CMR', 'FIGYELVE')), const SizedBox(width: 8), Expanded(child: _metric('SYNC', 'KÉSZ'))]),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _advance, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('FUVAR FOLYTATÁSA')),
            ])),
            const SizedBox(height: 14),
            const Text('MŰVELETI KÖZPONT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.45,
              children: [
                _action(Icons.gps_fixed, 'Élő GPS', 'Fuvar követése valós helyadatokkal.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen()))),
                _action(Icons.warning_amber_rounded, 'Incidens', 'Várakozás, sérülés, címhiba vagy műszaki hiba.', () => _openAction('Incidens jelentése', 'Az esemény a fuvarhoz, időponthoz és helyhez kapcsolódik.')),
                _action(Icons.fact_check_outlined, 'Checklist', 'Indulás előtti jármű- és dokumentumellenőrzés.', () => _openAction('Sofőr checklist', 'Gumi, világítás, rakomány, dokumentumok és kötelező felszerelés.')),
                _action(Icons.photo_library_outlined, 'Bizonyíték', 'CMR, fotó, GPS és időbélyeg egy csomagban.', () => _openAction('Bizonyítékcsomag', 'A fuvarhoz tartozó bizonyítékok egységes áttekintése.')),
                _action(Icons.timer_outlined, 'Várakozás', 'Állásidő rögzítése és dokumentálása.', () => _openAction('Várakozásmérő', 'A kezdés és befejezés eseménye naplózható.')),
                _action(Icons.sos_outlined, 'SOS', 'Gyors segítségkérés műveleti problémánál.', () => _openAction('SOS / Segítség', 'Gyors eseményrögzítés az admin felé.')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _flow() {
    return Container(
      color: const Color(0xFF020813),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('FLOW', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Fuvar eseménynapló és rendszerállapot', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _panel(Column(children: [
              _health(Icons.gps_fixed, 'GPS', 'Aktív'),
              _health(Icons.cloud_done_outlined, 'Szinkron', 'Kész'),
              _health(Icons.storage_outlined, 'Offline tárhely', 'Rendben'),
              _health(Icons.document_scanner_outlined, 'CMR motor', 'Kész'),
            ])),
            const SizedBox(height: 14),
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
    decoration: BoxDecoration(color: const Color(0xCC081725), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF24557D))),
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

  Widget _action(IconData icon, String title, String detail, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF071725), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF173B54))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: _blue, size: 20), const Spacer(), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 9))]),
    ),
  );

  Widget _health(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(children: [Icon(icon, color: _blue), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(value, style: const TextStyle(color: Color(0xFF4DE3A4), fontWeight: FontWeight.w900))]),
  );
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint(this.city, this.label);
  final String city;
  final String label;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(city, style: const TextStyle(fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10))]);
}
