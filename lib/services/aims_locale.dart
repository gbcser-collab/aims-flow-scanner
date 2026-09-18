import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AimsLocaleController extends ChangeNotifier {
  AimsLocaleController._();

  static final AimsLocaleController instance = AimsLocaleController._();
  static const _prefsKey = 'aims_language';

  String _languageCode = 'hu';

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && const ['hu', 'en', 'de'].contains(saved)) {
      _languageCode = saved;
    }
  }

  Future<void> setLanguage(String value) async {
    if (!const ['hu', 'en', 'de'].contains(value) || value == _languageCode) return;
    _languageCode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    notifyListeners();
  }

  String t(String key, {Map<String, String> vars = const {}}) {
    var value = (_strings[_languageCode] ?? _strings['hu']!)[key] ??
        _strings['hu']![key] ??
        key;
    for (final entry in vars.entries) {
      value = value.replaceAll('{' + entry.key + '}', entry.value);
    }
    return value;
  }

  String get speechLocale => switch (_languageCode) {
        'de' => 'de_DE',
        'en' => 'en_US',
        _ => 'hu_HU',
      };

  String get ttsLocale => switch (_languageCode) {
        'de' => 'de-DE',
        'en' => 'en-US',
        _ => 'hu-HU',
      };
}

class AimsLanguageSelector extends StatelessWidget {
  const AimsLanguageSelector({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final locale = AimsLocaleController.instance;
    return AnimatedBuilder(
      animation: locale,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            const Icon(Icons.language_rounded, size: 18),
            const SizedBox(width: 7),
          ],
          for (final code in const ['hu', 'en', 'de'])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text(code.toUpperCase()),
                selected: locale.languageCode == code,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => locale.setLanguage(code),
              ),
            ),
        ],
      ),
    );
  }
}

