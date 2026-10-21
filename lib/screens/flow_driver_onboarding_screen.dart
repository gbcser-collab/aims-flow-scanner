import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/flow_account_service.dart';

class FlowDriverOnboardingScreen extends StatefulWidget {
  const FlowDriverOnboardingScreen({
    super.key,
    required this.session,
  });

  final FlowAccountSession session;

  @override
  State<FlowDriverOnboardingScreen> createState() =>
      _FlowDriverOnboardingScreenState();
}

class _FlowDriverOnboardingScreenState
    extends State<FlowDriverOnboardingScreen> {
  final _account = const FlowAccountService();
  late final TextEditingController _name = TextEditingController(
    text: widget.session.driverName,
  );
  late final TextEditingController _plate = TextEditingController(
    text: widget.session.plate,
  );
  late final TextEditingController _km = TextEditingController(
    text: widget.session.currentKm?.toString() ?? '',
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _km.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    final plate = _plate.text.trim().toUpperCase();
    final km = int.tryParse(_km.text.trim());

    if (name.length < 2) {
      setState(() => _error = 'Add meg a neved.');
      return;
    }
    if (plate.length < 4) {
      setState(() => _error = 'Add meg a jármű rendszámát.');
      return;
    }
    if (km == null || km < 0 || km > 5000000) {
      setState(() => _error = 'Ellenőrizd a kilométeróra-állást.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await _account.completeOnboarding(
        session: widget.session,
        driverName: name,
        odometerKm: km,
        plate: plate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Első belépés'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.person_pin_circle_outlined,
                          size: 52,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Állítsuk be a sofőrprofilt',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A kilométeróra-állást a rendszer ehhez a rendszámhoz menti. '
                          'Ezt az adatot az iroda fogja látni.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          key: const Key('flow-onboarding-name'),
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'Sofőr neve',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('flow-onboarding-plate'),
                          controller: _plate,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          maxLength: 16,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9-]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Rendszám',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                            counterText: '',
                            hintText: 'ABC-123',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('flow-onboarding-km'),
                          controller: _km,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Aktuális kilométeróra-állás',
                            prefixIcon: Icon(Icons.speed_rounded),
                            suffixText: 'km',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('flow-onboarding-submit'),
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(
                            _busy ? 'MENTÉS…' : 'PROFIL MENTÉSE',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'FLOW ID: ${widget.session.flowId}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
