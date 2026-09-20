import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/aims_locale.dart';
import '../services/native_auth_service.dart';

class _CountryOption {
  const _CountryOption(this.code, this.hu, this.en, this.de);

  final String code;
  final String hu;
  final String en;
  final String de;

  String label(String language) => switch (language) {
        'en' => en,
        'de' => de,
        _ => hu,
      };

  bool matches(String query) {
    final q = _fold(query);
    return _fold(hu).contains(q) ||
        _fold(en).contains(q) ||
        _fold(de).contains(q) ||
        code.toLowerCase().contains(q);
  }

  static String _fold(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ő', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ű', 'u')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss');
}

const _countries = <_CountryOption>[
  _CountryOption('HU', 'Magyarország', 'Hungary', 'Ungarn'),
  _CountryOption('SK', 'Szlovákia', 'Slovakia', 'Slowakei'),
  _CountryOption('AT', 'Ausztria', 'Austria', 'Österreich'),
  _CountryOption('DE', 'Németország', 'Germany', 'Deutschland'),
  _CountryOption('PL', 'Lengyelország', 'Poland', 'Polen'),
  _CountryOption('CZ', 'Csehország', 'Czechia', 'Tschechien'),
  _CountryOption('RO', 'Románia', 'Romania', 'Rumänien'),
  _CountryOption('SI', 'Szlovénia', 'Slovenia', 'Slowenien'),
  _CountryOption('HR', 'Horvátország', 'Croatia', 'Kroatien'),
  _CountryOption('RS', 'Szerbia', 'Serbia', 'Serbien'),
  _CountryOption('UA', 'Ukrajna', 'Ukraine', 'Ukraine'),
  _CountryOption('LT', 'Litvánia', 'Lithuania', 'Litauen'),
  _CountryOption('LV', 'Lettország', 'Latvia', 'Lettland'),
  _CountryOption('EE', 'Észtország', 'Estonia', 'Estland'),
  _CountryOption('BG', 'Bulgária', 'Bulgaria', 'Bulgarien'),
  _CountryOption('IT', 'Olaszország', 'Italy', 'Italien'),
  _CountryOption('FR', 'Franciaország', 'France', 'Frankreich'),
  _CountryOption('BE', 'Belgium', 'Belgium', 'Belgien'),
  _CountryOption('NL', 'Hollandia', 'Netherlands', 'Niederlande'),
  _CountryOption('LU', 'Luxemburg', 'Luxembourg', 'Luxemburg'),
  _CountryOption('CH', 'Svájc', 'Switzerland', 'Schweiz'),
  _CountryOption('LI', 'Liechtenstein', 'Liechtenstein', 'Liechtenstein'),
  _CountryOption('DK', 'Dánia', 'Denmark', 'Dänemark'),
  _CountryOption('SE', 'Svédország', 'Sweden', 'Schweden'),
  _CountryOption('NO', 'Norvégia', 'Norway', 'Norwegen'),
  _CountryOption('FI', 'Finnország', 'Finland', 'Finnland'),
  _CountryOption('IS', 'Izland', 'Iceland', 'Island'),
  _CountryOption('IE', 'Írország', 'Ireland', 'Irland'),
  _CountryOption('GB', 'Egyesült Királyság', 'United Kingdom', 'Vereinigtes Königreich'),
  _CountryOption('ES', 'Spanyolország', 'Spain', 'Spanien'),
  _CountryOption('PT', 'Portugália', 'Portugal', 'Portugal'),
  _CountryOption('GR', 'Görögország', 'Greece', 'Griechenland'),
  _CountryOption('CY', 'Ciprus', 'Cyprus', 'Zypern'),
  _CountryOption('MT', 'Málta', 'Malta', 'Malta'),
  _CountryOption('AL', 'Albánia', 'Albania', 'Albanien'),
  _CountryOption('BA', 'Bosznia-Hercegovina', 'Bosnia and Herzegovina', 'Bosnien und Herzegowina'),
  _CountryOption('ME', 'Montenegró', 'Montenegro', 'Montenegro'),
  _CountryOption('MK', 'Észak-Macedónia', 'North Macedonia', 'Nordmazedonien'),
  _CountryOption('MD', 'Moldova', 'Moldova', 'Moldau'),
  _CountryOption('TR', 'Törökország', 'Türkiye', 'Türkei'),
  _CountryOption('GE', 'Grúzia', 'Georgia', 'Georgien'),
  _CountryOption('AM', 'Örményország', 'Armenia', 'Armenien'),
  _CountryOption('AZ', 'Azerbajdzsán', 'Azerbaijan', 'Aserbaidschan'),
  _CountryOption('AD', 'Andorra', 'Andorra', 'Andorra'),
  _CountryOption('MC', 'Monaco', 'Monaco', 'Monaco'),
  _CountryOption('SM', 'San Marino', 'San Marino', 'San Marino'),
  _CountryOption('VA', 'Vatikán', 'Vatican City', 'Vatikanstadt'),
  _CountryOption('US', 'Amerikai Egyesült Államok', 'United States', 'Vereinigte Staaten'),
  _CountryOption('CA', 'Kanada', 'Canada', 'Kanada'),
  _CountryOption('MX', 'Mexikó', 'Mexico', 'Mexiko'),
  _CountryOption('BR', 'Brazília', 'Brazil', 'Brasilien'),
  _CountryOption('AR', 'Argentína', 'Argentina', 'Argentinien'),
  _CountryOption('CL', 'Chile', 'Chile', 'Chile'),
  _CountryOption('CN', 'Kína', 'China', 'China'),
  _CountryOption('JP', 'Japán', 'Japan', 'Japan'),
  _CountryOption('KR', 'Dél-Korea', 'South Korea', 'Südkorea'),
  _CountryOption('IN', 'India', 'India', 'Indien'),
  _CountryOption('AE', 'Egyesült Arab Emírségek', 'United Arab Emirates', 'Vereinigte Arabische Emirate'),
  _CountryOption('IL', 'Izrael', 'Israel', 'Israel'),
  _CountryOption('SA', 'Szaúd-Arábia', 'Saudi Arabia', 'Saudi-Arabien'),
  _CountryOption('AU', 'Ausztrália', 'Australia', 'Australien'),
  _CountryOption('NZ', 'Új-Zéland', 'New Zealand', 'Neuseeland'),
  _CountryOption('ZA', 'Dél-Afrika', 'South Africa', 'Südafrika'),
];

