import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/tracking_runtime.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const _blue = Color(0xFF1478FF);
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _dark ? const Color(0xFF020813) : const Color(0xFFF5F9FC);
  Color get _panel => _dark ? const Color(0xFF0A1727) : Colors.white;
  Color get _text => _dark ? Colors.white : const Color(0xFF0A1C2E);
  Color get _muted => _dark ? Colors.white70 : const Color(0xFF536B7A);
  Color get _faint => _dark ? Colors.white38 : const Color(0xFF8093A0);
  Color get _line => _dark ? const Color(0xFF24557D) : const Color(0xFFD5E2EB);
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

  Future<void> _openLiveMap(TrackingPoint point) async {
    final coordinate =
        '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(coordinate)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A térkép nem nyitható meg.')),
      );
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
          backgroundColor: _page,
          appBar: AppBar(
            backgroundColor: _page,
            foregroundColor: _text,
            title: const Text('AIMS Flow • Nyomkövetés'),
            actions: [
              IconButton(
                tooltip: 'Szinkronizálás most',
                onPressed: _runtime.busy ? null : _runtime.syncNow,
                icon: const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          body: Container(
            color: _page,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _runtime.active
                          ? (_dark ? const Color(0xFF0B2420) : const Color(0xFFEAF9F2))
                          : _panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: (_runtime.active ? const Color(0xFF48D597) : _blue).withValues(alpha: .48)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_runtime.active ? Icons.location_on_rounded : Icons.location_off_rounded, color: _runtime.active ? const Color(0xFF48D597) : _blue, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _runtime.active ? 'ÉLŐ GPS AKTÍV' : 'GPS NYOMKÖVETÉS KIKAPCSOLVA',
                                style: TextStyle(color: _runtime.active ? const Color(0xFF48D597) : _blue, fontWeight: FontWeight.w900, letterSpacing: .7),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _runtime.active
                                    ? 'Csak az aktív fuvar alatt követ. Androidon állandó értesítés jelzi a nyomkövetést.'
                                    : 'A követés nem fut a háttérben addig, amíg itt el nem indítod a fuvart.',
                                style: TextStyle(color: _muted, height: 1.35),
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
                        backgroundColor: const Color(0xFF0B76FF),
                        foregroundColor: Colors.white,
                        shadowColor: _blue,
                        elevation: 7,
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
                    if (point != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _openLiveMap(point),
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('Élő helyzet megnyitása térképen'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: _blue,
                          side: const BorderSide(color: _blue),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
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
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _blue.withValues(alpha: .24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Kapcsolat az adminnal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text('Eszköz státusz: ${_runtime.deviceState.toUpperCase()}', style: const TextStyle(color: _blue, fontWeight: FontWeight.w800)),
                        if (_runtime.statusMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(_runtime.statusMessage!, style: TextStyle(color: _muted, height: 1.35)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
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
        style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _muted),
          filled: true,
          fillColor: _panel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _blue)),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _blue.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: _faint, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
