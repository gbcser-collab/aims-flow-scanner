import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vehicle_tracking_service.dart';

class TrackingStatusCard extends StatefulWidget {
  const TrackingStatusCard({super.key});

  @override
  State<TrackingStatusCard> createState() => _TrackingStatusCardState();
}

class _TrackingStatusCardState extends State<TrackingStatusCard> {
  final _service = VehicleTrackingService.instance;
  final _plate = TextEditingController();
  StreamSubscription<VehicleTrackingStatus>? _subscription;
  VehicleTrackingStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.currentStatus().then((value) {
      if (!mounted) return;
      _plate.text = value.vehicleLabel;
      setState(() => _status = value);
      _service.startIfEnabled();
    });
    _subscription = _service.statusStream.listen((value) {
      if (!mounted) return;
      if (_plate.text.trim().isEmpty && value.vehicleLabel.isNotEmpty) {
        _plate.text = value.vehicleLabel;
      }
      setState(() => _status = value);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_plate.text.trim().isNotEmpty) {
        await _service.setVehicleLabel(_plate.text);
      }
      final enabled = await _service.enableWithPermission();
      if (!mounted) return;
      if (!enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A folyamatos nyomkövetéshez engedélyezd a helyhozzáférést.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePlate() async {
    final value = _plate.text.trim();
    if (value.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adj meg érvényes rendszámot.')),
      );
      return;
    }
    await _service.setVehicleLabel(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A jármű rendszáma elmentve.')),
    );
  }

  String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final active = status?.enabled == true && status?.running == true;
    final last = status?.lastPosition;

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF10241D) : const Color(0xFF171A1F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? const Color(0xFF48D597).withValues(alpha: .35)
                : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                  color: active ? const Color(0xFF48D597) : Colors.white54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    active ? 'Okos járműkövetés aktív' : 'Járműkövetés nincs bekapcsolva',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'A rendszám köti össze a sofőr telefonját a megfelelő főnökségi/admin fiókkal. '
              'A háttérkövetésből készül a 15/30/60 perces állásjelzés és a fel-/lerakó érkezésértesítés.',
              style: TextStyle(color: Colors.white60, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: 'Jármű rendszáma',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'pl. SIP-115',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF0C0F13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  tooltip: 'Rendszám mentése',
                  onPressed: _savePlate,
                  icon: const Icon(Icons.save_rounded, color: Color(0xFFE6B85C)),
                ),
              ),
            ),
            if (last != null) ...[
              const SizedBox(height: 10),
              Text(
                'Utolsó pozíció: ${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
              ),
            ],
            if (status?.lastSentAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Utolsó szerverfrissítés: ${_formatTime(status!.lastSentAt!)}',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
            if (status?.lastError != null) ...[
              const SizedBox(height: 8),
              Text(status!.lastError!, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            if (!active)
              FilledButton.icon(
                onPressed: _busy ? null : _enable,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.location_on_rounded),
                label: Text(_busy ? 'Bekapcsolás…' : 'Nyomkövetés bekapcsolása'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF48D597),
                  foregroundColor: Colors.black,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : _service.disable,
                icon: const Icon(Icons.pause_circle_outline_rounded),
                label: const Text('Nyomkövetés kikapcsolása'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
              ),
            if (status != null && status.deviceId.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Tracker ID: ${status.deviceId}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
