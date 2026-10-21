import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/aims_display_mode.dart';
import '../services/aims_locale.dart';
import '../services/flow_account_service.dart';
import '../widgets/aims_flow_logo.dart';
import 'driver_shell_screen.dart';
import 'flow_driver_onboarding_screen.dart';

class FlowLoginScreen extends StatefulWidget {
  const FlowLoginScreen({super.key});

  @override
  State<FlowLoginScreen> createState() => _FlowLoginScreenState();
}

class _FlowLoginScreenState extends State<FlowLoginScreen> {
  final _flowId = TextEditingController();
  final _pin = TextEditingController();
  final _account = const FlowAccountService();

  bool _busy = false;
  bool _resumeBusy = true;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeSession());
  }

  @override
  void dispose() {
    _flowId.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _resumeSession() async {
    try {
      final saved = await FlowSessionStore.instance.load();
      if (saved == null) return;
      final validated = await _account.validateSession(saved);
      if (!mounted) return;
      await _openDriver(validated);
    } catch (_) {
      await FlowSessionStore.instance.clear();
    } finally {
      if (mounted) setState(() => _resumeBusy = false);
    }
  }

  Future<void> _openDriver(FlowAccountSession session) async {
    var current = session;
    if (!current.onboardingComplete ||
        current.driverName.isEmpty ||
        current.plate.isEmpty ||
        current.currentKm == null) {
      final updated = await Navigator.of(context).push<FlowAccountSession>(
        MaterialPageRoute(
          builder: (_) => FlowDriverOnboardingScreen(session: current),
        ),
      );
      if (!mounted || updated == null) return;
      current = updated;
    }

    await FlowSessionStore.instance.save(current);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriverShellScreen(
          initialPlate: current.plate,
          initialDriverName: current.driverName,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_busy || _resumeBusy) return;
    final flowId = _flowId.text.trim();
    final pin = _pin.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(flowId)) {
      setState(() => _error = 'A FLOW ID pontosan 6 számjegyből áll.');
      return;
    }
    if (!RegExp(r'^\d{5}$').hasMatch(pin)) {
      setState(() => _error = 'A PIN pontosan 5 számjegyből áll.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await _account.login(flowId: flowId, pin: pin);
      _pin.clear();
      if (!mounted) return;
      await _openDriver(session);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAdmin() async {
    final uri = Uri.parse('https://logistic-aims.hu/admin/aims-flow.php');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      setState(() => _error = 'Az AIMS FLOW Admin nem nyitható meg.');
    }
  }

  Widget _modeButton() {
    final display = AimsDisplayModeController.instance;
    final locale = AimsLocaleController.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([display, locale]),
      builder: (context, _) {
        final icon = switch (display.mode) {
          AimsDisplayMode.auto => Icons.brightness_auto_rounded,
          AimsDisplayMode.light => Icons.light_mode_outlined,
          AimsDisplayMode.dark => Icons.dark_mode_outlined,
        };
        return OutlinedButton.icon(
          key: const Key('flow-display-mode'),
          onPressed: display.cycleMode,
          icon: Icon(icon, size: 18),
          label: Text(display.label(locale.locale.languageCode)),
        );
      },
    );
  }

  Widget _errorBox(ThemeData theme, bool dark) {
    final message = _error;
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: .35),
        ),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : theme.colorScheme.error,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const [Color(0xFF111315), Color(0xFF1B1E21)]
                        : const [Color(0xFFF8FAFB), Color(0xFFEAF0F4)],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _modeButton(),
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(
                                child: AimsFlowLogo(width: 86, height: 86),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'AIMS FLOW',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: 31,
                                  letterSpacing: -.5,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'SOFŐR BELÉPÉS',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 26),
                              TextField(
                                key: const Key('flow-login-flow-id'),
                                controller: _flowId,
                                autofocus: !_resumeBusy,
                                enabled: !_busy && !_resumeBusy,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                maxLength: 6,
                                inputFormatters: const [],
                                decoration: const InputDecoration(
                                  labelText: '6 jegyű FLOW ID',
                                  hintText: '123456',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('flow-login-pin'),
                                controller: _pin,
                                enabled: !_busy && !_resumeBusy,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                maxLength: 5,
                                obscureText: _obscure,
                                onSubmitted: (_) => _submit(),
                                inputFormatters: const [],
                                decoration: InputDecoration(
                                  labelText: '5 jegyű PIN',
                                  hintText: '•••••',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline_rounded),
                                  counterText: '',
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _obscure = !_obscure,
                                    ),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              _errorBox(theme, dark),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                key: const Key('flow-login-submit'),
                                onPressed:
                                    (_busy || _resumeBusy) ? null : _submit,
                                icon: (_busy || _resumeBusy)
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  _resumeBusy
                                      ? 'MUNKAMENET ELLENŐRZÉSE…'
                                      : _busy
                                          ? 'BELÉPÉS…'
                                          : 'BELÉPÉS',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'A FLOW ID-t és az első PIN-t az iroda küldi '
                                'e-mailben. A sikeres belépés után ez a telefon '
                                'megjegyzi a munkamenetet; a PIN-t nem tárolja.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: _openAdmin,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('IRODAI AIMS FLOW ADMIN'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
