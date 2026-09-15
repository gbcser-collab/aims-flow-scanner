#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
ACTIVITY="$PKG/.MainActivity"
APK="build/app/outputs/flutter-apk/app-debug.apk"
EVIDENCE="test-evidence"
mkdir -p "$EVIDENCE"

fail() {
  adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  exit 1
}

check_foreground() {
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" >/dev/null || fail
}

check_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|Process: ${PKG}|AndroidRuntime.*FATAL" "$EVIDENCE/logcat.txt" >/dev/null; then
    fail
  fi
}

echo "[1/5] APK integrity"
test -s "$APK"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"

echo "[2/5] Install"
adb install -r "$APK"
adb shell pm list packages | grep "$PKG"

echo "[3/5] Cold launch"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 4
check_foreground
check_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[4/5] Verify NAILFIT UI text"
adb shell uiautomator dump /sdcard/nailfit.xml >/dev/null
adb pull /sdcard/nailfit.xml "$EVIDENCE/nailfit.xml" >/dev/null
grep -E "NAIL|FIT|Fotózás|Galéria|Nail Match" "$EVIDENCE/nailfit.xml" >/dev/null || fail

echo "[5/5] Background/resume + repeated launch"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 2
check_foreground
check_crash
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  sleep 2
  check_foreground
  check_crash
done
adb exec-out screencap -p > "$EVIDENCE/02-final.png" || true
echo "NAILFIT Android smoke-test PASSED"
