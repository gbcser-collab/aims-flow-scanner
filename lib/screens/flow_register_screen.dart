import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/native_auth_service.dart';

class FlowRegisterScreen extends StatefulWidget {
  const FlowRegisterScreen({super.key});

  @override
  State<FlowRegisterScreen> createState() => _FlowRegisterScreenState();
}

class _FlowRegisterScreenState extends State<FlowRegisterScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _auth = NativeAuthService();

  final _company = TextEditingController();
  final _country = TextEditingController(text: 'Hungary');
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _tax = TextEditingController();

  bool _terms = false;
  bool _privacy = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _company.dispose();
    _country.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _tax.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF9EDBFF)),
        filled: true,
        fillColor: const Color(0xFF0A2236),
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF245A78)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      );

  Future<void> _open(String path) async {
    final uri = Uri.parse('https://logistic-aims.hu/$path');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _validPhone(String value) {
    var phone = value.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (phone.startsWith('00')) phone = '+' + phone.substring(2);
    return RegExp(r'^\+[1-9][0-9]{7,14}
        _country.text.trim().isEmpty ||
        _contact.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _email.text.trim().isEmpty) {
      setState(() => _error = 'Töltsd ki a kötelező mezőket.');
      return;
    }
    if (!_validPhone(_phone.text)) {
      setState(
        () => _error =
            'A telefonszámot nemzetközi formátumban add meg, például: +36 30 123 4567.',
      );
      return;
    }
    if (!_terms || !_privacy) {
      setState(() => _error = 'A feltételek és az adatkezelés elfogadása szükséges.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _auth.register(
        companyName: _company.text,
        country: _country.text,
        contactName: _contact.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        taxNumber: _tax.text,
        terms: _terms,
        privacy: _privacy,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF071522),
          title: Text(
            result.reactivated ? 'Fiók újraregisztrálva' : 'Regisztráció elküldve',
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w900),
          ),
          content: Text(
            '${result.message}'
            '${result.username.isNotEmpty ? '\n\nA.I.M.S. azonosító: ${result.username}' : ''}',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('RENDBEN'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      appBar: AppBar(
        title: const Text(
          'REGISZTRÁCIÓ',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'AIMS Flow fiók',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Ugyanez a fiók működik a Logistic-AIMS webes partnerfelületén is. '
                      'Partner/sofőr fióknál nincs kétfaktoros belépés.',
                      style: TextStyle(color: Colors.white54, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('flow-register-company'),
                      controller: _company,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Cégnév *', Icons.business_outlined),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _country,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Ország *', Icons.public_rounded),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _contact,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Kapcsolattartó neve *', Icons.person_outline),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Telefon *', Icons.phone_outlined).copyWith(
                        hintText: '+36 30 123 4567',
                        helperText: 'Nemzetközi formátum (+országkód)',
                        helperStyle: const TextStyle(color: Colors.white38),
                      ),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      key: const Key('flow-register-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('E-mail *', Icons.alternate_email_rounded),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _address,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Székhely / cím', Icons.location_on_outlined),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _tax,
                      textInputAction: TextInputAction.done,
                      decoration: _decoration('Adószám', Icons.receipt_long_outlined),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: _terms,
                      onChanged: (v) => setState(() => _terms = v == true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Elfogadom a partnerfelület használati feltételeit.'),
                    ),
                    TextButton(
                      onPressed: () => _open('legal/partner-terms.html'),
                      child: const Text('FELTÉTELEK MEGNYITÁSA ↗'),
                    ),
                    CheckboxListTile(
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v == true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Tudomásul vettem az adatkezelési tájékoztatót.'),
                    ),
                    TextButton(
                      onPressed: () => _open('legal/privacy.html'),
                      child: const Text('ADATKEZELÉS MEGNYITÁSA ↗'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('flow-register-submit'),
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00131F),
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_busy ? 'KÜLDÉS…' : 'REGISZTRÁCIÓ ELKÜLDÉSE'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        backgroundColor: _blue,
                        foregroundColor: const Color(0xFF00131F),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A regisztráció jóváhagyás után válik aktívvá. '
                      'Ha korábban törölted ugyanezt a fiókot, az e-mail címmel újraregisztrálható.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, height: 1.4, fontSize: 11),
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
).hasMatch(phone);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_company.text.trim().isEmpty ||
        _country.text.trim().isEmpty ||
        _contact.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _email.text.trim().isEmpty) {
      setState(() => _error = 'Töltsd ki a kötelező mezőket.');
      return;
    }
    if (!_terms || !_privacy) {
      setState(() => _error = 'A feltételek és az adatkezelés elfogadása szükséges.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _auth.register(
        companyName: _company.text,
        country: _country.text,
        contactName: _contact.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        taxNumber: _tax.text,
        terms: _terms,
        privacy: _privacy,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF071522),
          title: Text(
            result.reactivated ? 'Fiók újraregisztrálva' : 'Regisztráció elküldve',
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w900),
          ),
          content: Text(
            '${result.message}'
            '${result.username.isNotEmpty ? '\n\nA.I.M.S. azonosító: ${result.username}' : ''}',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('RENDBEN'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020813),
      appBar: AppBar(
        title: const Text(
          'REGISZTRÁCIÓ',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071E3D), Color(0xFF030A13), Color(0xFF02070E)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'AIMS Flow fiók',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Ugyanez a fiók működik a Logistic-AIMS webes partnerfelületén is. '
                      'Partner/sofőr fióknál nincs kétfaktoros belépés.',
                      style: TextStyle(color: Colors.white54, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('flow-register-company'),
                      controller: _company,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Cégnév *', Icons.business_outlined),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _country,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Ország *', Icons.public_rounded),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _contact,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Kapcsolattartó neve *', Icons.person_outline),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Telefon *', Icons.phone_outlined),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      key: const Key('flow-register-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('E-mail *', Icons.alternate_email_rounded),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _address,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Székhely / cím', Icons.location_on_outlined),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _tax,
                      textInputAction: TextInputAction.done,
                      decoration: _decoration('Adószám', Icons.receipt_long_outlined),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: _terms,
                      onChanged: (v) => setState(() => _terms = v == true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Elfogadom a partnerfelület használati feltételeit.'),
                    ),
                    TextButton(
                      onPressed: () => _open('legal/partner-terms.html'),
                      child: const Text('FELTÉTELEK MEGNYITÁSA ↗'),
                    ),
                    CheckboxListTile(
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v == true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Tudomásul vettem az adatkezelési tájékoztatót.'),
                    ),
                    TextButton(
                      onPressed: () => _open('legal/privacy.html'),
                      child: const Text('ADATKEZELÉS MEGNYITÁSA ↗'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('flow-register-submit'),
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00131F),
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_busy ? 'KÜLDÉS…' : 'REGISZTRÁCIÓ ELKÜLDÉSE'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        backgroundColor: _blue,
                        foregroundColor: const Color(0xFF00131F),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A regisztráció jóváhagyás után válik aktívvá. '
                      'Ha korábban törölted ugyanezt a fiókot, az e-mail címmel újraregisztrálható.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, height: 1.4, fontSize: 11),
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
