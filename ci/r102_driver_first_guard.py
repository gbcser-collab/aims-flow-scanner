from pathlib import Path

main = Path("lib/main.dart").read_text(encoding="utf-8")
sync = Path("lib/services/sync_coordinator.dart").read_text(encoding="utf-8")
shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
api = Path("lib/services/driver_api_service.dart").read_text(encoding="utf-8")

required_main = [
    "runApp(const AimsFlowApp());",
    "DriverPushService.instance.initialize().catchError",
]
for needle in required_main:
    if needle not in main:
        raise SystemExit(f"R102 main guard missing: {needle}")

if main.find("runApp(const AimsFlowApp());") > main.find("DriverPushService.instance.initialize().catchError"):
    raise SystemExit("R102 startup guard: app must render before async push init")

required_sync = [
    "_initialized = false;",
    "Never leave sync locked",
    "_syncing = false;",
]
for needle in required_sync:
    if needle not in sync:
        raise SystemExit(f"R102 sync guard missing: {needle}")

required_shell = [
    "DateTime? _lastJobSyncAt;",
    "int _jobRefreshFailures = 0;",
    "Widget _driverHealthStrip()",
    "int get _driverPendingCount",
    "constraints.maxWidth < 350 || textScale > 1.18",
    "childAspectRatio: singleColumn ? 1.78 : .90",
    "HapticFeedback.selectionClick();",
    "label: _l('Jelzés', 'Signal', 'Meldung')",
]
for needle in required_shell:
    if needle not in shell:
        raise SystemExit(f"R102 shell guard missing: {needle}")

required_api = [
    "final attempts = stableClientId.isNotEmpty ? 2 : 1;",
    "Message network error",
    ".timeout(const Duration(seconds: 10))",
]
for needle in required_api:
    if needle not in api:
        raise SystemExit(f"R102 API guard missing: {needle}")

print("R102 driver-first stability guard: PASS")
