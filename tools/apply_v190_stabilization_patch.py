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
    text = replace_once(text, old_auth, new_auth, label="driver_api auth block")
    text = text.replace("headers: _headers", "headers: await _sessionHeaders()")

    if "AIMS_TRACKING_TOKEN" in text or "Bearer $_token" in text:
        raise SystemExit("driver_api: embedded tracking token reference remains")
    if text.count("await _sessionHeaders()") < 8:
        raise SystemExit("driver_api: too few session-protected requests")

    path.write_text(text, encoding="utf-8")


def patch_driver_shell() -> None:
    path = ROOT / "lib/screens/driver_shell_screen.dart"
    text = path.read_text(encoding="utf-8")

    replacements = {
        "_isDark ? const Color(0xFF020813) : const Color(0xFFF5F9FC)":
            "_isDark ? const Color(0xFF111315) : const Color(0xFFF5F9FC)",
        "_isDark ? const Color(0xFF06162A) : const Color(0xFFFFFFFF)":
            "_isDark ? const Color(0xFF171A1D) : const Color(0xFFFFFFFF)",
        "_isDark ? const Color(0xFF071725) : const Color(0xFFFFFFFF)":
            "_isDark ? const Color(0xFF1B1F23) : const Color(0xFFFFFFFF)",
        "_isDark ? const Color(0xFF06131F) : const Color(0xFFEEF6FB)":
            "_isDark ? const Color(0xFF23272B) : const Color(0xFFEEF6FB)",
        "_isDark ? const Color(0xFF173B54) : const Color(0xFFD5E2EB)":
            "_isDark ? const Color(0xFF3A4046) : const Color(0xFFD5E2EB)",
    }
    for old, new in replacements.items():
        if old not in text:
            raise SystemExit(f"driver_shell color pattern missing: {old}")
        text = text.replace(old, new, 1)

    # Modal surfaces follow the selected light/dark theme instead of forcing a
    # blue-black sheet in every mode.
    text = text.replace(
        "backgroundColor: const Color(0xFF06131F),",
        "backgroundColor: _panelColor,",
    )

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
