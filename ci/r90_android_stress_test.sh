#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
ACTIVITY="$PKG/.MainActivity"
APK="build/app/outputs/flutter-apk/app-debug.apk"
EVIDENCE="test-evidence-r90"
COLD_LOOPS="${AIMS_COLD_LOOPS:-1000}"
RESUME_LOOPS="${AIMS_RESUME_LOOPS:-1000}"
mkdir -p "$EVIDENCE"

fail() {
  echo "==== R90 ANDROID STRESS FAILURE ===="
  adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
  adb shell dumpsys meminfo "$PKG" > "$EVIDENCE/meminfo.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  tail -n 250 "$EVIDENCE/logcat.txt" || true
  exit 1
}

check_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|AndroidRuntime.*FATAL|Process: $PKG" "$EVIDENCE/logcat.txt" >/dev/null; then
    fail
  fi
}
echo "[1] install"
adb install -r -g "$APK"
adb shell pm list packages | grep "$PKG" >/dev/null
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -W -n "$ACTIVITY" > "$EVIDENCE/first-start.txt"
sleep 2
adb shell uiautomator dump /sdcard/r90-login.xml >/dev/null 2>&1 || true
adb pull /sdcard/r90-login.xml "$EVIDENCE/login.xml" >/dev/null 2>&1 || true
grep -E "AIMS FLOW|Belépés|Sign in|Anmelden" "$EVIDENCE/login.xml" >/dev/null || fail
check_crash

echo "[2] $COLD_LOOPS cold starts"
for i in $(seq 1 "$COLD_LOOPS"); do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  if (( i % 25 == 0 )); then
    check_crash
  fi
  if (( i % 100 == 0 )); then
    adb shell am send-trim-memory "$PKG" RUNNING_LOW >/dev/null 2>&1 || true
    echo "cold $i/$COLD_LOOPS"
  fi
done
echo "[3] $RESUME_LOOPS background/resume cycles"
for i in $(seq 1 "$RESUME_LOOPS"); do
  adb shell input keyevent KEYCODE_HOME
  adb shell am start -n "$ACTIVITY" >/dev/null
  if (( i % 50 == 0 )); then
    check_crash
  fi
  if (( i % 200 == 0 )); then
    echo "resume $i/$RESUME_LOOPS"
  fi
done

echo "[4] repeated process trim"
for i in $(seq 1 100); do
  adb shell am send-trim-memory "$PKG" RUNNING_LOW >/dev/null 2>&1 || true
  adb shell am start -n "$ACTIVITY" >/dev/null
  if (( i % 10 == 0 )); then
    check_crash
  fi
done
echo "[5] slow-network profile"
adb emu network speed gsm >/dev/null 2>&1 || true
adb emu network delay gprs >/dev/null 2>&1 || true
for i in $(seq 1 100); do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  if (( i % 10 == 0 )); then
    check_crash
  fi
done
adb emu network speed full >/dev/null 2>&1 || true
adb emu network delay none >/dev/null 2>&1 || true

echo "[6] final evidence"
adb shell dumpsys meminfo "$PKG" > "$EVIDENCE/meminfo.txt" 2>&1 || true
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt" 2>&1 || true
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
adb exec-out screencap -p > "$EVIDENCE/final.png" 2>/dev/null || true
check_crash
echo "PASS R90 Android stress: cold=$COLD_LOOPS resume=$RESUME_LOOPS trim=100 slow-network=100"