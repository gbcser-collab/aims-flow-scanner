import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/gps_tracking_service.dart';
import '../widgets/aims_skin.dart';

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  final _runtime = GpsTrackingService.instance;
  late final TextEditingController _plate;
  late final TextEditingController _reference;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _plate = TextEditingController(text: _runtime.plate);
    _reference = TextEditingController(text: _runtime.reference);
    _runtime.initialize();
  }

  @override
  void dispose() {
    _plate.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _localError = null);
    try {
      await _runtime.start(plate: _plate.text, reference: _reference.text);
    } on FormatException catch (e) {
      if (mounted) setState(() => _localError = e.message);
    } catch (e) {
      if (mounted) setState(() => _localError = e.toString());
    }
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071B35),
        title: const Text('Fuvar lezárása?', style: TextStyle(color: Colors.white)),
        content: const Text('A GPS nyomkövetés azonnal leáll.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lezárás')),
        ],
      ),
    );
    if (ok == true) await _runtime.stop();
  }

  String _time(DateTime? value) {
    if (value == null) return '—';
    final v = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(v.hour)}:${two(v.minute)}:${two(v.second)}';
  }

  Widget _metric(String label, String value) {
    return AimsGlassCard(
      padding: const EdgeInsets.all(13),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _runtime,
      builder: (context, _) {
        final Position? point = _runtime.latest;
        final error = _localError ?? _runtime.error;
        return Scaffold(
          backgroundColor: aimsNavy,
          appBar: AppBar(
            backgroundColor: const Color(0xFF03152C),
            foregroundColor: Colors.white,
            title: const Text('Fuvar + GPS'),
          ),
          body: AimsBackdrop(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AimsGlassCard(
                  child: Row(
                    children: [
                      Icon(_runtime.active ? Icons.gps_fixed_rounded : Icons.location_off_rounded, color: _runtime.active ? aimsMint : aimsCyan, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _runtime.active ? 'ÉLŐ GPS AKTÍV' : 'GPS NYOMKÖVETÉS KIKAPCSOLVA',
                              style: TextStyle(color: _runtime.active ? aimsMint : aimsCyan, fontWeight: FontWeight.w900, letterSpacing: .5),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _runtime.active ? 'Az aktív fuvar pozíciója folyamatosan frissül.' : 'Indítsd el a fuvart a valós GPS-rögzítéshez.',
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
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: aimsInputDecoration('Rendszám', prefix: const Icon(Icons.local_shipping_outlined, color: Color(0xFFB7E6FF))),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reference,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: aimsInputDecoration('Fuvar / referencia (opcionális)', prefix: const Icon(Icons.tag_rounded, color: Color(0xFFB7E6FF))),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error, style: const TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 12),
                  AimsNeonButton(
                    label: _runtime.busy ? 'Indítás…' : 'Fuvar + GPS indítása',
                    onPressed: _runtime.busy ? null : _start,
                    leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: _metric('Jármű', _runtime.plate)),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Referencia', _runtime.reference.isEmpty ? '—' : _runtime.reference)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _metric('Sebesség', point == null ? '—' : '${(point.speed * 3.6).clamp(0, 999).toStringAsFixed(0)} km/h')),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Pontosság', point == null ? '—' : '±${point.accuracy.toStringAsFixed(0)} m')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _metric('Valós koordináta', point == null ? 'GPS-jelre vár…' : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _metric('Utolsó GPS', _time(point?.timestamp))),
                      const SizedBox(width: 10),
                      Expanded(child: _metric('Indítás', _time(_runtime.startedAt))),
                    ],
                  ),
                  if (point?.isMocked == true) ...[
                    const SizedBox(height: 10),
                    const AimsGlassCard(
                      child: Text('Figyelem: az Android ezt a pozíciót teszt/mock helyadatként jelölte.', style: TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w800)),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error, style: const TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: _runtime.busy ? null : _stop,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB9374F), foregroundColor: Colors.white),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Fuvar lezárása • GPS leállítása', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AimsGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Android GPS állapot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        _runtime.active
                            ? 'A helymeghatározás aktív. Androidon tartós értesítés jelzi a háttérben futó GPS-rögzítést.'
                            : 'A GPS csak akkor indul el, amikor te elindítod a fuvart.',
                        style: const TextStyle(color: Colors.white70, height: 1.4),
                      ),
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
}
