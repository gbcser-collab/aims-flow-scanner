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
    label = ' '.join(filter(None, [node.attrib.get('text',''), node.attrib.get('content-desc',''), node.attrib.get('hint','')]))
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

find_any_center() {
  local file="$1"
  shift
  local needle
  for needle in "$@"; do
    if find_center "$file" "$needle"; then
      return 0
    fi
  done
  return 1
}

dismiss_system_dialogs() {
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/aims_system_dialog.xml >/dev/null 2>&1 || return 0
    adb pull /sdcard/aims_system_dialog.xml /tmp/aims_system_dialog.xml >/dev/null 2>&1 || return 0
    if grep -q -E "isn't responding|is not responding" /tmp/aims_system_dialog.xml; then
      if find_center /tmp/aims_system_dialog.xml "Wait" >/tmp/system-dialog-pos.txt 2>/dev/null; then
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
    fail_with_logs
  fi
}

launch_app() { adb shell am start -W -n "$ACTIVITY" >/dev/null; }

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

scroll_down() { adb shell input swipe 540 1800 540 520 350; sleep 1; }

login_if_needed() {
  dump_ui /sdcard/login.xml "$EVIDENCE/login.xml"
  if ! grep -q 'Belépés' "$EVIDENCE/login.xml"; then
    return 0
  fi
  echo "Logging into unified AIMS Flow UI"
  python3 - "$EVIDENCE/login.xml" >/tmp/edit-centers.txt <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
out=[]
for n in root.iter('node'):
    cls=n.attrib.get('class','')
    if 'EditText' not in cls:
        continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
    if m:
        x1,y1,x2,y2=map(int,m.groups()); out.append(((x1+x2)//2,(y1+y2)//2))
for x,y in out:
    print(x,y)
PY
  mapfile -t EDITS < /tmp/edit-centers.txt
  if [ "${#EDITS[@]}" -lt 3 ]; then
    echo "Could not locate login fields"
    fail_with_logs
  fi
  read UX UY <<<"${EDITS[0]}"; adb shell input tap "$UX" "$UY"; adb shell input text e2e_user
  read PX PY <<<"${EDITS[1]}"; adb shell input tap "$PX" "$PY"; adb shell input text e2e_pass
  adb shell input keyevent KEYCODE_BACK || true
  sleep 1
  read CX CY <<<"${EDITS[2]}"; adb shell input tap "$CX" "$CY"
  for d in 1 2 3 4 5 6; do adb shell input text "$d"; sleep .3; done
  adb shell input keyevent KEYCODE_BACK || true
  sleep 1
  dump_ui /sdcard/login-ready.xml "$EVIDENCE/login-ready.xml"
  read TX TY < <(find_center "$EVIDENCE/login-ready.xml" "Tovább") || fail_with_logs
  adb shell input tap "$TX" "$TY"
  for i in $(seq 1 20); do
    sleep 2
    dump_ui /sdcard/post-login.xml "$EVIDENCE/post-login.xml"
    if grep -q 'Smart Scan indítása' "$EVIDENCE/post-login.xml"; then return 0; fi
    if grep -q -E 'Készülék jóváhagyásra vár|Hozzáférés visszavonva' "$EVIDENCE/post-login.xml"; then
      echo "Device gate blocked E2E"
      fail_with_logs
    fi
  done
  fail_with_logs
}

echo "[1/14] Install APK and grant camera/location"
adb install -r "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION || true
adb shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION || true
adb shell pm list packages | grep "$PKG"

echo "[2/14] Cold launch + login"
adb logcat -c
adb shell am force-stop "$PKG"
launch_app
sleep 4
dismiss_system_dialogs || true
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/01-login.png" || true
login_if_needed
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[3/14] Open Smart Scanner"
dump_ui /sdcard/home.xml "$EVIDENCE/home.xml"
read X Y < <(find_center "$EVIDENCE/home.xml" "Smart Scan indítása") || fail_with_logs
adb shell input tap "$X" "$Y"
rm -f /tmp/capture.txt
for i in $(seq 1 15); do
  sleep 2
  dump_ui /sdcard/scanner.xml "$EVIDENCE/scanner.xml"
  if find_center "$EVIDENCE/scanner.xml" "CMR fényképezése és feldolgozása" >/tmp/capture.txt 2>/dev/null; then break; fi
done
test -s /tmp/capture.txt || fail_with_logs
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/02-scanner.png" || true

echo "[4/14] Verify flash OFF/AUTO/ON"
dump_ui /sdcard/flash.xml "$EVIDENCE/flash.xml"
for label in "Vaku KI" "Vaku AUTO" "Vaku BE"; do
  find_center "$EVIDENCE/flash.xml" "$label" >/tmp/flash-pos.txt 2>/dev/null || fail_with_logs
  read FX FY < /tmp/flash-pos.txt; adb shell input tap "$FX" "$FY"; sleep 1; check_no_crash
  dump_ui /sdcard/flash.xml "$EVIDENCE/flash.xml"
done

echo "[5/14] Capture + OCR"
read CX CY < /tmp/capture.txt
adb shell input tap "$CX" "$CY"
RESULT_OK=0
for i in $(seq 1 65); do
  sleep 2; check_no_crash; dump_ui /sdcard/result.xml "$EVIDENCE/result.xml"
  if grep -q -E 'Felismert CMR adatok|Smart Scan PRO' "$EVIDENCE/result.xml"; then RESULT_OK=1; break; fi
done
[ "$RESULT_OK" -eq 1 ] || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/04-result.png" || true

echo "[6/14] Verify OCR result"
grep -q 'Felismert CMR adatok' "$EVIDENCE/result.xml" || fail_with_logs
check_no_crash

echo "[7/14] Verify copy-summary"
rm -f /tmp/copy.txt
for i in $(seq 1 10); do
  dump_ui /sdcard/copy.xml "$EVIDENCE/copy.xml"
  if find_center "$EVIDENCE/copy.xml" "CMR összegzés másolása" >/tmp/copy.txt 2>/dev/null; then break; fi
  scroll_down
done
test -s /tmp/copy.txt || fail_with_logs
read CPX CPY < /tmp/copy.txt; adb shell input tap "$CPX" "$CPY"; sleep 1; check_no_crash

echo "[8/14] Verify private save/update"
rm -f /tmp/save.txt
for i in $(seq 1 12); do
  dump_ui /sdcard/save.xml "$EVIDENCE/save.xml"
  if find_center "$EVIDENCE/save.xml" "Módosítások mentése az appba" >/tmp/save.txt 2>/dev/null; then break; fi
  scroll_down
done
test -s /tmp/save.txt || fail_with_logs
read SX SY < /tmp/save.txt; adb shell input tap "$SX" "$SY"; sleep 3; check_no_crash

echo "[9/14] Restart + login + verify CMR history"
adb shell am force-stop "$PKG"; launch_app; sleep 4; check_foreground; login_if_needed
rm -f /tmp/history.txt
for i in $(seq 1 12); do
  dump_ui /sdcard/history.xml "$EVIDENCE/history.xml"
  if find_any_center "$EVIDENCE/history.xml" "Mentett CMR" "CMR-" "Feldolgozva" "Feldolgozás alatt" >/tmp/history.txt 2>/dev/null; then break; fi
  scroll_down
done
test -s /tmp/history.txt || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/06-history.png" || true

echo "[10/14] Re-open persisted CMR"
read HX HY < /tmp/history.txt; adb shell input tap "$HX" "$HY"; sleep 3; check_foreground; check_no_crash
dump_ui /sdcard/reopened.xml "$EVIDENCE/reopened.xml"
grep -q -E 'Smart Scan PRO|Felismert CMR adatok' "$EVIDENCE/reopened.xml" || fail_with_logs

echo "[11/14] Restart/background/resume"
adb shell am force-stop "$PKG"; launch_app; sleep 3; login_if_needed; check_foreground
adb shell input keyevent KEYCODE_HOME; sleep 2; launch_app; sleep 3; check_foreground; check_no_crash

echo "[12/14] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"; launch_app; sleep 3; login_if_needed; check_foreground; check_no_crash; echo "cold start $i OK"
done

echo "[13/14] APK integrity"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"; tail -5 "$EVIDENCE/apk-integrity.txt"

echo "[14/14] Final diagnostics"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/08-final.png" || true

echo "AIMS Flow v1.0 UNIFIED Android end-to-end test PASSED"
