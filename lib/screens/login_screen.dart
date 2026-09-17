import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cmr_sync_service.dart';
import '../services/local_auth_service.dart';
import '../widgets/aims_skin.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _otp = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());
  bool _hidePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    for (final c in _otp) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  String get _code => _otp.map((e) => e.text).join();

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await LocalAuthService.instance.login(
        username: _user.text,
        password: _password.text,
        code: _code,
      );
      if (!ok && mounted) {
        setState(() => _error = 'A felhasználónév, jelszó vagy 2FA kód nem megfelelő.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Belépési hiba: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _help() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'office@logistic-aims.hu',
      queryParameters: {'subject': 'AIMS Flow belépési segítség'},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _error = 'Nem található használható e-mail alkalmazás. Írj az office@logistic-aims.hu címre.');
    }
  }

  Future<void> _setupDevice() async {
    final user = TextEditingController();
    final pass = TextEditingController();
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF071B35),
        title: const Text('Új eszköz hozzáadása', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ezen a készüléken létrejön a helyi admin belépés. A 2FA-t egy hitelesítő alkalmazással kell párosítani.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(controller: user, style: const TextStyle(color: Colors.white), decoration: aimsInputDecoration('Felhasználónév')),
            const SizedBox(height: 10),
            TextField(controller: pass, obscureText: true, style: const TextStyle(color: Colors.white), decoration: aimsInputDecoration('Jelszó')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tovább')),
        ],
      ),
    );
    if (first != true) {
      user.dispose();
      pass.dispose();
      return;
    }

    try {
      final secret = await LocalAuthService.instance.beginSetup(username: user.text, password: pass.text);
      try {
        await const CmrSyncService().syncPending();
      } catch (_) {}
      if (!mounted) return;
      final codeController = TextEditingController();
      final uri = LocalAuthService.instance.otpauthUri(user.text.trim(), secret);
      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF071B35),
          title: const Text('2FA párosítás', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add hozzá az AIMS Flow fiókot Google Authenticatorhoz, Microsoft Authenticatorhoz vagy más TOTP alkalmazáshoz.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                SelectableText(secret, textAlign: TextAlign.center, style: const TextStyle(color: aimsCyan, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: secret));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Titkos kulcs másolása'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: uri));
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('otpauth hivatkozás másolása'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, letterSpacing: 8, fontWeight: FontWeight.w900),
                  decoration: aimsInputDecoration('6 jegyű ellenőrző kód'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                try {
                  await LocalAuthService.instance.confirmSetup(codeController.text);
                  if (context.mounted) Navigator.pop(context, true);
                } on FormatException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('Aktiválás'),
            ),
          ],
        ),
      );
      codeController.dispose();
      if (verified == true && mounted) {
        _user.text = user.text.trim();
        _password.clear();
        for (final c in _otp) c.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Az eszköz és a 2FA belépés elkészült.')));
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Az eszköz hozzáadása nem sikerült: $e');
    } finally {
      user.dispose();
      pass.dispose();
    }
  }

  Widget _otpBox(int index) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
        child: TextField(
          controller: _otp[index],
          focusNode: _otpFocus[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0xAA10345F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5BD9FF))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF4AC9FF))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: aimsCyan, width: 1.6)),
          ),
          onChanged: (value) {
            if (value.isNotEmpty && index < 5) _otpFocus[index + 1].requestFocus();
            if (value.isEmpty && index > 0) _otpFocus[index - 1].requestFocus();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aimsNavy,
      body: AimsBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    const AimsFakeStatusBar(),
                    const SizedBox(height: 38),
                    const AimsFlowMark(size: 116),
                    const SizedBox(height: 18),
                    const Text('Belépés', style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -.8)),
                    const SizedBox(height: 5),
                    const Text('AIMS Flow Smart Scanner', style: TextStyle(color: Color(0xFFC2E2FF), fontSize: 23, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 20),
                    const Text('G Y O R S A B B   F O L Y A M A T O K .\nO K O S A B B   M Ű K Ö D É S .', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8EC9FF), fontSize: 11, height: 1.7, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    AimsGlassCard(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _user,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            decoration: aimsInputDecoration('Felhasználó', prefix: const Icon(Icons.person_outline_rounded, color: Color(0xFFB7E6FF))),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _hidePassword,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            decoration: aimsInputDecoration(
                              'Jelszó',
                              prefix: const Icon(Icons.lock_outline_rounded, color: Color(0xFFB7E6FF)),
                              suffix: IconButton(
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                icon: Icon(_hidePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFFB7E6FF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Color(0xFFB7E6FF)),
                              SizedBox(width: 9),
                              Text('2FA kód', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(children: List.generate(6, _otpBox)),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8E9A), fontWeight: FontWeight.w700)),
                          ],
                          const SizedBox(height: 14),
                          AimsNeonButton(
                            label: _busy ? 'Belépés…' : 'Tovább',
                            onPressed: _busy ? null : _login,
                            leading: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(height: 1, color: const Color(0xFF5BB8FF).withValues(alpha: .55)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _setupDevice,
                            icon: const Icon(Icons.phonelink_setup_rounded, color: Color(0xFFB7E6FF), size: 31),
                            label: const Text('Új eszköz\nhozzáadása', style: TextStyle(color: Color(0xFFD4ECFF), fontSize: 16)),
                          ),
                        ),
                        Container(width: 1, height: 58, color: const Color(0xFF5BB8FF).withValues(alpha: .55)),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _help,
                            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF9CCBFF), size: 31),
                            label: const Text('Segítség\nbelépéshez', style: TextStyle(color: Color(0xFFD4ECFF), fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('—   A I M S   F L O W   —\nS C A N N E R', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF78AEE4), fontSize: 10, letterSpacing: 2, height: 1.5)),
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
