#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
APK="build/app/outputs/flutter-apk/app-debug.apk"
EVIDENCE="test-evidence"
mkdir -p "$EVIDENCE"

fail_with_logs() {
  echo "==== FAILURE DIAGNOSTICS ===="
  adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  tail -n 250 "$EVIDENCE/logcat.txt" || true
  exit 1
}

check_foreground() {
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" >/dev/null || fail_with_logs
}

check_no_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|Process: ${PKG}|AndroidRuntime.*FATAL" "$EVIDENCE/logcat.txt" >/dev/null; then
    echo "Crash signature found in logcat"
    fail_with_logs
  fi
}

echo "[1/9] Install APK"
adb install -r "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm list packages | grep "$PKG"

echo "[2/9] Cold launch and foreground verification"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 4
check_foreground
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

# Home is static, so accessibility lookup is reliable here.
adb shell uiautomator dump /sdcard/home.xml >/dev/null
adb pull /sdcard/home.xml "$EVIDENCE/home.xml" >/dev/null
python3 - <<'PY' > /tmp/tap.txt
import re, xml.etree.ElementTree as ET
root = ET.parse('test-evidence/home.xml').getroot()
for node in root.iter('node'):
    label = node.attrib.get('text') or node.attrib.get('content-desc') or ''
    if label == 'Scanner megnyitása':
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib['bounds'])
        if not m:
            raise SystemExit('Button bounds missing')
        x1,y1,x2,y2 = map(int,m.groups())
        print((x1+x2)//2, (y1+y2)//2)
        break
else:
    raise SystemExit('Scanner button not found in UI tree')
PY
read TAP_X TAP_Y < /tmp/tap.txt

echo "[3/9] Open live scanner screen"
adb shell input tap "$TAP_X" "$TAP_Y"
sleep 8
check_foreground
adb exec-out screencap -p > "$EVIDENCE/02-scanner.png" || true
check_no_crash

echo "[4/9] Exercise tap-to-focus path"
# Pixel 6 emulator is 1080x2400. Tap near the document center, away from controls.
adb shell input tap 540 1200
sleep 2
check_foreground
adb exec-out screencap -p > "$EVIDENCE/03-focus.png" || true
check_no_crash

echo "[5/9] Let live frame analysis run under load"
sleep 8
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/04-analysis.png" || true

echo "[6/9] Background / resume lifecycle"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 5
check_foreground
check_no_crash

echo "[7/9] Back navigation"
adb shell input keyevent KEYCODE_BACK
sleep 3
check_foreground
adb shell uiautomator dump /sdcard/back.xml >/dev/null
adb pull /sdcard/back.xml "$EVIDENCE/back.xml" >/dev/null
grep -F 'Scanner megnyitása' "$EVIDENCE/back.xml" >/dev/null || fail_with_logs

echo "[8/9] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
  sleep 3
  check_foreground
  echo "cold start $i OK"
done
check_no_crash

echo "[9/9] Package, permission and final diagnostics"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/05-final.png" || true

echo "AIMS Flow live-scanner Android smoke-test PASSED"