const Map<String, Map<String, String>> _strings = {
  'hu': {
    'login': 'Belépés',
    'driver_login_help': 'Sofőr belépés rendszámmal és 6 karakteres kóddal.',
    'admin_login_help': 'Admin belépés jelszóval és Authenticator-kóddal.',
    'plate': 'Rendszám',
    'plate_hint': 'pl. SIP-115',
    'driver_code': 'Sofőr belépőkód',
    'driver_code_hint': 'pl. K4M8T2',
    'admin_login': 'Admin belépés',
    'admin_2fa_note': 'Csak adminnál kell Authenticator-kód.',
    'admin_password': 'Admin jelszó',
    'authenticator_code': '6 jegyű Authenticator-kód',
    'sign_in': 'BELÉPÉS',
    'signing_in': 'BELÉPÉS…',
    'register': 'REGISZTRÁCIÓ',
    'forgot_code': 'ELFELEJTETT KÓD',
    'driver_footer': 'Sofőr: rendszám + pontosan 3 betű és 3 szám. Adminnál külön jelszó + Authenticator marad.',
    'driver_name_question': 'Hogy hívnak?',
    'driver_name': 'Sofőr neve',
    'driver_name_hint': 'pl. Péter',
    'continue': 'MEHET',
    'invalid_driver_fields': 'Add meg a rendszámot és a 6 karakteres sofőrkódot.',
    'admin_password_required': 'Add meg az admin jelszót.',
    'too_many_attempts': 'Túl sok sikertelen próbálkozás. Próbáld meg később.',
    'invalid_credentials': 'Hibás rendszám vagy belépőkód.',
    'temp_expired': 'Az egyszer használatos kód lejárt. Kérj új kódot.',
    'server_unavailable': 'A Logistic-AIMS belépési szerver nem érhető el.',
    'change_code_title': 'Új belépőkód beállítása',
    'change_code_desc': 'Ez egy egyszer használatos kód volt. Mielőtt továbblépsz, állíts be egy új 6 karakteres kódot.',
    'new_code': 'Új kód',
    'new_code_again': 'Új kód újra',
    'save_code': 'KÓD MENTÉSE',
    'code_rule': 'Pontosan 6 karakter: 3 betű + 3 szám, tetszőleges sorrendben.',
    'code_invalid': 'A kód pontosan 3 betűt és 3 számot tartalmazzon.',
    'code_mismatch': 'A két kód nem egyezik.',
    'code_saved': 'Az új belépőkód elmentve.',
    'forgot_title': 'Elfelejtett belépőkód',
    'forgot_desc': 'Add meg a rendszámot. A visszaállítás először admin jóváhagyásra kerül. Jóváhagyás után az új egyszer használatos kód a regisztrált e-mail címre érkezik.',
    'request_reset': 'VISSZAÁLLÍTÁS KÉRÉSE',
    'forgot_sent': 'A kérelmet elküldtük admin jóváhagyásra.',
    'registration_title': 'REGISZTRÁCIÓ',
    'registration_account': 'AIMS Flow regisztráció',
    'registration_intro': 'A sofőr appban a rendszám lesz a belépési azonosító. Jóváhagyás után e-mailben érkezik az egyszer használatos kód.',
    'company_name': 'Cégnév *',
    'country': 'Ország *',
    'country_search': 'Kezdd el begépelni az országot…',
    'country_choose': 'Ország kiválasztása',
    'contact_name': 'Kapcsolattartó neve *',
    'phone': 'Telefon *',
    'phone_helper': 'Nemzetközi formátum (+országkód)',
    'email': 'E-mail *',
    'address': 'Székhely / cím',
    'tax_number': 'Adószám',
    'terms_accept': 'Elfogadom a partnerfelület használati feltételeit.',
    'privacy_accept': 'Tudomásul vettem az adatkezelési tájékoztatót.',
    'open_terms': 'FELTÉTELEK MEGNYITÁSA ↗',
    'open_privacy': 'ADATKEZELÉS MEGNYITÁSA ↗',
    'send_registration': 'REGISZTRÁCIÓ ELKÜLDÉSE',
    'sending': 'KÜLDÉS…',
    'registration_sent': 'Regisztráció elküldve',
    'registration_reactivated': 'Fiók újraregisztrálva',
    'registration_pending': 'A regisztráció jóváhagyás után válik aktívvá. A megadott rendszám automatikusan megjelenik az admin Flow felületén.',
    'required_fields': 'Töltsd ki a kötelező mezőket.',
    'phone_error': 'A telefonszámot nemzetközi formátumban add meg, például: +36 30 123 4567.',
    'legal_required': 'A feltételek és az adatkezelés elfogadása szükséges.',
    'plate_error': 'Adj meg érvényes rendszámot.',
    'ok': 'RENDBEN',
    'device_unlock': 'AIMS Flow feloldása',
    'device_unlock_reason': 'Használd a telefon biometrikus vagy képernyőzáras azonosítását.',
    'device_unlock_failed': 'A telefonos azonosítás nem sikerült.',
    'home': 'KEZDŐLAP',
    'my_job': 'FUVAROM',
    'quick_signal': 'GYORS JELZÉS',
    'docs': 'DOKSI',
    'hands_free_off': 'AIMS Hands-Free kikapcsolva.',
    'wake_listening': 'Figyelek. Mondd: AIMS.',
    'assistant_empty': 'Tessék. Miben segíthetek?',
    'assistant_named': 'Tessék, {name}. Miben segíthetek?',
    'not_understood': 'Ezt nem értettem. Mondd újra az AIMS után.',
    'command_failed': 'A parancs végrehajtása nem sikerült.',
    'speech_unavailable': 'A beszédfelismerés nem érhető el ezen a telefonon.',
    'speech_permission_error': 'A mikrofon vagy beszédfelismerés engedélye hiányzik.',
    'speech_restarting': 'A hangfigyelés újraindul.',
  },
  'en': {
    'login': 'Sign in',
    'driver_login_help': 'Driver sign-in with plate and 6-character code.',
    'admin_login_help': 'Admin sign-in with password and Authenticator code.',
    'plate': 'Plate',
    'plate_hint': 'e.g. SIP-115',
    'driver_code': 'Driver access code',
    'driver_code_hint': 'e.g. K4M8T2',
    'admin_login': 'Admin sign-in',
    'admin_2fa_note': 'Authenticator code is required only for admin.',
    'admin_password': 'Admin password',
    'authenticator_code': '6-digit Authenticator code',
    'sign_in': 'SIGN IN',
    'signing_in': 'SIGNING IN…',
    'register': 'REGISTER',
    'forgot_code': 'FORGOT CODE',
    'driver_footer': 'Driver: plate + exactly 3 letters and 3 numbers. Admin keeps separate password + Authenticator.',
    'driver_name_question': 'What is your name?',
    'driver_name': 'Driver name',
    'driver_name_hint': 'e.g. Peter',
    'continue': 'CONTINUE',
    'invalid_driver_fields': 'Enter the plate and the 6-character driver code.',
    'admin_password_required': 'Enter the admin password.',
    'too_many_attempts': 'Too many failed attempts. Try again later.',
    'invalid_credentials': 'Invalid plate or access code.',
    'temp_expired': 'The one-time code has expired. Request a new code.',
    'server_unavailable': 'The Logistic-AIMS sign-in server is unavailable.',
    'change_code_title': 'Set a new access code',
    'change_code_desc': 'This was a one-time code. Before continuing, set a new 6-character code.',
    'new_code': 'New code',
    'new_code_again': 'Repeat new code',
    'save_code': 'SAVE CODE',
    'code_rule': 'Exactly 6 characters: 3 letters + 3 numbers, in any order.',
    'code_invalid': 'The code must contain exactly 3 letters and 3 numbers.',
    'code_mismatch': 'The two codes do not match.',
    'code_saved': 'The new access code has been saved.',
    'forgot_title': 'Forgot access code',
    'forgot_desc': 'Enter the plate. The reset first goes to admin approval. After approval, a new one-time code is sent to the registered email address.',
    'request_reset': 'REQUEST RESET',
    'forgot_sent': 'The request was sent for admin approval.',
    'registration_title': 'REGISTRATION',
    'registration_account': 'AIMS Flow registration',
    'registration_intro': 'In the driver app the plate is the sign-in identifier. After approval, a one-time code is sent by email.',
    'company_name': 'Company name *',
    'country': 'Country *',
    'country_search': 'Start typing your country…',
    'country_choose': 'Choose country',
    'contact_name': 'Contact name *',
    'phone': 'Phone *',
    'phone_helper': 'International format (+country code)',
    'email': 'Email *',
    'address': 'Registered address',
    'tax_number': 'Tax number',
    'terms_accept': 'I accept the partner portal terms of use.',
    'privacy_accept': 'I acknowledge the privacy notice.',
    'open_terms': 'OPEN TERMS ↗',
    'open_privacy': 'OPEN PRIVACY ↗',
    'send_registration': 'SEND REGISTRATION',
    'sending': 'SENDING…',
    'registration_sent': 'Registration sent',
    'registration_reactivated': 'Account re-registered',
    'registration_pending': 'The registration becomes active after approval. The entered plate automatically appears in the admin Flow interface.',
    'required_fields': 'Fill in all required fields.',
    'phone_error': 'Enter the phone number in international format, e.g. +36 30 123 4567.',
    'legal_required': 'You must accept the terms and privacy notice.',
    'plate_error': 'Enter a valid plate.',
    'ok': 'OK',
    'device_unlock': 'Unlock AIMS Flow',
    'device_unlock_reason': 'Use your phone biometric or screen-lock authentication.',
    'device_unlock_failed': 'Device authentication failed.',
    'home': 'HOME',
    'my_job': 'MY JOB',
    'quick_signal': 'QUICK SIGNAL',
    'docs': 'DOCS',
    'hands_free_off': 'AIMS Hands-Free is off.',
    'wake_listening': 'Listening. Say: AIMS.',
    'assistant_empty': 'Yes. How can I help?',
    'assistant_named': 'Yes, {name}. How can I help?',
    'not_understood': 'I did not understand. Say it again after AIMS.',
    'command_failed': 'The command could not be completed.',
    'speech_unavailable': 'Speech recognition is not available on this phone.',
    'speech_permission_error': 'Microphone or speech recognition permission is missing.',
    'speech_restarting': 'Voice listening is restarting.',
  },
  'de': {
    'login': 'Anmelden',
    'driver_login_help': 'Fahrer-Anmeldung mit Kennzeichen und 6-stelligem Code.',
    'admin_login_help': 'Admin-Anmeldung mit Passwort und Authenticator-Code.',
    'plate': 'Kennzeichen',
    'plate_hint': 'z. B. SIP-115',
    'driver_code': 'Fahrer-Zugangscode',
    'driver_code_hint': 'z. B. K4M8T2',
    'admin_login': 'Admin-Anmeldung',
    'admin_2fa_note': 'Authenticator-Code ist nur für Admin erforderlich.',
    'admin_password': 'Admin-Passwort',
    'authenticator_code': '6-stelliger Authenticator-Code',
    'sign_in': 'ANMELDEN',
    'signing_in': 'ANMELDUNG…',
    'register': 'REGISTRIEREN',
    'forgot_code': 'CODE VERGESSEN',
    'driver_footer': 'Fahrer: Kennzeichen + genau 3 Buchstaben und 3 Zahlen. Admin behält separates Passwort + Authenticator.',
    'driver_name_question': 'Wie heißt du?',
    'driver_name': 'Name des Fahrers',
    'driver_name_hint': 'z. B. Peter',
    'continue': 'WEITER',
    'invalid_driver_fields': 'Kennzeichen und 6-stelligen Fahrer-Code eingeben.',
    'admin_password_required': 'Admin-Passwort eingeben.',
    'too_many_attempts': 'Zu viele Fehlversuche. Später erneut versuchen.',
    'invalid_credentials': 'Falsches Kennzeichen oder falscher Zugangscode.',
    'temp_expired': 'Der Einmalcode ist abgelaufen. Fordere einen neuen Code an.',
    'server_unavailable': 'Der Logistic-AIMS-Anmeldeserver ist nicht erreichbar.',
    'change_code_title': 'Neuen Zugangscode festlegen',
    'change_code_desc': 'Dies war ein Einmalcode. Lege vor dem Fortfahren einen neuen 6-stelligen Code fest.',
    'new_code': 'Neuer Code',
    'new_code_again': 'Neuen Code wiederholen',
    'save_code': 'CODE SPEICHERN',
    'code_rule': 'Genau 6 Zeichen: 3 Buchstaben + 3 Zahlen, in beliebiger Reihenfolge.',
    'code_invalid': 'Der Code muss genau 3 Buchstaben und 3 Zahlen enthalten.',
    'code_mismatch': 'Die beiden Codes stimmen nicht überein.',
    'code_saved': 'Der neue Zugangscode wurde gespeichert.',
    'forgot_title': 'Zugangscode vergessen',
    'forgot_desc': 'Kennzeichen eingeben. Die Rücksetzung muss zuerst vom Admin genehmigt werden. Danach wird ein neuer Einmalcode an die registrierte E-Mail-Adresse gesendet.',
    'request_reset': 'RÜCKSETZUNG ANFORDERN',
    'forgot_sent': 'Die Anfrage wurde zur Admin-Genehmigung gesendet.',
    'registration_title': 'REGISTRIERUNG',
    'registration_account': 'AIMS Flow Registrierung',
    'registration_intro': 'In der Fahrer-App ist das Kennzeichen die Anmeldekennung. Nach Genehmigung wird ein Einmalcode per E-Mail gesendet.',
    'company_name': 'Firmenname *',
    'country': 'Land *',
    'country_search': 'Land eintippen…',
    'country_choose': 'Land auswählen',
    'contact_name': 'Ansprechpartner *',
    'phone': 'Telefon *',
    'phone_helper': 'Internationales Format (+Ländercode)',
    'email': 'E-Mail *',
    'address': 'Firmensitz / Adresse',
    'tax_number': 'Steuernummer',
    'terms_accept': 'Ich akzeptiere die Nutzungsbedingungen des Partnerportals.',
    'privacy_accept': 'Ich habe den Datenschutzhinweis zur Kenntnis genommen.',
    'open_terms': 'BEDINGUNGEN ÖFFNEN ↗',
    'open_privacy': 'DATENSCHUTZ ÖFFNEN ↗',
    'send_registration': 'REGISTRIERUNG SENDEN',
    'sending': 'SENDEN…',
    'registration_sent': 'Registrierung gesendet',
    'registration_reactivated': 'Konto erneut registriert',
    'registration_pending': 'Die Registrierung wird nach Genehmigung aktiv. Das eingegebene Kennzeichen erscheint automatisch in der Admin-Flow-Oberfläche.',
    'required_fields': 'Alle Pflichtfelder ausfüllen.',
    'phone_error': 'Telefonnummer im internationalen Format eingeben, z. B. +36 30 123 4567.',
    'legal_required': 'Bedingungen und Datenschutzhinweis müssen akzeptiert werden.',
    'plate_error': 'Gültiges Kennzeichen eingeben.',
    'ok': 'OK',
    'device_unlock': 'AIMS Flow entsperren',
    'device_unlock_reason': 'Nutze die biometrische oder Bildschirmsperren-Authentifizierung des Telefons.',
    'device_unlock_failed': 'Geräteauthentifizierung fehlgeschlagen.',
    'home': 'START',
    'my_job': 'MEIN AUFTRAG',
    'quick_signal': 'SCHNELLMELDUNG',
    'docs': 'DOKUMENTE',
    'hands_free_off': 'AIMS Hands-Free ist aus.',
    'wake_listening': 'Ich höre zu. Sage: AIMS.',
    'assistant_empty': 'Ja. Wie kann ich helfen?',
    'assistant_named': 'Ja, {name}. Wie kann ich helfen?',
    'not_understood': 'Das habe ich nicht verstanden. Sage es nach AIMS noch einmal.',
    'command_failed': 'Der Befehl konnte nicht ausgeführt werden.',
    'speech_unavailable': 'Spracherkennung ist auf diesem Telefon nicht verfügbar.',
    'speech_permission_error': 'Mikrofon- oder Spracherkennungsberechtigung fehlt.',
    'speech_restarting': 'Die Sprachüberwachung wird neu gestartet.',
  },
};
