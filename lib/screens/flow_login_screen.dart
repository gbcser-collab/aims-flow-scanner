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
  static final Uint8List _logo = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAdpQTFRFAAAAVMX4VMX4AUN3AVGRAVaaAVebKbb2VMX4FmOXVMX4VMX4Kbb2AUuGAUuHAVWXAVebFmyWKbb2LLf2VMX4AClIACxOACxPAC1QAC5RAC5SAC9TAC9UADBWADFWADFXADNaADVeADZgADdgADtpADxsASZCASZDASpJATFXATRbATRcATRdATVfATZgAThjAThkATlmATpnATpoATtpATxqAT1sAT1tAT5tAT5uAT5vAT9vAT9wAUByAUFzAUF0AUJ1AUJ2AUR5AUR6AUV6AUV7AUZ8AUd+AUd/AUiAAUiBAUmCAUmDAUqDAUqEAUqFAUuEAUuFAUuGAUuHAUyHAUyIAUyJAU2IAU2JAU2KAU6KAU6LAU6MAU+MAU+NAVCOAVCPAVCQAVGPAVGQAVGRAVKRAVKSAVOSAVOTAVOUAVOVAVSUAVSVAVSWAVWWAVWXAVWYAVWZAVaYAVaZAVaaAVeaAVebAi5PAjFWAjRbAjdgAjpkAjxoAj5rAkBuAkFxAkJzAkN1AkR2AkV4AkZ5AkZ6Akd6FmiPFmmQF22WF3CbGHOfGXajGXmnGXuqGn2tGn+wGoCyG4K0G4O2G4S3G4W4G4W5G4a6HIa7H4vAKbb2LLf2TML4VMX4KQGaCAAAABV0Uk5TABAgMDAwMDAwQEDP3+/v7+/v7+/v7Yl3rQAAAz5JREFUeNrt1AdTE1EUhmFEQKygYi9YsTewYcOAEBBRg6KIkASBmKhhkazXLnbsvUb8r2bNMASy2b33zmzmnJnv+wF7nnd2dgsKMAzL60or/uqtohR++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++OGHH3744Ycffvjhhx9++Gn7C2dprpCGX/uhs6fBDz/88HPxa9+i4te9Rsevd4+SX+ciLb/6TWp+1av0/Gp3KfpVLtP0y9+m6pe9Ttcvd5+yX0ZA2+9uoO53U9D3Ozuc/DMWjpHwOxU4+hck/4yR8OcucPEntQo88OcqcPXrFHjity+Q8KsXeOS3K5DyqxZ45s8ukPSrFXjon1og7Vcp8NQ/uUDBL1/gsT+zQMkvW+C5f6JA0S9XkAf/eIGyX6YgL/50gYbfvSBPfqtAy+9WkDd/qkDP71yQR7/THP1OBTz8uQu4+HMV8PHbF3Dy2xXw8mcXcPNPLeDnn1zA0Z9ZwNM/UcDVP17A158u4OyCoj4C+Yk9fZ7Jg2/7hv49XJuEeeCny/a+8qK+RZY/kGzvIRrwY/n7b3xhBBcC74/O5vy3xJcC749bQvFb5pWAMuCr09ag9eHzHQAw4Ivj1u6o0YiFcCz4POIv6s/PjwRwKzg06OmjiuxwcwAVgUfH9YHgpGYYWQGMCr48MDX2hWOxuLGsDn+FXMqeH//qP9cT+/VrAAmBe/uHWw4dSHYF8kOYFHw9u5eX/OZzmA4ErthTPqKeRS8ubPrSENLoLMnPGAXQL7g9e3t++oaTwY6u8MDUbsA4gWvNm/ZXetrbDl9sTvUH72W/o8KwaZgdNOSbdWHrICOy6E+6z9qiuzRLRitWrRyR83h4yea285bAUZC2I5qQcq/ePXOmtq6Bn8qIDIkco5mgeVfVrmu+sCxen9X1BROo1jw37+8cu2e/c2hhHAbvYK0f8WqDW1DQmbUCtL+9U0RITtaBZZ/jU9eT61gtGrpxkumUBydgvlbG/sNZT+hgunztPyECorKtPyECorLBfOCEhSgAAUoQAEKUIACFKAABShAAZkCDKO1f/OiyBBYvwCtAAAAAElFTkSuQmCC');

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
