import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/gps_tracking_service.dart';
import '../widgets/aims_skin.dart';
import 'gps_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _runtime = GpsTrackingService.instance;

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_changed);
    _runtime.initialize();
  }

  @override
  void dispose() {
    _runtime.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _date(DateTime value) {
    final v = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${v.year}.${two(v.month)}.${two(v.day)} ${two(v.hour)}:${two(v.minute)}';
  }

  String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours > 0) return '${hours} ó ${minutes} p';
    return '${minutes} p';
  }

  Future<void> _openLastPosition(GpsTripRecord record) async {
    if (record.latitude == null || record.longitude == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${record.latitude},${record.longitude}',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _delete(GpsTripRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071B35),
        title: const Text('Fuvar törlése?', style: TextStyle(color: Colors.white)),
        content: Text('${record.plate}${record.reference.isEmpty ? '' : ' • ${record.reference}'}', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Törlés')),
        ],
      ),
    );
    if (ok == true) await _runtime.deleteHistoryRecord(record.id);
  }

  @override
  Widget build(BuildContext context) {
    final history = _runtime.history;
    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('Fuvarok'),
        actions: [
          IconButton(
            tooltip: 'Új fuvar / GPS',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GpsScreen())),
            icon: const Icon(Icons.add_road_rounded),
          ),
        ],
      ),
      body: AimsBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_runtime.active) ...[
              AimsGlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed_rounded, color: aimsMint, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('AKTÍV FUVAR', style: TextStyle(color: aimsMint, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(_runtime.plate, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          if (_runtime.reference.isNotEmpty) Text(_runtime.reference, style: const TextStyle(color: Colors.white60)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GpsScreen())),
                      icon: const Icon(Icons.chevron_right_rounded, color: aimsCyan),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            AimsSectionTitle('Korábbi fuvarok', trailing: Text('${history.length}', style: const TextStyle(color: aimsCyan, fontWeight: FontWeight.w900))),
            const SizedBox(height: 10),
            if (history.isEmpty)
              const AimsGlassCard(
                child: Text('Még nincs lezárt fuvar ezen a készüléken.', style: TextStyle(color: Colors.white70)),
              )
            else
              ...history.map((record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AimsGlassCard(
                      padding: EdgeInsets.zero,
                      radius: 16,
                      child: ListTile(
                        leading: const Icon(Icons.local_shipping_outlined, color: aimsCyan, size: 30),
                        title: Text(record.plate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record.reference.isNotEmpty) Text(record.reference, style: const TextStyle(color: Color(0xFF9FD5FF))),
                            Text('${_date(record.startedAt)} • ${_duration(record.duration)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          iconColor: const Color(0xFF9EDBFF),
                          color: const Color(0xFF071B35),
                          onSelected: (value) {
                            if (value == 'map') _openLastPosition(record);
                            if (value == 'delete') _delete(record);
                          },
                          itemBuilder: (_) => [
                            if (record.latitude != null && record.longitude != null)
                              const PopupMenuItem(value: 'map', child: Text('Utolsó pozíció térképen')),
                            const PopupMenuItem(value: 'delete', child: Text('Törlés')),
                          ],
                        ),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
