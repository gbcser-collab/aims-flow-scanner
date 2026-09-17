import 'package:flutter/material.dart';

import '../services/tracking_runtime.dart';
import '../widgets/aims_flow_skin.dart';

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
    _runtime.initialize();
  }

  @override
  void dispose() {
    _plate.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _start() async {
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
        backgroundColor: AimsFlowSkin.panelSolid,
        title: const Text('Fuvar lezárása?', style: TextStyle(color: Colors.white)),
        content: const Text('A GPS nyomkövetés leáll. A még offline sorban lévő pontok később automatikusan szinkronizálódnak.', style: TextStyle(color: Colors.white70)),
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
          backgroundColor: AimsFlowSkin.background,
          appBar: AppBar(
            backgroundColor: AimsFlowSkin.background,
            foregroundColor: Colors.white,
            title: const Text('Fuvar + GPS', style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [IconButton(onPressed: _runtime.busy ? null : _runtime.syncNow, icon: const Icon(Icons.sync_rounded))],
          ),
          body: AimsFlowBackground(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AimsFlowSkin.glass(radius: 20),
                    child: Row(
                      children: [
                        Icon(_runtime.active ? Icons.gps_fixed_rounded : Icons.location_off_rounded, color: _runtime.active ? AimsFlowSkin.green : AimsFlowSkin.cyan, size: 34),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_runtime.active ? 'ÉLŐ GPS AKTÍV' : 'GPS NYOMKÖVETÉS KIKAPCSOLVA', style: TextStyle(color: _runtime.active ? AimsFlowSkin.green : AimsFlowSkin.cyan, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              Text(_runtime.active ? 'Az aktív fuvar pozíciója rögzítésre és szinkronizálásra kerül.' : 'Indítsd el a fuvart a valós GPS nyomkövetéshez.', style: const TextStyle(color: Colors.white70, height: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!_runtime.active) ...[
                    _input('Rendszám', _plate, capitalization: TextCapitalization.characters),
                    _input('Fuvar / referencia', _reference),
                    if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800))),
                    AimsGlowButton(label: 'Fuvar + GPS indítása', icon: Icons.play_arrow_rounded, onPressed: _start, busy: _runtime.busy),
                  ] else ...[
                    Row(children: [
                      Expanded(child: _metric('Jármű', session?.plate ?? '—')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Fuvar', session?.reference.isNotEmpty == true ? session!.reference : '—')),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _metric('Sebesség', point == null ? '—' : '${point.speedKmh.toStringAsFixed(0)} km/h')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Pontosság', point == null ? '—' : '±${point.accuracy.toStringAsFixed(0)} m')),
                    ]),
                    const SizedBox(height: 10),
                    _metric('Valós koordináta', point == null ? 'GPS-jelre vár…' : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _metric('Utolsó GPS', _time(point?.capturedAt))),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Offline sor', '${_runtime.queuedPointCount} pont')),
                    ]),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _runtime.busy ? null : _stop,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Fuvar lezárása • GPS leállítása'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: AimsFlowSkin.glass(radius: 16, alpha: .68),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Kapcsolat az adminnal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text('Eszköz státusz: ${_runtime.deviceState.toUpperCase()}', style: const TextStyle(color: AimsFlowSkin.cyan, fontWeight: FontWeight.w800)),
                      if (_runtime.statusMessage != null) ...[const SizedBox(height: 5), Text(_runtime.statusMessage!, style: const TextStyle(color: Colors.white60))],
                    ]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _input(String label, TextEditingController controller, {TextCapitalization capitalization = TextCapitalization.sentences}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          textCapitalization: capitalization,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: AimsFlowSkin.panelSolid.withValues(alpha: .82),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF2876A9))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AimsFlowSkin.cyan)),
          ),
        ),
      );

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.all(13),
        decoration: AimsFlowSkin.glass(radius: 15, alpha: .72),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ]),
      );
}
