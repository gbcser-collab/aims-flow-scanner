from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_driver_api() -> None:
    path = ROOT / "lib/services/driver_api_service.dart"
    text = path.read_text(encoding="utf-8")

    if "import 'flow_account_service.dart';" not in text:
        text = replace_once(
            text,
            "import 'package:http/http.dart' as http;\n",
            "import 'package:http/http.dart' as http;\n\n"
            "import 'flow_account_service.dart';\n",
            label="driver_api import",
        )

    text = text.replace(
        "defaultValue: 'https://logistic-aims.hu/api/aims-tracking',",
        "defaultValue: 'https://logistic-aims.hu/api/aims-tracking/session',",
    )

    text = re.sub(
        r"\n  static const _token =\n      String\.fromEnvironment\('AIMS_TRACKING_TOKEN', defaultValue: ''\);\n",
        "\n",
        text,
        count=1,
    )

    old_auth = """  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  void _ensureConfigured() {
    if (_token.trim().isEmpty) {
      throw StateError('Az AIMS Flow szerverkulcs nincs beállítva.');
    }
  }
"""
    new_auth = """  Future<Map<String, String>> _sessionHeaders() async {
    final session = await FlowSessionStore.instance.load();
    if (session == null || session.isExpired) {
      throw StateError('A FLOW munkamenet lejárt. Lépj be újra.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.sessionToken}',
    };
  }

  void _ensureConfigured() {
    if (_baseUrl.trim().isEmpty) {
      throw StateError('Az AIMS FLOW API címe nincs beállítva.');
    }
  }
"""
    if old_auth in text:
        text = replace_once(text, old_auth, new_auth, label="driver_api auth block")
    elif new_auth not in text:
        raise SystemExit("driver_api: neither legacy nor session auth block found")

    text = text.replace("headers: _headers", "headers: await _sessionHeaders()")

    if "AIMS_TRACKING_TOKEN" in text or "Bearer $_token" in text:
        raise SystemExit("driver_api: embedded tracking token reference remains")
    if text.count("await _sessionHeaders()") < 8:
        raise SystemExit("driver_api: too few session-protected requests")

    path.write_text(text, encoding="utf-8")


