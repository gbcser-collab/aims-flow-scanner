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
  StreamSubscription<VehicleTrackingStatus>? _subscription;
  VehicleTrackingStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.currentStatus().then((value) {
      if (!mounted) return;
      setState(() => _status = value);
      _service.startIfEnabled();
    });
    _subscription = _service.statusStream.listen((value) {
      if (mounted) setState(() => _status = value);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final enabled = await _service.enableWithPermission();
      if (!mounted) return;
      if (!enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A folyamatos nyomkövetéshez engedélyezd a helyhozzáférést.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    return Container(
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
                  active ? 'Jármű-nyomkövetés aktív' : 'Jármű-nyomkövetés nincs bekapcsolva',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            active
                ? 'Az AIMS Flow a munkavégzés alatt háttérben is továbbítja a jármű helyzetét. Androidon erről állandó rendszerértesítés látható.'
                : 'Az első bekapcsolásnál a telefon helyengedélyt kér. Ezután az app minden induláskor automatikusan újraindítja a nyomkövetést.',
            style: const TextStyle(color: Colors.white60, height: 1.35),
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
            Text(
              status!.lastError!,
              style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700),
            ),
          ],
          if (!active) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _enable,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.location_on_rounded),
              label: Text(_busy ? 'Bekapcsolás…' : 'Nyomkövetés bekapcsolása'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF48D597),
                foregroundColor: Colors.black,
              ),
            ),
          ],
          if (status != null && status.deviceId.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Tracker ID: ${status.deviceId}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
