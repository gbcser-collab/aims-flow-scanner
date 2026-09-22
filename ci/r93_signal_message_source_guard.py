from pathlib import Path

shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
login = Path("lib/screens/flow_login_screen.dart").read_text(encoding="utf-8")

def block(text, start_marker, end_marker):
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[start:end]

ensure = block(
    shell,
    "Future<bool> _ensureDriverIdentity() async",
    "String _newOfficeMessageId",
)

required_shell = [
    "this.initialPlate = ''",
    "final String initialPlate;",
    "widget.initialPlate.trim().isNotEmpty",
    "SharedPreferences.getInstance()",
    "prefs.getString(_prefsPlate)",
    "setState(() => _plate = recoveredPlate)",
]
for token in required_shell:
    if token not in shell:
        raise SystemExit(f"missing R93 identity hardening token: {token}")

if "pushAndRemoveUntil" in ensure or "pushReplacement" in ensure:
    raise SystemExit(
        "R93 regression: _ensureDriverIdentity must not replace the widget tree "
        "from a quick-signal/message callback"
    )

required_login = [
    "initialPlate:",
    "initialDriverName:",
    "prefs.getString('aims_driver_plate')",
]
for token in required_login:
    if token not in login:
        raise SystemExit(f"login no longer passes driver identity directly: {token}")

required_signal_flow = [
    "flow-office-message-input",
    "flow-office-message-send",
    "_showSignalChoice(",
    "type: 'Késés'",
    "'Forgalom'",
    "'Csúszás'",
    "type: 'Várakozás'",
    "'Rakodásra várok'",
    "'Telephelyen várok'",
    "type: 'Cím / rakodás'",
    "'Nem található'",
    "'Nem engednek be'",
    "type: 'Műszaki hiba'",
    "'Autó'",
    "'Gumi'",
    "'Motor'",
    "type: 'Baleset / sürgős'",
    "'SOS – azonnali segítség'",
    "'Baleset'",
    "await _sendSignal(type, urgent: urgent, message: selected);",
]
for token in required_signal_flow:
    if token not in shell:
        raise SystemExit(f"signal/message action missing: {token}")

choice = block(
    shell,
    "Future<void> _showSignalChoice({",
    "Future<void> _otherSignal() async",
)
if "bool urgent = false" not in choice:
    raise SystemExit("signal choice no longer carries urgent severity")
if "message: selected" not in choice:
    raise SystemExit("signal choice no longer forwards the selected reason")
if "urgent: urgent" not in choice:
    raise SystemExit("signal choice no longer forwards urgent severity")

print("R93_SIGNAL_MESSAGE_SOURCE_GUARD_PASS")
