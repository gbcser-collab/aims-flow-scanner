import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/aims_locale.dart';
import '../services/native_auth_service.dart';

class FlowChangeCodeScreen extends StatefulWidget {
  const FlowChangeCodeScreen({
    super.key,
    required this.plate,
    required this.currentCode,
  });

  final String plate;
  final String currentCode;

  @override
  State<FlowChangeCodeScreen> createState() => _FlowChangeCodeScreenState();
}

class _FlowChangeCodeScreenState extends State<FlowChangeCodeScreen> {
  static const _auth = NativeAuthService();
  final _newCode = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newCode.dispose();
    _again.dispose();
    super.dispose();
  }

  bool _valid(String input) {
    final value = input.trim().toUpperCase();
    if (value.length != 6) return false;
    var letters = 0;
    var digits = 0;
    for (final unit in value.codeUnits) {
      if (unit >= 65 && unit <= 90) {
        letters++;
      } else if (unit >= 48 && unit <= 57) {
        digits++;
      } else {
        return false;
      }
    }
    return letters == 3 && digits == 3;
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = AimsLocaleController.instance.t;
    final first = _newCode.text.trim().toUpperCase();
    final second = _again.text.trim().toUpperCase();
    if (!_valid(first)) {
      setState(() => _error = t('code_invalid'));
      return;
    }
    if (first != second) {
      setState(() => _error = t('code_mismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.changeDriverCode(
        plate: widget.plate,
        currentCode: widget.currentCode,
        newCode: first,
      );
      if (mounted) Navigator.pop(context, true);
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
          title: Text(t('change_code_title')),
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
              t('change_code_desc'),
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              t('code_rule'),
              style: const TextStyle(color: Color(0xFF1CB8FF), height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _newCode,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              obscureText: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: InputDecoration(
                labelText: t('new_code'),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _again,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              obscureText: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: t('new_code_again'),
                counterText: '',
              ),
            ),
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
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.password_rounded),
              label: Text(_busy ? t('sending') : t('save_code')),
            ),
          ],
        ),
      ),
    );
  }
}
