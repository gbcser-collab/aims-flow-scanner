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

for token in [
    "flow-office-message-input",
    "flow-office-message-send",
    "_sendSignal('Késés')",
    "_sendSignal('Várakozás')",
    "_sendSignal('Műszaki hiba')",
]:
    if token not in shell:
        raise SystemExit(f"signal/message action missing: {token}")

print("R93_SIGNAL_MESSAGE_SOURCE_GUARD_PASS")
