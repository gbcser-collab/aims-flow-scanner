import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/aims_locale.dart';
import '../services/device_unlock_service.dart';
import '../services/native_auth_service.dart';
import 'driver_shell_screen.dart';
import 'flow_change_code_screen.dart';
import 'flow_forgot_code_screen.dart';
import 'flow_register_screen.dart';

class FlowLoginScreen extends StatefulWidget {
  const FlowLoginScreen({super.key});

  @override
  State<FlowLoginScreen> createState() => _FlowLoginScreenState();
}

class _FlowLoginScreenState extends State<FlowLoginScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _auth = NativeAuthService();
  static const _e2e =
      bool.fromEnvironment('AIMS_E2E_TEST', defaultValue: false);
  static final Uint8List _logo = base64Decode('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');

  final _login = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _adminMode = false;
  bool _autoUnlockTried = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryDeviceUnlock();
    });
  }

  Future<void> _tryDeviceUnlock() async {
    if (_e2e || _autoUnlockTried || !mounted) return;
    _autoUnlockTried = true;
    final prefs = await SharedPreferences.getInstance();
    final plate = (prefs.getString('aims_driver_plate') ?? '').trim();
    final enabled = prefs.getBool('aims_driver_local_unlock') ?? false;
    if (plate.isEmpty || !enabled || !mounted) return;

    final available = await DeviceUnlockService.instance.isAvailable();
    if (!available || !mounted) return;

    final ok = await DeviceUnlockService.instance.authenticate();
    if (!ok || !mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverShellScreen()),
    );
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<String?> _askDriverName() async {
    final t = AimsLocaleController.instance.t;
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(
      text: prefs.getString('aims_driver_name') ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071522),
        title: Text(t('driver_name_question')),
        content: TextField(
          key: const Key('flow-driver-name'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: t('driver_name'),
            hintText: t('driver_name_hint'),
            counterText: '',
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: Text(t('continue')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final t = AimsLocaleController.instance.t;
    if (!_e2e) {
      if (_adminMode) {
        if (_password.text.isEmpty) {
          setState(() => _error = t('admin_password_required'));
          return;
        }
      } else {
        final plate = _login.text.trim();
        final accessCode = _password.text.trim().toUpperCase();
        if (plate.length < 4 || accessCode.length != 6) {
          setState(
            () => _error = t('invalid_driver_fields'),
          );
          return;
        }
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      NativeAuthResult? authResult;
      if (!_e2e) {
        authResult = await _auth.login(
          login: _adminMode ? 'ADMIN' : _login.text,
          password: _adminMode
              ? _password.text
              : _password.text.trim().toUpperCase(),
          code: _adminMode ? _code.text : '',
        );
      }
      if (!mounted) return;

      if (!_e2e && authResult?.role == 'driver') {
        final driver = authResult!;
        if (driver.forceCodeChange) {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => FlowChangeCodeScreen(
                plate: driver.plate,
                currentCode: _password.text.trim().toUpperCase(),
              ),
            ),
          );
          if (!mounted || changed != true) return;
        }

        final name = await _askDriverName();
        if (!mounted || name == null || name.isEmpty) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'aims_driver_plate',
          driver.plate.trim().toUpperCase(),
        );
        await prefs.setString('aims_driver_name', name);
        await prefs.setBool('aims_driver_local_unlock', true);
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverShellScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      final value = e.toString().replaceFirst('Bad state: ', '');
      setState(() => _error = value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF9EDBFF)),
        filled: true,
        fillColor: const Color(0xFF0A2236),
        hintStyle: const TextStyle(color: Colors.white38),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF245A78)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final locale = AimsLocaleController.instance;
    return AnimatedBuilder(
      animation: locale,
      builder: (context, _) {
        final t = locale.t;
        return Scaffold(
          backgroundColor: const Color(0xFF020813),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF071E3D),
                  Color(0xFF030A13),
                  Color(0xFF02070E),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: AimsLanguageSelector(),
                        ),
                        const SizedBox(height: 12),
                        Image.memory(_logo, width: 118, height: 118),
                        const SizedBox(height: 14),
                        const Text(
                          'AIMS FLOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'DRIVER OPERATIONS',
                          style: TextStyle(
                            color: _blue,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.2,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xDD071725),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _blue.withValues(alpha: .5),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _blue.withValues(alpha: .12),
                                blurRadius: 30,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                t('login'),
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t(
                                  _adminMode
                                      ? 'admin_login_help'
                                      : 'driver_login_help',
                                ),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (!_adminMode) ...[
                                TextField(
                                  key: const Key('flow-login-user'),
                                  controller: _login,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(12),
                                  ],
                                  decoration: _decoration(
                                    t('plate'),
                                    Icons.local_shipping_outlined,
                                  ).copyWith(
                                    hintText: t('plate_hint'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('flow-login-password'),
                                  controller: _password,
                                  obscureText: _obscure,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textInputAction: TextInputAction.done,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9]'),
                                    ),
                                  ],
                                  onSubmitted: (_) => _submit(),
                                  decoration: _decoration(
                                    t('driver_code'),
                                    Icons.key_rounded,
                                  ).copyWith(
                                    counterText: '',
                                    hintText: t('driver_code_hint'),
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
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    key: const Key('flow-forgot-code-open'),
                                    onPressed: _busy
                                        ? null
                                        : () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    FlowForgotCodeScreen(
                                                  initialPlate: _login.text,
                                                ),
                                              ),
                                            ),
                                    icon: const Icon(
                                      Icons.help_outline_rounded,
                                      size: 18,
                                    ),
                                    label: Text(t('forgot_code')),
                                  ),
                                ),
                              ] else ...[
                                TextField(
                                  key: const Key('flow-login-password'),
                                  controller: _password,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.next,
                                  decoration: _decoration(
                                    t('admin_password'),
                                    Icons.lock_outline_rounded,
                                  ).copyWith(
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
                              ],
                              const SizedBox(height: 10),
                              InkWell(
                                key: const Key('flow-admin-toggle'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: _busy
                                    ? null
                                    : () => setState(() {
                                          _adminMode = !_adminMode;
                                          _password.clear();
                                          _code.clear();
                                        }),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.admin_panel_settings_outlined,
                                        color: Color(0xFF9EDBFF),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t('admin_login'),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              t('admin_2fa_note'),
                                              style: const TextStyle(
                                                color: Colors.white38,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _adminMode,
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(() {
                                                  _adminMode = value;
                                                  _password.clear();
                                                  _code.clear();
                                                }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_adminMode) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  key: const Key('flow-login-2fa'),
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  decoration: _decoration(
                                    t('authenticator_code'),
                                    Icons.shield_outlined,
                                  ).copyWith(counterText: ''),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                key: const Key('flow-login-submit'),
                                onPressed: _busy ? null : _submit,
                                icon: _busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF00131F),
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  t(_busy ? 'signing_in' : 'sign_in'),
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(58),
                                  backgroundColor: _blue,
                                  foregroundColor: const Color(0xFF00131F),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('flow-register-open'),
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FlowRegisterScreen(),
                                          ),
                                        ),
                                icon:
                                    const Icon(Icons.person_add_alt_1_rounded),
                                label: Text(t('register')),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: _blue),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          t('driver_footer'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            height: 1.45,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
