import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/flow_account_service.dart';
import '../services/flow_safety_check_service.dart';
import 'safety_photo_capture_screen.dart';

class FlowSafetyCheckScreen extends StatefulWidget {
  const FlowSafetyCheckScreen({
    super.key,
    required this.session,
    required this.plate,
    required this.initialKm,
  });

  final FlowAccountSession session;
  final String plate;
  final int initialKm;

  @override
  State<FlowSafetyCheckScreen> createState() => _FlowSafetyCheckScreenState();
}

class _FlowSafetyCheckScreenState extends State<FlowSafetyCheckScreen> {
  final _service = FlowSafetyCheckService.instance;
  late final TextEditingController _km =
      TextEditingController(text: widget.initialKm.toString());
  final Map<String, String> _status = {
    'oil': 'ok',
    'coolant': 'ok',
    'tires': 'ok',
    'steering': 'ok',
  };
  final Map<String, String> _photos = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Future<void> _photo(String key, String title) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SafetyPhotoCaptureScreen(
          title: title,
          fileLabel: key,
        ),
      ),
    );
    if (path != null && mounted) setState(() => _photos[key] = path);
  }

  Widget _row(
    String key,
    String title, {
    bool photo = false,
    String? photoTitle,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ok', label: Text('RENDBEN')),
                  ButtonSegment(value: 'problem', label: Text('PROBLÉMA')),
                ],
                selected: {_status[key]!},
                onSelectionChanged: (value) =>
                    setState(() => _status[key] = value.first),
              ),
              if (photo) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _photo(key, photoTitle ?? title),
                  icon: Icon(
                    _photos.containsKey(key)
                        ? Icons.check_circle_rounded
                        : Icons.camera_alt_outlined,
                  ),
                  label: Text(
                    _photos.containsKey(key)
                        ? 'FOTÓ KÉSZ'
                        : 'KÖTELEZŐ FOTÓ',
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Future<void> _submit() async {
    if (_busy) return;
    final km = int.tryParse(_km.text.trim());
    if (km == null || km < 0 || km > 5000000) {
      setState(() => _error = 'Ellenőrizd a kilométeróra-állást.');
      return;
    }
    const required = {'oil', 'coolant', 'tires', 'odometer'};
    if (!required.every(_photos.containsKey)) {
      setState(() => _error =
          'Kötelező fotó: olajnívó, hűtőfolyadék, kerék és kilométeróra.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.saveAndSubmit(
        session: widget.session,
        plate: widget.plate,
        km: km,
        statuses: _status,
        photoPaths: _photos,
      );
      if (!mounted) return;
      Navigator.of(context).pop(km);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('FLOW SAFETY CHECK')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Gyors járműellenőrzés',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.plate} · álló helyzetben végezd el',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            _row(
              'oil',
              'Olajszint',
              photo: true,
              photoTitle: 'Fotó az olajnívóról',
            ),
            const SizedBox(height: 10),
            _row(
              'coolant',
              'Hűtőfolyadék / víz',
              photo: true,
              photoTitle: 'Fotó a hűtőfolyadék szintjéről',
            ),
            const SizedBox(height: 10),
            _row(
              'tires',
              'Kerekek / gumik',
              photo: true,
              photoTitle: 'Fotó a kerékről / gumiról',
            ),
            const SizedBox(height: 10),
            _row('steering', 'Kormányzás / rendellenes holtjáték vagy zaj'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Kilométeróra',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _km,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Aktuális km',
                        suffixText: 'km',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _photo(
                        'odometer',
                        'Fotó a kilométeróráról',
                      ),
                      icon: Icon(
                        _photos.containsKey('odometer')
                            ? Icons.check_circle_rounded
                            : Icons.camera_alt_outlined,
                      ),
                      label: Text(
                        _photos.containsKey('odometer')
                            ? 'FOTÓ KÉSZ'
                            : 'KÖTELEZŐ KM-FOTÓ',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.verified_rounded),
              label: Text(_busy ? 'MENTÉS…' : 'ELLENŐRZÉS BEKÜLDÉSE'),
            ),
          ],
        ),
      );
}
