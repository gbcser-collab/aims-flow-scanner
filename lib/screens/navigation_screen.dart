import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/aims_skin.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _destination = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _launch() async {
    final text = _destination.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Add meg a célállomást vagy címet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': text, 'travelmode': 'driving'});
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => _error = 'A navigáció nem indítható ezen a készüléken.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Navigációs hiba: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aimsNavy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF03152C),
        foregroundColor: Colors.white,
        title: const Text('Navigáció'),
      ),
      body: AimsBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const AimsGlassCard(
              child: Row(
                children: [
                  Icon(Icons.navigation_rounded, color: aimsCyan, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add meg a lerakóhelyet vagy a pontos címet. Az AIMS Flow átadja az úticélt a telefon navigációjának.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destination,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _launch(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              decoration: aimsInputDecoration(
                'Célállomás / cím',
                prefix: const Icon(Icons.location_on_outlined, color: Color(0xFFB7E6FF)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            AimsNeonButton(
              label: _busy ? 'Megnyitás…' : 'Navigáció indítása',
              onPressed: _busy ? null : _launch,
              leading: const Icon(Icons.near_me_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
