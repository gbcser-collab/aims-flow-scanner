import 'package:flutter/material.dart';

import '../services/tracking_runtime.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _runtime = TrackingRuntime.instance;
  late final TextEditingController _plate;
  late final TextEditingController _reference;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = _runtime.session;
    _plate = TextEditingController(text: session?.plate ?? '');
    _reference = TextEditingController(text: session?.reference ?? '');
  }

  @override
  void dispose() {
    _plate.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_plate.text.trim().isEmpty) {
      setState(() => _error = 'Add meg a jármű rendszámát.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nyomkövetés indítása'),
        content: const Text(
          'Az aktív fuvar alatt a telefon valós GPS-pozíciót rögzít és internetkapcsolat esetén továbbítja a Logistic-AIMS admin felületére. '
          'A követés a „Fuvar lezárása” gombbal leáll. Androidon aktív értesítés jelzi a működését.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Indítás')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _error = null);
    try {
      await _runtime.start(plate: _plate.text, reference: _reference.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fuvar lezárása?'),
        content: const Text('A GPS-nyomkövetés azonnal leáll. A még offline sorban lévő pontok később automatikusan szinkronizálódnak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lezárás')),
        ],
      ),
    );
    if (confirmed == true) await _runtime.stop();
  }

  String _time(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _runtime,
      builder: (context, _) {
        final point = _runtime.latestPoint;
        final session = _runtime.session;
        return Scaffold(
          backgroundColor: const Color(0xFF0C0F13),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0C0F13),
            foregroundColor: Colors.white,
            title: const Text('AIMS Flow • Nyomkövetés'),
            actions: [
              IconButton(
                tooltip: 'Szinkronizálás most',
                onPressed: _runtime.busy ? null : _runtime.syncNow,
                icon: const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _runtime.active ? const Color(0xFF13231D) : const Color(0xFF171A1F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: (_runtime.active ? const Color(0xFF48D597) : const Color(0xFFE6B85C)).withValues(alpha: .4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_runtime.active ? Icons.location_on_rounded : Icons.location_off_rounded, color: _runtime.active ? const Color(0xFF48D597) : const Color(0xFFE6B85C), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _runtime.active ? 'ÉLŐ GPS AKTÍV' : 'GPS NYOMKÖVETÉS KIKAPCSOLVA',
                              style: TextStyle(color: _runtime.active ? const Color(0xFF48D597) : const Color(0xFFE6B85C), fontWeight: FontWeight.w900, letterSpacing: .7),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _runtime.active
                                  ? 'Csak az aktív fuvar alatt követ. Androidon állandó értesítés jelzi a nyomkövetést.'
                                  : 'A követés nem fut a háttérben addig, amíg itt el nem indítod a fuvart.',
                              style: const TextStyle(color: Colors.white70, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!_runtime.active) ...[
                  _input('Rendszám', _plate, capitalization: TextCapitalization.characters),
                  _input('Fuvar / referencia (opcionális)', _reference),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _runtime.busy ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Fuvar + GPS indítása'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFFE6B85C),
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: _metric('Jármű', session?.plate ?? '—')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Fuvar', session?.reference.trim().isNotEmpty == true ? session!.reference : '—')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _metric('Sebesség', point == null ? '—' : '${point.speedKmh.toStringAsFixed(0)} km/h')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Pontosság', point == null ? '—' : '±${point.accuracy.toStringAsFixed(0)} m')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _metric('Valós koordináta', point == null ? 'GPS-jelre vár…' : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _metric('Utolsó GPS', _time(point?.capturedAt))),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Offline sor', '${_runtime.queuedPointCount} pont')),
                    ],
                  ),
                  if (point?.isMocked == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                      child: const Text('Figyelem: az Android ezt a pozíciót teszt/mock helyadatként jelölte.', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _runtime.busy ? null : _stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Fuvar lezárása • GPS leállítása'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Kapcsolat az adminnal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('Eszköz státusz: ${_runtime.deviceState.toUpperCase()}', style: const TextStyle(color: Color(0xFFE6B85C), fontWeight: FontWeight.w800)),
                      if (_runtime.statusMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(_runtime.statusMessage!, style: const TextStyle(color: Colors.white60, height: 1.35)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _input(String label, TextEditingController controller, {TextCapitalization capitalization = TextCapitalization.sentences}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        textCapitalization: capitalization,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF14181D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE6B85C))),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFF14181D), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
