import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/flow_preferences.dart';
import '../services/flow_auth_service.dart';
import '../services/vehicle_tracking_service.dart';

import '../services/aims_display_mode.dart';
import '../services/aims_locale.dart';
import '../services/device_unlock_service.dart';
import '../services/driver_push_service.dart';
import '../services/native_auth_service.dart';
import 'driver_shell_screen.dart';
import 'flow_register_screen.dart';

class FlowLoginScreen extends StatefulWidget {
  const FlowLoginScreen({super.key});

  @override
  State<FlowLoginScreen> createState() => _FlowLoginScreenState();
}

class _FlowLoginScreenState extends State<FlowLoginScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _auth = NativeAuthService();
  static final Uint8List _logo = base64Decode(
    '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',
  );

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
    if (_autoUnlockTried || !mounted || _busy) return;
    _autoUnlockTried = true;
    var ownsBusy = false;
    try {
      if (!await FlowAuthService.instance.hasStoredSession()) return;
      if (!await DeviceUnlockService.instance.isAvailable() || !mounted) return;
      if (_busy || _adminMode) return;
      ownsBusy = true;
      setState(() => _busy = true);
      if (!await DeviceUnlockService.instance.authenticate() || !mounted)
        return;
      if (!await FlowAuthService.instance.restore() || !mounted) return;
      final session = FlowAuthService.instance.session!;
      await _saveDriverProfile(session);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DriverShellScreen(
            initialPlate: session.plate,
            initialDriverName: session.displayName,
          ),
        ),
      );
    } catch (_) {
      /* Manual FLOW ID + PIN remains available. */
    } finally {
      if (ownsBusy && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDriverProfile(FlowAuthSession session) async {
    final prefs = await FlowPreferences.getInstance();
    await prefs.setString('aims_driver_plate', session.plate);
    await prefs.setString('aims_driver_name', session.displayName);
    await prefs.setString('aims_flow_id', session.flowId);
    await prefs.setString('aims_user_role', 'driver');
    await AimsLocaleController.instance.setLanguage(session.language);
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final t = AimsLocaleController.instance.t;
    if (_adminMode
        ? _password.text.isEmpty
        : !FlowAuthService.credentialsValid(_login.text, _password.text)) {
      setState(
        () => _error = t(
          _adminMode ? 'admin_password_required' : 'invalid_driver_fields',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await VehicleTrackingService.instance.disable();
      if (_adminMode) {
        final push = await DriverPushService.instance
            .adminRegistrationPayload();
        final result = await _auth.login(
          login: 'ADMIN',
          password: _password.text,
          code: _code.text,
          pushDeviceId: push['deviceId'] ?? '',
          fcmToken: push['fcmToken'] ?? '',
          pushPlatform: push['platform'] ?? 'android',
        );
        if (result.role != 'admin' || !result.adminPushRegistered) {
          throw StateError(
            'Az admin belépés vagy push regisztráció nem sikerült.',
          );
        }
        await FlowAuthService.instance.clear();
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const DriverShellScreen(adminMode: true),
          ),
        );
      } else {
        FlowAuthSession session;
        try {
          session = await FlowAuthService.instance.login(
            _login.text,
            _password.text,
          );
        } finally {
          _password.clear();
        }
        await _saveDriverProfile(session);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DriverShellScreen(
              initialPlate: session.plate,
              initialDriverName: session.displayName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      _password.clear();
      _code.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(
    BuildContext context,
    String hint,
    IconData icon,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: dark ? const Color(0xFF9EDBFF) : const Color(0xFF1478FF),
        size: 25,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 54, minHeight: 58),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      filled: true,
      fillColor: dark ? const Color(0xFF0A2236) : const Color(0xFFF5F9FC),
      hintStyle: TextStyle(color: Colors.white),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: dark ? const Color(0xFF245A78) : const Color(0xFFD4E1EA),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AimsLocaleController.instance;
    return AnimatedBuilder(
      animation: locale,
      builder: (context, _) {
        final t = locale.t;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          backgroundColor: dark
              ? const Color(0xFF020813)
              : const Color(0xFFF5F9FC),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [
                        Color(0xFF071E3D),
                        Color(0xFF030A13),
                        Color(0xFF02070E),
                      ]
                    : const [
                        Color(0xFFFFFFFF),
                        Color(0xFFF5FAFE),
                        Color(0xFFEDF5FB),
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip:
                                    'Night Driver Mode: ${AimsDisplayModeController.instance.label(locale.languageCode)}',
                                onPressed: () => AimsDisplayModeController
                                    .instance
                                    .cycleMode(),
                                icon: Icon(
                                  switch (AimsDisplayModeController
                                      .instance
                                      .mode) {
                                    AimsDisplayMode.auto =>
                                      Icons.brightness_auto_rounded,
                                    AimsDisplayMode.light =>
                                      Icons.light_mode_rounded,
                                    AimsDisplayMode.dark =>
                                      Icons.dark_mode_rounded,
                                  },
                                  color:
                                      AimsDisplayModeController.instance.isDark
                                      ? const Color(0xFF8BD8FF)
                                      : const Color(0xFFFFC857),
                                ),
                              ),
                              const AimsLanguageSelector(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Image.memory(_logo, width: 96, height: 96),
                        const SizedBox(height: 14),
                        Text(
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
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.2,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xDD071725)
                                : const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: dark
                                  ? _blue.withValues(alpha: .5)
                                  : const Color(0xFFD7E4ED),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF113A56)
                                    .withValues(alpha: dark ? .12 : .08),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
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
                                style: TextStyle(
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (!_adminMode) ...[
                                TextField(
                                  key: const Key('flow-login-user'),
                                  controller: _login,
                                  keyboardType: TextInputType.number,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9]'),
                                    ),
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                  ),
                                  decoration: _decoration(
                                    context,
                                    'FLOW ID',
                                    Icons.person_outline,
                                  ).copyWith(hintText: '000000'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('flow-login-password'),
                                  controller: _password,
                                  obscureText: _obscure,
                                  keyboardType: TextInputType.number,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.done,
                                  maxLength: 5,
                                  enableIMEPersonalizedLearning: false,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9]'),
                                    ),
                                  ],
                                  onSubmitted: (_) => _submit(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                  ),
                                  decoration:
                                      _decoration(
                                        context,
                                        'PIN',
                                        Icons.key_rounded,
                                      ).copyWith(
                                        counterText: '',
                                        hintText: '•••••',
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
                                        : () => showDialog<void>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: const Text(
                                                'FLOW ID / PIN',
                                              ),
                                              content: Text(t('flow_pin_help')),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('OK'),
                                                ),
                                              ],
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
                                  decoration:
                                      _decoration(
                                        context,
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
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
                                              style: TextStyle(
                                                color: Colors.white,
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
                                    context,
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
                                    color: Colors.white,
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
                                  minimumSize: const Size.fromHeight(64),
                                  backgroundColor: _blue,
                                  foregroundColor: Colors.white,
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
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                label: Text(t('register')),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(58),
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
                          style: TextStyle(
                            color: Colors.white,
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
