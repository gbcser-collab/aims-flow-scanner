import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/aims_locale.dart';
import '../services/native_auth_service.dart';

class FlowForgotCodeScreen extends StatefulWidget {
  const FlowForgotCodeScreen({super.key, this.initialPlate = ''});

  final String initialPlate;

  @override
  State<FlowForgotCodeScreen> createState() => _FlowForgotCodeScreenState();
}

class _FlowForgotCodeScreenState extends State<FlowForgotCodeScreen> {
  static const _auth = NativeAuthService();
  late final TextEditingController _plate;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plate = TextEditingController(text: widget.initialPlate);
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AimsLocaleController.instance.t;
    final plate = _plate.text.trim().toUpperCase();
    if (plate.length < 4) {
      setState(() => _error = t('plate_error'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.requestForgotCode(plate: plate);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AimsLocaleController.instance;
    final t = locale.t;
    return AnimatedBuilder(
      animation: locale,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(t('forgot_title')),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 10),
              child: AimsLanguageSelector(compact: true),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              t('forgot_desc'),
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
                LengthLimitingTextInputFormatter(12),
              ],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
              decoration: InputDecoration(
                labelText: t('plate'),
                hintText: t('plate_hint'),
                prefixIcon: const Icon(Icons.local_shipping_outlined),
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: 16),
              Text(
                t('forgot_sent'),
                style: const TextStyle(
                  color: Color(0xFF4DE3A4),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: Text(_busy ? t('sending') : t('request_reset')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
            ),
          ],
        ),
      ),
    );
  }
}