from pathlib import Path

voice=Path("lib/services/aims_voice_service.dart").read_text(encoding="utf-8")
shell=Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")

checks={
    "voice init contains failures": "_initialized = false;" in voice and "return false;" in voice,
    "native start failure contained": "Future<bool> enableHandsFree()" in voice and "await AimsHandsFreePlatform.stop();" in voice,
    "assistant invocation safe": "_safeTriggerAssistant" in voice,
    "shell catches voice failure": "A hangvezérlés most nem indítható" in shell,
    "resume stop flush": "await _flushPendingStopActions(refreshAfter: false);" in shell,
    "resume signal flush": "await _flushPendingSignals();" in shell,
    "resume registration flush": "await _flushPendingRegistrationPoints();" in shell,
    "resume office flush": "await _flushPendingOfficeMessages();" in shell,
    "resume document reconciliation": "await _finalizeDocumentGateIfPossible();" in shell,
}
bad=[name for name,ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_LIFECYCLE_RECOVERY_FAIL: "+", ".join(bad))
print("R94_LIFECYCLE_RECOVERY_GUARD_PASS")
