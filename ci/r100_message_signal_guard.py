from pathlib import Path

shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
main = Path("lib/main.dart").read_text(encoding="utf-8")
api = Path("lib/services/driver_api_service.dart").read_text(encoding="utf-8")
server = Path("server/aims-tracking/driver_messages.php").read_text(encoding="utf-8")

required_shell = [
    "Future<bool> _ensureDriverIdentity()",
    "status.vehicleLabel.trim().isNotEmpty",
    "Future<void> _sendOfficeMessage()",
    "_pendingOfficeMessages",
    "NATÍV FLOW ÜZENET • NEM KÉR WEBES BELÉPÉST",
    "childAspectRatio: 1.02",
    "const Color(0xFF3BC7FF)",
    "width: danger ? 2.4 : 2.0",
    "Theme.of(context).textTheme.headlineSmall",
]
for needle in required_shell:
    if needle not in shell:
        raise SystemExit(f"missing driver-shell guard: {needle}")

if "Message cannot be sent. Check sign in." in shell:
    raise SystemExit("stale fake-login message remains")

fallback = shell.find("status.vehicleLabel.trim().isNotEmpty")
login_redirect = shell.find("MaterialPageRoute(builder: (_) => const FlowLoginScreen())")
if fallback < 0 or login_redirect < 0 or fallback > login_redirect:
    raise SystemExit("driver identity fallback must run before login redirect")

if "Future<DriverChatMessage> sendMessage" not in api:
    raise SystemExit("native message API method missing")
if "driver_messages.php" not in api:
    raise SystemExit("native message endpoint missing from client")
if "aims_require_token('AIMS_TRACKING_TOKEN')" not in server:
    raise SystemExit("driver message endpoint is not token protected")
if "clientMessageId" not in server:
    raise SystemExit("message idempotency key missing")
if "textTheme: TextTheme(" not in main:
    raise SystemExit("global typography theme missing")
if "inputDecorationTheme: InputDecorationTheme(" not in main:
    raise SystemExit("global input theme missing")

print("R100 message/signal/typography guard: PASS")
