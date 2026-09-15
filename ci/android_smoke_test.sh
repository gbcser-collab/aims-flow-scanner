#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
ACTIVITY="$PKG/.MainActivity"
BUILT_APK="build/app/outputs/flutter-apk/app-debug.apk"
DELIVERY_DIR="/tmp/aims-delivery"
DELIVERY_NAME="AIMS-Flow-Smart-Scanner-v0.5-OCR.apk"
DELIVERY_ZIP="$DELIVERY_DIR/AIMS-Flow-Smart-Scanner-v0.5-OCR-INSTALL.zip"
APK="$DELIVERY_DIR/unpacked/$DELIVERY_NAME"
EVIDENCE="test-evidence"
mkdir -p "$EVIDENCE" "$DELIVERY_DIR/unpacked"

fail_with_logs() {
  echo "==== FAILURE DIAGNOSTICS ===="
  adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  tail -n 300 "$EVIDENCE/logcat.txt" || true
  exit 1
}

check_app_foreground() {
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" >/dev/null || fail_with_logs
}

check_no_app_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|Process: ${PKG}|AndroidRuntime.*FATAL" "$EVIDENCE/logcat.txt" >/dev/null; then
    echo "Crash signature found for AIMS Flow"
    fail_with_logs
  fi
}

launch_app() {
  adb shell am start -W -n "$ACTIVITY" >/dev/null
}

dump_ui() {
  local remote="$1"
  local local_file="$2"
  for attempt in 1 2 3; do
    if adb shell uiautomator dump "$remote" >/dev/null 2>&1 && adb pull "$remote" "$local_file" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "UIAutomator dump failed"
  fail_with_logs
}

find_scanner_button() {
  local xml="$1"
  python3 - "$xml" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root.iter('node'):
    label = node.attrib.get('text') or node.attrib.get('content-desc') or ''
    if 'Scanner megnyitása' in label:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if not m:
            continue
        x1,y1,x2,y2 = map(int,m.groups())
        print((x1+x2)//2, (y1+y2)//2)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

echo "[0/9] Recreate delivery chain: APK -> ZIP -> extract"
cp "$BUILT_APK" "$DELIVERY_DIR/$DELIVERY_NAME"
(
  cd "$DELIVERY_DIR"
  zip -q "$(basename "$DELIVERY_ZIP")" "$DELIVERY_NAME"
)
unzip -t "$DELIVERY_ZIP"
unzip -q "$DELIVERY_ZIP" -d "$DELIVERY_DIR/unpacked"
test -s "$APK"
cmp -s "$BUILT_APK" "$APK"
sha256sum "$BUILT_APK" "$APK" > "$EVIDENCE/delivery-sha256.txt"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"
echo "Delivery APK is byte-for-byte identical"

echo "[1/9] Verify Google Play services and install extracted APK"
adb shell pm list packages | grep 'com.google.android.gms' >/dev/null || {
  echo "Google Play services missing from emulator"
  exit 1
}
adb install -r "$APK"
adb shell pm list packages | grep "$PKG"

echo "[2/9] Cold launch AIMS Flow"
adb logcat -c
adb shell am force-stop "$PKG"
launch_app
sleep 4
check_app_foreground
check_no_app_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[3/9] Locate scanner button, scrolling if needed"
FOUND=0
for attempt in 1 2 3 4; do
  dump_ui /sdcard/home.xml "$EVIDENCE/home-$attempt.xml"
  if find_scanner_button "$EVIDENCE/home-$attempt.xml" > /tmp/tap.txt; then
    FOUND=1
    break
  fi
  adb shell input swipe 540 1900 540 700 450
  sleep 1
done
if [[ "$FOUND" -ne 1 ]]; then
  echo "Scanner button not found after scrolling"
  fail_with_logs
fi
read TAP_X TAP_Y < /tmp/tap.txt

echo "[4/9] Launch native ML Kit document scanner"
adb shell input tap "$TAP_X" "$TAP_Y"
# First use can download the scanner UI/model through Google Play services.
for i in $(seq 1 20); do
  sleep 2
  TOP=$(adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | head -1 || true)
  echo "$TOP" > "$EVIDENCE/top-after-scan.txt"
  if [[ "$TOP" != *"$PKG"* ]] && [[ -n "$TOP" ]]; then
    break
  fi
done
TOP=$(cat "$EVIDENCE/top-after-scan.txt")
if [[ -z "$TOP" ]] || [[ "$TOP" == *"$PKG"* ]]; then
  echo "Native document scanner did not take foreground"
  fail_with_logs
fi
check_no_app_crash
adb exec-out screencap -p > "$EVIDENCE/02-mlkit-scanner.png" || true

echo "[5/9] Capture scanner UI diagnostics"
dump_ui /sdcard/mlkit.xml "$EVIDENCE/mlkit.xml"
adb shell dumpsys activity activities > "$EVIDENCE/mlkit-activities.txt"
adb logcat -d > "$EVIDENCE/mlkit-logcat.txt"

echo "[6/9] Back from scanner to AIMS Flow"
adb shell input keyevent KEYCODE_BACK
sleep 3
check_app_foreground
check_no_app_crash
adb exec-out screencap -p > "$EVIDENCE/03-back-home.png" || true

echo "[7/9] Background / resume lifecycle"
adb shell input keyevent KEYCODE_HOME
sleep 2
launch_app
sleep 3
check_app_foreground
check_no_app_crash

echo "[8/9] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  launch_app
  sleep 2
  check_app_foreground
  check_no_app_crash
  echo "cold start $i OK"
done

echo "[9/9] Final diagnostics"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/04-final.png" || true

echo "AIMS Flow Smart Scanner v0.5 OCR smoke-test PASSED"
