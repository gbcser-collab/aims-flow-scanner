#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.nailfit"
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

dismiss_system_anr() {
  # GitHub's Pixel 6 emulator occasionally shows a Pixel Launcher ANR over
  # the tested app even though NAILFIT itself is running normally. Dismiss
  # only that system dialog, then continue testing the app underneath it.
  for _ in 1 2 3; do
    adb shell uiautomator dump /sdcard/system-ui.xml >/dev/null 2>&1 || true
    adb pull /sdcard/system-ui.xml /tmp/system-ui.xml >/dev/null 2>&1 || true
    if ! grep -q "Pixel Launcher isn't responding" /tmp/system-ui.xml 2>/dev/null; then
      return 0
    fi

    coords=$(python3 - <<'PY'
import re
from pathlib import Path
text = Path('/tmp/system-ui.xml').read_text(errors='ignore')
m = re.search(r'resource-id="android:id/aerr_wait"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', text)
if m:
    x1, y1, x2, y2 = map(int, m.groups())
    print((x1 + x2) // 2, (y1 + y2) // 2)
PY
)
    if [ -n "${coords:-}" ]; then
      adb shell input tap $coords
      sleep 2
    else
      adb shell input keyevent KEYCODE_BACK || true
      sleep 2
    fi
  done
}

dump_ui() {
  adb shell uiautomator dump /sdcard/nailfit-current.xml >/dev/null 2>&1 || fail
  adb pull /sdcard/nailfit-current.xml /tmp/nailfit-current.xml >/dev/null 2>&1 || fail
}

tap_text() {
  local label="$1"
  dump_ui
  local coords
  coords=$(python3 - "$label" <<'PY'
import re, sys, xml.etree.ElementTree as ET
label = sys.argv[1]
root = ET.parse('/tmp/nailfit-current.xml').getroot()
for node in root.iter('node'):
    text = node.attrib.get('text', '')
    desc = node.attrib.get('content-desc', '')
    if text == label or desc == label:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2 = map(int,m.groups())
            print((x1+x2)//2, (y1+y2)//2)
            break
PY
)
  [ -n "${coords:-}" ] || fail
  adb shell input tap $coords
  sleep 2
  dismiss_system_anr
  check_foreground
  check_crash
}

assert_text() {
  local label="$1"
  dump_ui
  python3 - "$label" <<'PY' || fail
import sys, xml.etree.ElementTree as ET
label = sys.argv[1]
root = ET.parse('/tmp/nailfit-current.xml').getroot()
for node in root.iter('node'):
    text = node.attrib.get('text', '')
    desc = node.attrib.get('content-desc', '')
    if label == text or label in text or label == desc or label in desc:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

echo "[1/7] APK integrity"
test -s "$APK"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"

echo "[2/7] Verify standalone package id"
if adb shell pm list packages | grep -q 'hu.logisticaims.aims_flow_scanner'; then
  echo "Scanner package exists independently; NAILFIT must not replace it."
fi

echo "[3/7] Install NAILFIT"
adb install -r "$APK"
adb shell pm list packages | grep "$PKG"

echo "[4/7] Cold launch"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 4
dismiss_system_anr
check_foreground
check_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[5/7] Verify visible NAILFIT UI"
adb shell uiautomator dump /sdcard/nailfit.xml >/dev/null
adb pull /sdcard/nailfit.xml "$EVIDENCE/nailfit.xml" >/dev/null
grep -E "NAIL|FIT|Próbáld" "$EVIDENCE/nailfit.xml" >/dev/null || fail

echo "[6/7] Navigate all main tabs on device"
tap_text "Scan"
assert_text "Kéz szkennelése"
adb exec-out screencap -p > "$EVIDENCE/02-scan.png" || true

tap_text "Try-On"
assert_text "Próbáld fel"
adb exec-out screencap -p > "$EVIDENCE/03-try.png" || true

tap_text "Mentett"
assert_text "Mentett"
adb exec-out screencap -p > "$EVIDENCE/04-saved.png" || true

tap_text "Profil"
assert_text "Saját profil"
adb exec-out screencap -p > "$EVIDENCE/05-profile.png" || true

echo "[7/7] Background/resume + repeated launch"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 2
dismiss_system_anr
check_foreground
check_crash
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  sleep 2
  dismiss_system_anr
  check_foreground
  check_crash
done
adb exec-out screencap -p > "$EVIDENCE/06-final.png" || true
echo "NAILFIT standalone Android smoke-test PASSED"