class FlowRegisterScreen extends StatefulWidget {
  const FlowRegisterScreen({super.key});

  @override
  State<FlowRegisterScreen> createState() => _FlowRegisterScreenState();
}

class _FlowRegisterScreenState extends State<FlowRegisterScreen> {
  static const _blue = Color(0xFF1CB8FF);
  static const _auth = NativeAuthService();

  final _company = TextEditingController();
  final _plate = TextEditingController();
  final _country = TextEditingController();
  final _countryFocus = FocusNode();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  String _countryCode = '';
  bool _countryTyping = false;
  bool _terms = false;
  bool _privacy = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AimsLocaleController.instance.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (_countryCode.isEmpty) return;
    for (final country in _countries) {
      if (country.code == _countryCode) {
        _country.text = _countryLabel(country);
        _country.selection =
            TextSelection.collapsed(offset: _country.text.length);
        if (mounted) setState(() {});
        return;
      }
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _plate.dispose();
    _country.dispose();
    _countryFocus.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    AimsLocaleController.instance.removeListener(_onLanguageChanged);
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF9EDBFF), size: 24),
        prefixIconConstraints: const BoxConstraints(minWidth: 54, minHeight: 58),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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

  String _countryLabel(_CountryOption country) =>
      country.label(AimsLocaleController.instance.languageCode);

  void _chooseCountry(_CountryOption country, {bool notify = true}) {
    _countryCode = country.code;
    _country.text = _countryLabel(country);
    _country.selection = TextSelection.collapsed(offset: _country.text.length);
    _countryTyping = false;
    if (notify && mounted) setState(() {});
  }

  List<_CountryOption> get _suggestions {
    final query = _country.text.trim();
    if (query.length < 2) return const [];
    return _countries
        .where((country) => country.matches(query))
        .take(5)
        .toList();
  }

  _CountryOption? _resolveCountryText(String value) {
    final folded = _CountryOption._fold(value.trim());
    if (folded.isEmpty) return null;

    for (final country in _countries) {
      if (_CountryOption._fold(country.hu) == folded ||
          _CountryOption._fold(country.en) == folded ||
          _CountryOption._fold(country.de) == folded ||
          country.code.toLowerCase() == folded) {
        return country;
      }
    }

    final matches =
        _countries.where((country) => country.matches(value)).toList();
    if (matches.length == 1) return matches.first;
    return null;
  }

  void _focusCountrySearch() {
    _countryFocus.requestFocus();
    setState(() {
      _country.clear();
      _countryCode = '';
      _countryTyping = true;
    });
  }

  Future<void> _open(String path) async {
    final language = AimsLocaleController.instance.languageCode;
    final uri = Uri.parse('https://logistic-aims.hu/$path?lang=$language');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _validPhone(String value) {
    var phone = value.trim();
    if (phone.startsWith('00')) phone = '+' + phone.substring(2);
    if (!phone.startsWith('+')) return false;

    final digits = phone
        .substring(1)
        .split('')
        .where((ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57)
        .join();

    final stripped = phone
        .substring(1)
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('.', '');

    if (stripped != digits) return false;
    if (digits.length < 8 || digits.length > 15) return false;
    if (digits.startsWith('0')) return false;
    return true;
  }

  bool _validPlate(String value) {
    final normalized =
        value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.length >= 4 && normalized.length <= 12;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final locale = AimsLocaleController.instance;
    final t = locale.t;

    final resolvedCountry = _countryCode.isEmpty
        ? _resolveCountryText(_country.text)
        : null;
    if (resolvedCountry != null) {
      _chooseCountry(resolvedCountry, notify: false);
    }

    final missing = <String>[];
    if (_company.text.trim().isEmpty) missing.add(t('company_name'));
    if (_plate.text.trim().isEmpty) missing.add(t('plate'));
    if (_country.text.trim().isEmpty || _countryCode.isEmpty) {
      missing.add(t('country'));
    }
    if (_contact.text.trim().isEmpty) missing.add(t('contact_name'));
    if (_phone.text.trim().isEmpty) missing.add(t('phone'));
    if (_email.text.trim().isEmpty) missing.add(t('email'));

    if (missing.isNotEmpty) {
      setState(
        () => _error =
            'Hiányzó vagy nem kiválasztott mező: ${missing.join(', ')}.',
      );
      return;
    }
    if (!_validPlate(_plate.text)) {
      setState(() => _error = t('plate_error'));
      return;
    }
    if (!_validPhone(_phone.text)) {
      setState(() => _error = t('phone_error'));
      return;
    }
    if (!_terms || !_privacy) {
      setState(() => _error = t('legal_required'));
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _countryFocus.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _auth.register(
        companyName: _company.text,
        plate: _plate.text,
        country: _country.text,
        contactName: _contact.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        taxNumber: '',
        language: locale.languageCode,
        terms: _terms,
        privacy: _privacy,
      );
      if (!mounted) return;

      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF071522),
          title: Text(
            t(
              result.reactivated
                  ? 'registration_reactivated'
                  : 'registration_sent',
            ),
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            result.message +
                '\n\n' +
                t('plate') +
                ': ' +
                result.plate +
                '\n\n' +
                t('registration_pending'),
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t('ok')),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) {
        await Navigator.of(context).maybePop();
      }
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
    final locale = AimsLocaleController.instance;
    return AnimatedBuilder(
      animation: locale,
      builder: (context, _) {
        final t = locale.t;
        return Scaffold(
          backgroundColor: const Color(0xFF020813),
          appBar: AppBar(
            title: Text(
              t('registration_title'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 10),
                child: AimsLanguageSelector(compact: true),
              ),
            ],
          ),
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
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('registration_account'),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          t('registration_intro'),
                          style: const TextStyle(
                            color: Colors.white54,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('flow-register-company'),
                          controller: _company,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('company_name'),
                            Icons.business_outlined,
                          ),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          key: const Key('flow-register-plate'),
                          controller: _plate,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9 -]'),
                            ),
                            LengthLimitingTextInputFormatter(12),
                          ],
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                          ),
                          decoration: _decoration(
                            t('plate'),
                            Icons.local_shipping_outlined,
                          ).copyWith(hintText: t('plate_hint')),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          key: const Key('flow-register-country'),
                          controller: _country,
                          focusNode: _countryFocus,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('country'),
                            Icons.public_rounded,
                          ).copyWith(
                            hintText: t('country_search'),
                            prefixIcon: IconButton(
                              key: const Key('flow-country-globe'),
                              tooltip: t('country_choose'),
                              onPressed: _focusCountrySearch,
                              icon: const Icon(
                                Icons.public_rounded,
                                color: Color(0xFF9EDBFF),
                              ),
                            ),
                            suffixText: _countryCode,
                          ),
                          onTap: () {
                            if (_countryCode.isNotEmpty ||
                                _country.text.trim().isNotEmpty) {
                              _focusCountrySearch();
                            } else {
                              setState(() => _countryTyping = true);
                            }
                          },
                          onChanged: (_) => setState(() {
                            _countryTyping = true;
                            _countryCode = '';
                          }),
                        ),
                        if (_countryTyping && _suggestions.isNotEmpty)
                          Container(
                            key: const Key('flow-country-suggestions'),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF071522),
                              border: Border.all(
                                color: const Color(0xFF245A78),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: const BoxConstraints(maxHeight: 224),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _suggestions.length,
                              itemBuilder: (context, index) {
                                final country = _suggestions[index];
                                return Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    dense: true,
                                    visualDensity: const VisualDensity(
                                      vertical: -2,
                                    ),
                                    leading: Text(
                                      country.code,
                                      style: const TextStyle(
                                        color: _blue,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    title: Text(_countryLabel(country)),
                                    onTap: () {
                                      _chooseCountry(country);
                                      _countryFocus.unfocus();
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 11),
                        TextField(
                          controller: _contact,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('contact_name'),
                            Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('phone'),
                            Icons.phone_outlined,
                          ).copyWith(
                            hintText: '+36 30 123 4567',
                            helperText: t('phone_helper'),
                            helperStyle:
                                const TextStyle(color: Colors.white38),
                          ),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          key: const Key('flow-register-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('email'),
                            Icons.alternate_email_rounded,
                          ),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          controller: _address,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            t('address'),
                            Icons.location_on_outlined,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: _terms,
                              onChanged: (v) =>
                                  setState(() => _terms = v == true),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t('terms_accept'))),
                          ],
                        ),
                        TextButton(
                          onPressed: () => _open('legal/partner-terms.html'),
                          child: Text(t('open_terms')),
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: _privacy,
                              onChanged: (v) =>
                                  setState(() => _privacy = v == true),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t('privacy_accept'))),
                          ],
                        ),
                        TextButton(
                          onPressed: () => _open('legal/privacy.html'),
                          child: Text(t('open_privacy')),
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
                          label: Text(
                            t(_busy ? 'sending' : 'send_registration'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(64),
                            backgroundColor: _blue,
                            foregroundColor: const Color(0xFF00131F),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t('registration_pending'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            height: 1.4,
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