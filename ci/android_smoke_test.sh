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

check_no_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|Process: ${PKG}|AndroidRuntime.*FATAL" "$EVIDENCE/logcat.txt" >/dev/null; then
    echo "Crash signature found in logcat"
    fail_with_logs
  fi
}

echo "[1/8] Install APK"
adb install -r "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm list packages | grep "$PKG"

echo "[2/8] Cold launch and foreground verification"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 4
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

# Flutter exposes visible labels through accessibility content-desc on Android.
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

echo "[3/8] Open scanner screen"
adb shell input tap "$TAP_X" "$TAP_Y"
sleep 8
adb exec-out screencap -p > "$EVIDENCE/02-scanner.png" || true
adb shell uiautomator dump /sdcard/scanner.xml >/dev/null
adb pull /sdcard/scanner.xml "$EVIDENCE/scanner.xml" >/dev/null
grep -F 'CMR Scanner' "$EVIDENCE/scanner.xml" >/dev/null || fail_with_logs
if grep -F 'A kamera nem indult el' "$EVIDENCE/scanner.xml" >/dev/null; then
  echo "Camera screen reported initialization failure"
  fail_with_logs
fi
check_no_crash

echo "[4/8] Background / resume lifecycle"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 5
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" || fail_with_logs
check_no_crash

echo "[5/8] Back navigation"
adb shell input keyevent KEYCODE_BACK
sleep 3
adb shell uiautomator dump /sdcard/back.xml >/dev/null
adb pull /sdcard/back.xml "$EVIDENCE/back.xml" >/dev/null
grep -F 'Scanner megnyitása' "$EVIDENCE/back.xml" >/dev/null || fail_with_logs

echo "[6/8] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
  sleep 3
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" >/dev/null || fail_with_logs
  echo "cold start $i OK"
done
check_no_crash

echo "[7/8] Package and permission state"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
grep -F 'android.permission.CAMERA: granted=true' "$EVIDENCE/package.txt" >/dev/null || true

echo "[8/8] Final diagnostics snapshot"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/03-final.png" || true

echo "AIMS Flow extended Android smoke-test PASSED"
