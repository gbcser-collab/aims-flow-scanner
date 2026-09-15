#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
ACTIVITY="$PKG/.MainActivity"
BUILT_APK="build/app/outputs/flutter-apk/app-debug.apk"
DELIVERY_DIR="/tmp/aims-delivery"
DELIVERY_NAME="AIMS-Flow-Smart-Scanner-PASSED.apk"
DELIVERY_ZIP="$DELIVERY_DIR/AIMS-Flow-Smart-Scanner-PASSED-INSTALL.zip"
APK="$DELIVERY_DIR/unpacked/$DELIVERY_NAME"
EVIDENCE="test-evidence"
mkdir -p "$EVIDENCE" "$DELIVERY_DIR/unpacked"

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

launch_app() {
  adb shell am start -W -n "$ACTIVITY" >/dev/null
}

dump_ui_with_retry() {
  local remote="$1"
  local local_file="$2"
  for attempt in 1 2 3; do
    if adb shell uiautomator dump "$remote" >/dev/null 2>&1 && adb pull "$remote" "$local_file" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "UIAutomator dump failed after retries"
  fail_with_logs
}

echo "[0/10] Recreate exact delivery chain: APK -> ZIP -> extract"
cp "$BUILT_APK" "$DELIVERY_DIR/$DELIVERY_NAME"
(
  cd "$DELIVERY_DIR"
  zip -q "$(basename "$DELIVERY_ZIP")" "$DELIVERY_NAME"
)
unzip -t "$DELIVERY_ZIP"
unzip -q "$DELIVERY_ZIP" -d "$DELIVERY_DIR/unpacked"
test -s "$APK"
cmp -s "$BUILT_APK" "$APK"
echo "Built and delivered APK are byte-for-byte identical"
sha256sum "$BUILT_APK" "$APK" > "$EVIDENCE/delivery-sha256.txt"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"

echo "[1/10] Install the extracted delivery APK"
adb install -r "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm list packages | grep "$PKG"

echo "[2/10] Cold launch and foreground verification"
adb logcat -c
adb shell am force-stop "$PKG"
launch_app
sleep 4
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

dump_ui_with_retry /sdcard/home.xml "$EVIDENCE/home.xml"
python3 - <<'PY' > /tmp/tap.txt
import re, xml.etree.ElementTree as ET
root = ET.parse('test-evidence/home.xml').getroot()
for node in root.iter('node'):
    label = node.attrib.get('text') or node.attrib.get('content-desc') or ''
    if 'Scanner megnyitása' in label:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if not m:
            raise SystemExit('Button bounds missing')
        x1,y1,x2,y2 = map(int,m.groups())
        print((x1+x2)//2, (y1+y2)//2)
        break
else:
    raise SystemExit('Scanner button not found in UI tree')
PY
read TAP_X TAP_Y < /tmp/tap.txt

echo "[3/10] Open live scanner screen"
adb shell input tap "$TAP_X" "$TAP_Y"
sleep 8
check_foreground
adb exec-out screencap -p > "$EVIDENCE/02-scanner.png" || true
check_no_crash

echo "[4/10] Exercise tap-to-focus path"
adb shell input tap 540 1200
sleep 2
check_foreground
adb exec-out screencap -p > "$EVIDENCE/03-focus.png" || true
check_no_crash

echo "[5/10] Let live frame analysis run under load"
sleep 8
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/04-analysis.png" || true

echo "[6/10] Background / resume lifecycle"
adb shell input keyevent KEYCODE_HOME
sleep 2
launch_app
sleep 5
check_foreground
check_no_crash

echo "[7/10] Back navigation"
adb shell input keyevent KEYCODE_BACK
sleep 3
check_foreground
dump_ui_with_retry /sdcard/back.xml "$EVIDENCE/back.xml"
grep -F 'Scanner megnyitása' "$EVIDENCE/back.xml" >/dev/null || fail_with_logs

echo "[8/10] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  launch_app
  sleep 3
  check_foreground
  check_no_crash
  echo "cold start $i OK"
done

echo "[9/10] Package and permission diagnostics"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"

echo "[10/10] Final screenshot"
adb exec-out screencap -p > "$EVIDENCE/05-final.png" || true

echo "AIMS Flow delivery-chain + live-scanner Android smoke-test PASSED"
