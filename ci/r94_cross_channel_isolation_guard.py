from pathlib import Path

SOURCE = Path("lib/screens/driver_shell_screen.dart")
text = SOURCE.read_text(encoding="utf-8")

def body_between(signature: str, next_signature: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"R94_GUARD_FAIL missing: {signature}")
    end = text.find(next_signature, start + len(signature))
    if end < 0:
        raise SystemExit(f"R94_GUARD_FAIL missing end marker: {next_signature}")
    return text[start:end]

signal_flush = body_between(
    "Future<void> _flushPendingSignals() async",
    "int get _pendingStopEventCount",
)
activate = body_between(
    "Future<void> _activateDriverServices() async",
    "Future<void> _refreshJobs",
)
initialize = body_between(
    "Future<void> _initialize() async",
    "Future<void> _activateDriverServices",
)

for forbidden in ("_pendingOfficeMessageRetryTimer", "_officeMessageTimer"):
    if forbidden in signal_flush:
        raise SystemExit(
            f"R94_GUARD_FAIL signal flush must not control office-message timer: {forbidden}"
        )

if "_flushPendingOfficeMessages()" not in activate:
    raise SystemExit(
        "R94_GUARD_FAIL driver service activation must flush persisted office messages"
    )

if "Timer.periodic(const Duration(seconds: 15)" not in initialize:
    raise SystemExit(
        "R94_GUARD_FAIL office message polling must start after driver initialization"
    )

print("R94_CROSS_CHANNEL_ISOLATION_GUARD_PASS")


EVENT_SOURCE = Path("server/aims-tracking/driver_event.php")
event_text = EVENT_SOURCE.read_text(encoding="utf-8")
for required in (
    "$eventId",
    "$occurredAt",
    "$dedupeSuffix",
    "hash('sha256',$eventId)",
):
    if required not in event_text:
        raise SystemExit(f"R94_GUARD_FAIL driver_event idempotency missing: {required}")
if "microtime(true).$body" in event_text:
    raise SystemExit("R94_GUARD_FAIL legacy non-idempotent driver signal dedupe still present")

print("R94_DRIVER_SIGNAL_IDEMPOTENCY_GUARD_PASS")
