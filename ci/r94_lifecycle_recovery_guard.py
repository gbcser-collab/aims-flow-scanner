from pathlib import Path

announcer = Path("lib/services/aims_voice_announcer_service.dart").read_text(encoding="utf-8")
shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
pubspec = Path("pubspec.yaml").read_text(encoding="utf-8")

checks = {
    "announcer init contains failures":
        "_initialized = false;" in announcer and "return false;" in announcer,
    "announcer output is failure-contained":
        "final ok = await initialize();" in announcer and "if (!ok) return;" in announcer,
    "interactive voice dependency removed":
        "speech_to_text:" not in pubspec,
    "interactive assistant not restored":
        "aims-assistant-talk" not in shell and "enableHandsFree" not in shell,
    "resume stop flush":
        "await _flushPendingStopActions(refreshAfter: false);" in shell,
    "resume signal flush":
        "await _flushPendingSignals();" in shell,
    "resume registration flush":
        "await _flushPendingRegistrationPoints();" in shell,
    "resume office flush":
        "await _flushPendingOfficeMessages();" in shell,
    "resume document reconciliation":
        "await _finalizeDocumentGateIfPossible();" in shell,
}

bad = [name for name, ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_LIFECYCLE_RECOVERY_FAIL: " + ", ".join(bad))

print("R94_LIFECYCLE_RECOVERY_GUARD_PASS")
