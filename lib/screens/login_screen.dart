import 'package:flutter/material.dart';

import '../services/cmr_sync_service.dart';
import '../services/device_identity_service.dart';
import '../widgets/aims_flow_skin.dart';
import 'device_gate.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _code = List.generate(6, (_) => TextEditingController());
  final _focus = List.generate(6, (_) => FocusNode());
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    for (final c in _code) c.dispose();
    for (final f in _focus) f.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final pin = _code.map((c) => c.text).join();
    if (_user.text.trim().isEmpty || _password.text.isEmpty || pin.length != 6) {
      setState(() => _error = 'Add meg a felhasználónevet, jelszót és a 6 jegyű 2FA kódot.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      const sync = CmrSyncService();
      await sync.syncPending();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DeviceGate(child: HomeScreen())),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'A belépés ellenőrzése most nem érhető el. Ellenőrizd a kapcsolatot.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDevice() async {
    final id = await const DeviceIdentityService().getOrCreateId();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF081A2B),
        title: const Text('Új eszköz hozzáadása', style: TextStyle(color: Colors.white)),
        content: SelectableText('Készülékazonosító:\n$id\n\nEzt az azonosítót az AIMS admin felületen kell jóváhagyni.', style: const TextStyle(color: Colors.white70)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Rendben'))],
      ),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF081A2B),
        title: const Text('Segítség belépéshez', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Ellenőrizd a felhasználónevet, jelszót és a 6 jegyű 2FA kódot. Új telefon esetén előbb add hozzá és hagyd jóvá az eszközt az admin felületen.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AimsFlowSkin.background,
      body: AimsFlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    const FlutterLogo(size: 110),
                    const SizedBox(height: 26),
                    const Text('Belépés', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text('AIMS Flow Smart Scanner', style: TextStyle(color: Color(0xFFC9EAFF), fontSize: 21)),
                    const SizedBox(height: 14),
                    const Text(
                      'G Y O R S A B B  F O L Y A M A T O K.\nO K O S A B B  M Ű K Ö D É S.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 11, height: 1.75, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AimsFlowSkin.glass(radius: 25),
                      child: Column(
                        children: [
                          _fieldLabel(Icons.person_outline_rounded, 'Felhasználó'),
                          _textField(_user, 'Felhasználónév'),
                          const SizedBox(height: 16),
                          _fieldLabel(Icons.lock_outline_rounded, 'Jelszó'),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            style: const TextStyle(color: Colors.white, fontSize: 17),
                            decoration: _inputDecoration('Jelszó').copyWith(
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscure = !_obscure),
                                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AimsFlowSkin.paleBlue),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _fieldLabel(Icons.shield_outlined, '2FA kód'),
                          Row(
                            children: List.generate(6, (index) {
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                                  child: TextField(
                                    controller: _code[index],
                                    focusNode: _focus[index],
                                    keyboardType: TextInputType.number,
                                    maxLength: 1,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                    decoration: _inputDecoration('•').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(vertical: 18)),
                                    onChanged: (value) {
                                      if (value.isNotEmpty && index < 5) _focus[index + 1].requestFocus();
                                      if (value.isEmpty && index > 0) _focus[index - 1].requestFocus();
                                    },
                                  ),
                                ),
                              );
                            }),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                          ],
                          const SizedBox(height: 20),
                          AimsGlowButton(label: 'Tovább', icon: Icons.login_rounded, onPressed: _continue, busy: _busy),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(height: 1, color: AimsFlowSkin.paleBlue.withValues(alpha: .45)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: _bottomAction(Icons.phonelink_setup_rounded, 'Új eszköz\nhozzáadása', _showDevice)),
                        Container(width: 1, height: 68, color: AimsFlowSkin.paleBlue.withValues(alpha: .35)),
                        Expanded(child: _bottomAction(Icons.help_outline_rounded, 'Segítség\nbelépéshez', _showHelp)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('A I M S   F L O W\nS C A N N E R', textAlign: TextAlign.center, style: TextStyle(color: AimsFlowSkin.paleBlue, fontSize: 10, letterSpacing: 4, height: 1.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [Icon(icon, color: AimsFlowSkin.paleBlue), const SizedBox(width: 9), Text(text, style: const TextStyle(color: Colors.white, fontSize: 16))]),
      );

  Widget _textField(TextEditingController controller, String hint) => TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: _inputDecoration(hint),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AimsFlowSkin.paleBlue.withValues(alpha: .6)),
        filled: true,
        fillColor: const Color(0xFF123253).withValues(alpha: .72),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF62CFFF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AimsFlowSkin.cyan, width: 1.5)),
      );

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: AimsFlowSkin.paleBlue, size: 31),
            const SizedBox(width: 11),
            Text(label, style: const TextStyle(color: Color(0xFFC9EAFF), fontSize: 15, height: 1.35)),
          ]),
        ),
      );
}
