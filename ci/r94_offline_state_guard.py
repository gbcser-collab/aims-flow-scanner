from pathlib import Path

shell=Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
required=[
    "_prefsStateQuarantine",
    "Future<void> _quarantineLocalState(",
    "cmr_links_invalid_json",
    "registration_queue_invalid_json",
    "signal_queue_invalid_json",
    "stop_queue_invalid_json",
    "office_message_queue_invalid_json",
    "_stateRecoveryWarning && mounted",
]
for needle in required:
    if needle not in shell:
        raise SystemExit(f"R94_OFFLINE_STATE_FAIL missing: {needle}")

for forbidden in (
    "catch (_) {\n        await prefs.remove(_pendingSignalPrefsKey",
    "catch (_) {\n      await prefs.remove(_pendingStopPrefsKey",
    "catch (_) {\n      await prefs.remove(_pendingRegistrationPrefsKey",
    "catch (_) {\n      await prefs.remove(_pendingOfficeMessagePrefsKey",
    "catch (_) {\n        await prefs.remove(_jobCmrPrefsKey",
):
    if forbidden in shell:
        raise SystemExit("R94_OFFLINE_STATE_FAIL destructive catch/remove returned")

print("R94_OFFLINE_STATE_QUARANTINE_GUARD_PASS")
