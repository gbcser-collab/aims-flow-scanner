import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/native_auth_service.dart';
import 'driver_shell_screen.dart';

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
  static final Uint8List _logo = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAdpQTFRFAAAAVMX4VMX4AUN3AVGRAVaaAVebKbb2VMX4FmOXVMX4VMX4Kbb2AUuGAUuHAVWXAVebFmyWKbb2LLf2VMX4AClIACxOACxPAC1QAC5RAC5SAC9TAC9UADBWADFWADFXADNaADVeADZgADdgADtpADx');

  final _login = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_e2e && (_login.text.trim().isEmpty || _password.text.isEmpty)) {
      setState(() => _error = 'Add meg a webes felhasználónevet/e-mailt és jelszót.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_e2e) {
        await _auth.login(
          login: _login.text,
          password: _password.text,
          code: _code.text,
        );
      }
      if (!mounted) return;
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
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
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
                        border: Border.all(color: _blue.withValues(alpha: .5)),
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
                          const Text(
                            'Belépés',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Ugyanazzal a Logistic-AIMS webes fiókkal. Nincs készülék-jóváhagyás.',
                            style: TextStyle(color: Colors.white54, height: 1.4),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            key: const Key('flow-login-user'),
                            controller: _login,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration(
                              'Felhasználónév vagy e-mail',
                              Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('flow-login-password'),
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration(
                              'Jelszó',
                              Icons.lock_outline_rounded,
                            ).copyWith(
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('flow-login-2fa'),
                            controller: _code,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: _decoration(
                              '2FA kód – admin fióknál',
                              Icons.shield_outlined,
                            ).copyWith(counterText: ''),
                          ),
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
                            label: Text(_busy ? 'BELÉPÉS…' : 'BELÉPÉS'),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'A webes admin fióknál a 6 jegyű Authenticator-kód is kell. '
                      'Partnerfióknál a 2FA mező üresen hagyható.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
  }
}
