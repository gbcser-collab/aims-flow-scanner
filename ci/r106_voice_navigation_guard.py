#!/usr/bin/env python3
from pathlib import Path
import sys

errors = []

push = Path("lib/services/driver_push_service.dart").read_text(encoding="utf-8")
server = Path("server/aims-tracking/push_service.php").read_text(encoding="utf-8")
shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")

for forbidden in (
    "RawResourceAndroidNotificationSound('aims_new_job')",
    "RawResourceAndroidNotificationSound('aims_new_message')",
):
    if forbidden in push:
        errors.append(f"spoken push asset still active: {forbidden}")

for required in (
    "aims_jobs_tts_v2",
    "aims_driver_messages_tts_v2",
    "playSound: false",
):
    if required not in push:
        errors.append(f"missing silent push requirement: {required}")

if "$isDriverMessage" not in server or "'android' => ['priority' => 'high']" not in server:
    errors.append("driver admin messages are not protected by data-only FCM delivery")

for required in (
    "Navigáció indul. Következő cél:",
    "Navigáció indul a regisztrációs ponthoz.",
    "_completionVoiceMessage",
    "Következő feladat:",
    "Üzenet a főnökségtől:",
):
    if required not in shell:
        errors.append(f"missing male voice workflow phrase/helper: {required}")

if errors:
    print("R106 MALE VOICE / NAVIGATION GUARD FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("R106 MALE VOICE / NAVIGATION GUARD PASS")
