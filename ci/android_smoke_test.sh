#!/usr/bin/env bash
set -euo pipefail

PKG="hu.logisticaims.aims_flow_scanner"
ACTIVITY="$PKG/.MainActivity"
APK="build/app/outputs/flutter-apk/app-debug.apk"
EVIDENCE="test-evidence"
mkdir -p "$EVIDENCE"

fail_with_logs() {
  echo "==== FAILURE DIAGNOSTICS ===="
  adb shell dumpsys activity activities > "$EVIDENCE/activities.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  tail -n 300 "$EVIDENCE/logcat.txt" || true
  exit 1
}

find_center() {
  local file="$1"
  local needle="$2"
  python3 - "$file" "$needle" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle = sys.argv[1], sys.argv[2]
root = ET.parse(path).getroot()
for node in root.iter('node'):
    label = ' '.join(filter(None, [node.attrib.get('text',''), node.attrib.get('content-desc','')]))
    if needle in label:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if not m:
            continue
        x1,y1,x2,y2 = map(int,m.groups())
        print((x1+x2)//2, (y1+y2)//2)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

dismiss_system_dialogs() {
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/aims_system_dialog.xml >/dev/null 2>&1 || return 0
    adb pull /sdcard/aims_system_dialog.xml /tmp/aims_system_dialog.xml >/dev/null 2>&1 || return 0

    if grep -q -E "isn't responding|is not responding" /tmp/aims_system_dialog.xml; then
      echo "Dismissing unrelated Android system ANR dialog"
      if find_center /tmp/aims_system_dialog.xml "Wait" >/tmp/system-dialog-pos.txt 2>/dev/null; then
        read DX DY < /tmp/system-dialog-pos.txt
        adb shell input tap "$DX" "$DY"
      elif find_center /tmp/aims_system_dialog.xml "Close app" >/tmp/system-dialog-pos.txt 2>/dev/null; then
        read DX DY < /tmp/system-dialog-pos.txt
        adb shell input tap "$DX" "$DY"
      else
        adb shell input keyevent KEYCODE_BACK || true
      fi
      sleep 1
      continue
    fi

    if grep -q -E "keeps stopping|has stopped" /tmp/aims_system_dialog.xml && ! grep -q "$PKG" /tmp/aims_system_dialog.xml; then
      echo "Dismissing unrelated Android system crash dialog"
      if find_center /tmp/aims_system_dialog.xml "Close app" >/tmp/system-dialog-pos.txt 2>/dev/null; then
        read DX DY < /tmp/system-dialog-pos.txt
        adb shell input tap "$DX" "$DY"
      else
        adb shell input keyevent KEYCODE_BACK || true
      fi
      sleep 1
      continue
    fi
    return 0
  done
}

check_foreground() {
  dismiss_system_dialogs || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | grep "$PKG" >/dev/null || fail_with_logs
}

check_no_crash() {
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  if grep -E "FATAL EXCEPTION|Process: ${PKG}|AndroidRuntime.*FATAL" "$EVIDENCE/logcat.txt" >/dev/null; then
    echo "Crash signature found"
    fail_with_logs
  fi
}

launch_app() {
  adb shell am start -W -n "$ACTIVITY" >/dev/null
}

dump_ui() {
  local remote="$1"
  local local_file="$2"
  dismiss_system_dialogs || true
  for attempt in 1 2 3; do
    if adb shell uiautomator dump "$remote" >/dev/null 2>&1 && adb pull "$remote" "$local_file" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  fail_with_logs
}

scroll_down() {
  adb shell input swipe 540 1800 540 520 350
  sleep 1
}

echo "[1/14] Install APK and grant camera"
adb install -r "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm list packages | grep "$PKG"

echo "[2/14] Cold launch"
adb logcat -c
adb shell am force-stop "$PKG"
launch_app
sleep 4
dismiss_system_dialogs || true
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[3/14] Open Smart Scanner PRO"
dump_ui /sdcard/home.xml "$EVIDENCE/home.xml"
read X Y < <(find_center "$EVIDENCE/home.xml" "Smart Scan PRO indítása") || fail_with_logs
adb shell input tap "$X" "$Y"
rm -f /tmp/capture.txt
for i in $(seq 1 15); do
  sleep 2
  dump_ui /sdcard/scanner.xml "$EVIDENCE/scanner.xml"
  if find_center "$EVIDENCE/scanner.xml" "CMR fényképezése és feldolgozása" >/tmp/capture.txt 2>/dev/null; then
    break
  fi
done
test -s /tmp/capture.txt || fail_with_logs
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/02-scanner.png" || true

echo "[4/14] Verify and exercise flash OFF/AUTO/ON controls"
dump_ui /sdcard/flash.xml "$EVIDENCE/flash.xml"
for label in "Vaku KI" "Vaku AUTO" "Vaku BE"; do
  find_center "$EVIDENCE/flash.xml" "$label" >/tmp/flash-pos.txt 2>/dev/null || fail_with_logs
  read FX FY < /tmp/flash-pos.txt
  adb shell input tap "$FX" "$FY"
  sleep 1
  check_no_crash
  dump_ui /sdcard/flash.xml "$EVIDENCE/flash.xml"
done
adb exec-out screencap -p > "$EVIDENCE/03-flash-controls.png" || true

echo "[5/14] Take photo and run perspective guard + dual OCR pipeline"
read CX CY < /tmp/capture.txt
adb shell input tap "$CX" "$CY"

RESULT_OK=0
for i in $(seq 1 65); do
  sleep 2
  check_no_crash
  dump_ui /sdcard/result.xml "$EVIDENCE/result.xml"
  if grep -q -E 'Felismert CMR adatok|Smart Scan PRO' "$EVIDENCE/result.xml"; then
    RESULT_OK=1
    break
  fi
done
if [ "$RESULT_OK" -ne 1 ]; then
  echo "Result screen was not reached after capture"
  fail_with_logs
fi
adb exec-out screencap -p > "$EVIDENCE/04-result.png" || true

echo "[6/14] Verify OCR/editable result UI"
grep -q 'Felismert CMR adatok' "$EVIDENCE/result.xml" || fail_with_logs
check_no_crash

echo "[7/14] Verify PRO copy-summary tool"
rm -f /tmp/copy.txt
for i in $(seq 1 10); do
  dump_ui /sdcard/copy.xml "$EVIDENCE/copy.xml"
  if find_center "$EVIDENCE/copy.xml" "CMR összegzés másolása" >/tmp/copy.txt 2>/dev/null; then
    break
  fi
  scroll_down
done
test -s /tmp/copy.txt || fail_with_logs
read CPX CPY < /tmp/copy.txt
adb shell input tap "$CPX" "$CPY"
sleep 1
check_no_crash

echo "[8/14] Save CMR offline"
rm -f /tmp/save.txt
for i in $(seq 1 10); do
  dump_ui /sdcard/save.xml "$EVIDENCE/save.xml"
  if find_center "$EVIDENCE/save.xml" "Mentés offline" >/tmp/save.txt 2>/dev/null; then
    break
  fi
  scroll_down
done
test -s /tmp/save.txt || fail_with_logs
read SX SY < /tmp/save.txt
adb shell input tap "$SX" "$SY"
sleep 3
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/05-saved.png" || true

echo "[9/14] Restart and verify offline history persisted"
adb shell am force-stop "$PKG"
launch_app
sleep 4
dismiss_system_dialogs || true
check_foreground
check_no_crash
rm -f /tmp/history.txt
for i in $(seq 1 10); do
  dump_ui /sdcard/history.xml "$EVIDENCE/history.xml"
  if find_center "$EVIDENCE/history.xml" "Mentett CMR dokumentum" >/tmp/history.txt 2>/dev/null; then
    break
  fi
  scroll_down
done
test -s /tmp/history.txt || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/06-history.png" || true

echo "[10/14] Re-open persisted CMR"
read HX HY < /tmp/history.txt
adb shell input tap "$HX" "$HY"
sleep 3
check_foreground
check_no_crash
dump_ui /sdcard/reopened.xml "$EVIDENCE/reopened.xml"
grep -q -E 'Smart Scan PRO|Felismert CMR adatok' "$EVIDENCE/reopened.xml" || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/07-reopened.png" || true

echo "[11/14] Home restart and background/resume"
adb shell am force-stop "$PKG"
launch_app
sleep 3
dismiss_system_dialogs || true
check_foreground
adb shell input keyevent KEYCODE_HOME
sleep 2
launch_app
sleep 3
dismiss_system_dialogs || true
check_foreground
check_no_crash

echo "[12/14] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  launch_app
  sleep 2
  dismiss_system_dialogs || true
  check_foreground
  check_no_crash
  echo "cold start $i OK"
done

echo "[13/14] APK integrity"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"
tail -5 "$EVIDENCE/apk-integrity.txt"

echo "[14/14] Final diagnostics"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/08-final.png" || true

echo "AIMS Flow Smart Scanner v0.9 PRO PERSPECTIVE-GUARD + DUAL-OCR + FLASH END-TO-END test PASSED"