def patch_driver_shell() -> None:
    path = ROOT / "lib/screens/driver_shell_screen.dart"
    text = path.read_text(encoding="utf-8")

    # Neutral graphite surfaces replace the generic blue-black dashboard skin.
    color_replacements = {
        "Color(0xFF020813)": "Color(0xFF111315)",
        "Color(0xFF06162A)": "Color(0xFF171A1D)",
        "Color(0xFF071725)": "Color(0xFF1B1F23)",
        "Color(0xFF06131F)": "Color(0xFF23272B)",
        "Color(0xFF173B54)": "Color(0xFF3A4046)",
        "Color(0xFF04101A)": "Color(0xFF171A1D)",
        "Color(0xFF071E3D)": "Color(0xFF1D2125)",
        "Color(0xFF030A13)": "Color(0xFF111315)",
        "Color(0xFF02070E)": "Color(0xFF0D0F11)",
        "Color(0xFF0A2236)": "Color(0xFF24292D)",
        "Color(0xFF102436)": "Color(0xFF2A2F34)",
    }
    for old, new in color_replacements.items():
        text = text.replace(old, new)

    # Modal surfaces follow the selected theme.
    text = text.replace(
        "backgroundColor: const Color(0xFF23272B),",
        "backgroundColor: _panelColor,",
    )

    if "Color get _headerText" not in text:
        marker = """  Color get _textFaint =>
      _isDark ? Colors.white38 : const Color(0xFF8093A0);
"""
        addition = marker + """  Color get _headerText =>
      _isDark ? Colors.white : const Color(0xFF17212A);
  Color get _headerMuted =>
      _isDark ? Colors.white70 : const Color(0xFF536B7A);
"""
        text = replace_once(text, marker, addition, label="driver_shell header colors")

    old_title = """                const Text(
                  'AIMS FLOW',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
"""
    new_title = """                Text(
                  'AIMS FLOW',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _headerText,
"""
    if old_title in text:
        text = replace_once(text, old_title, new_title, label="header title color")

    identity_color = """                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
"""
    identity_new = """                  style: TextStyle(
                    color: _headerMuted,
                    fontSize: 11,
"""
    if identity_color in text:
        text = replace_once(
            text,
            identity_color,
            identity_new,
            label="header identity color",
        )

    text = text.replace(
        "color: _restMode.active ? _green : Colors.white54,",
        "color: _restMode.active ? _green : _headerMuted,",
    )

    if "Future<void> _logoutDriverSession()" not in text:
        dispose_marker = """  @override
  void dispose() {
"""
        logout_method = """  Future<void> _logoutDriverSession() async {
    if (_actionBusy) return;
    if (_workdayState.active) {
      _snack(
        _l(
          'Aktív munkanap alatt a kijelentkezés nem engedélyezett. Előbb zárd le a munkanapot.',
          'You cannot sign out during an active workday. Finish the workday first.',
          'Während eines aktiven Arbeitstags ist die Abmeldung gesperrt. Beende zuerst den Arbeitstag.',
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_l('Kijelentkezés', 'Sign out', 'Abmelden')),
            content: Text(
              _l(
                'A telefon elfelejti a FLOW munkamenetet. A következő használatkor FLOW ID és PIN szükséges.',
                'This phone will forget the FLOW session. FLOW ID and PIN will be required next time.',
                'Dieses Telefon vergisst die FLOW-Sitzung. Beim nächsten Mal werden FLOW ID und PIN benötigt.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_l('MÉGSE', 'CANCEL', 'ABBRECHEN')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_l('KIJELENTKEZÉS', 'SIGN OUT', 'ABMELDEN')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      final session = _flowSession ?? await FlowSessionStore.instance.load();
      await const FlowAccountService().logout(session);
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const FlowLoginScreen()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

""" + dispose_marker
        text = replace_once(
            text,
            dispose_marker,
            logout_method,
            label="driver logout method",
        )

    if "tooltip: _l('Kijelentkezés'" not in text:
        selector = """          const AimsLanguageSelector(compact: true),
"""
        controls = selector + """          IconButton(
            tooltip: _l('Kijelentkezés', 'Sign out', 'Abmelden'),
            onPressed: _actionBusy ? null : _logoutDriverSession,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.logout_rounded, color: _headerMuted),
          ),
"""
        text = replace_once(text, selector, controls, label="driver logout button")

    path.write_text(text, encoding="utf-8")


def patch_admin_link() -> None:
    path = ROOT / "admin/aims-flow.php"
    text = path.read_text(encoding="utf-8")
    if "aims-flow-driver-access.php" in text:
        return

    candidates = [
        (
            '<a href="index.php">Admin főoldal</a><a href="logout.php">Kilépés</a>',
            '<a href="index.php">Admin főoldal</a><a href="aims-flow-driver-access.php">Sofőr-hozzáférések</a><a href="logout.php">Kilépés</a>',
        ),
        (
            '<a href="index.php">Főoldal</a><a href="logout.php">Kilépés</a>',
            '<a href="index.php">Főoldal</a><a href="aims-flow-driver-access.php">Sofőr-hozzáférések</a><a href="logout.php">Kilépés</a>',
        ),
    ]
    for old, new in candidates:
        if old in text:
            text = text.replace(old, new, 1)
            path.write_text(text, encoding="utf-8")
            return
    raise SystemExit("admin: navigation insertion point not found")


def main() -> None:
    patch_driver_api()
    patch_driver_shell()
    patch_admin_link()
    print("FLOW v1.9 stabilization patch applied")


if __name__ == "__main__":
    main()
