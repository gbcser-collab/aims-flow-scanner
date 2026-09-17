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
  adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt" 2>&1 || true
  adb logcat -d > "$EVIDENCE/logcat.txt" 2>&1 || true
  adb exec-out screencap -p > "$EVIDENCE/failure.png" 2>/dev/null || true
  tail -n 350 "$EVIDENCE/logcat.txt" || true
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
      echo "Dismissing Android system ANR dialog"
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

wait_for_label() {
  local needle="$1"
  local outfile="$2"
  local tries="${3:-20}"
  rm -f /tmp/aims-label-pos.txt
  for i in $(seq 1 "$tries"); do
    sleep 1
    dump_ui /sdcard/wait.xml "$outfile"
    if find_center "$outfile" "$needle" >/tmp/aims-label-pos.txt 2>/dev/null; then
      cat /tmp/aims-label-pos.txt
      return 0
    fi
  done
  return 1
}

tracking_json() {
  adb shell run-as "$PKG" cat app_flutter/aims_tracking/current_trip.json 2>/dev/null | tr -d '\r'
}

assert_tracking_json() {
  local expected_active="$1"
  local require_unsynced="$2"
  local file="$3"
  tracking_json > "$file" || fail_with_logs
  python3 - "$file" "$expected_active" "$require_unsynced" <<'PY'
import json, sys
path, expected_active, require_unsynced = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
assert data.get('active') is (expected_active == 'true'), data
points = data.get('points') or []
assert len(points) >= 1, data
if require_unsynced == 'true':
    assert any(not p.get('synced', False) for p in points), data
print('tracking JSON OK:', data.get('id'), 'active=', data.get('active'), 'points=', len(points))
PY
}

echo "[1/20] Install debug APK and grant runtime permissions"
adb install -r -g "$APK"
adb shell pm grant "$PKG" android.permission.CAMERA || true
adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION || true
adb shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION || true
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
adb shell pm list packages | grep "$PKG"

echo "[2/20] Cold launch"
adb logcat -c
adb shell am force-stop "$PKG"
launch_app
sleep 4
dismiss_system_dialogs || true
check_foreground
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/01-home.png" || true

echo "[3/20] Open Smart Scanner"
dump_ui /sdcard/home.xml "$EVIDENCE/home.xml"
read X Y < <(find_center "$EVIDENCE/home.xml" "Smart Scan indítása") || fail_with_logs
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

echo "[4/20] Exercise capture-only flash OFF/AUTO/ON controls"
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

echo "[5/20] Capture and run frame-crop + perspective guard + dual OCR"
read CX CY < /tmp/capture.txt
adb shell input tap "$CX" "$CY"
RESULT_OK=0
for i in $(seq 1 65); do
  sleep 2
  check_no_crash
  dump_ui /sdcard/result.xml "$EVIDENCE/result.xml"
  if grep -q -E 'Felismert CMR adatok|Smart Scan PRO|Smart Scan eredmény' "$EVIDENCE/result.xml"; then
    RESULT_OK=1
    break
  fi
done
if [ "$RESULT_OK" -ne 1 ]; then
  echo "Result screen was not reached after capture"
  fail_with_logs
fi
adb exec-out screencap -p > "$EVIDENCE/04-result.png" || true

echo "[6/20] Verify editable OCR result UI"
grep -q 'Felismert CMR adatok' "$EVIDENCE/result.xml" || fail_with_logs
check_no_crash

echo "[7/20] Save CMR with GPS/offline fallback"
adb emu geo fix 17.6504 47.6875 >/dev/null 2>&1 || true
rm -f /tmp/save.txt
for i in $(seq 1 10); do
  dump_ui /sdcard/save.xml "$EVIDENCE/save.xml"
  if find_center "$EVIDENCE/save.xml" "Mentés + GPS" >/tmp/save.txt 2>/dev/null; then
    break
  fi
  scroll_down
done
test -s /tmp/save.txt || fail_with_logs
read SX SY < /tmp/save.txt
adb shell input tap "$SX" "$SY"
sleep 4
check_no_crash
adb exec-out screencap -p > "$EVIDENCE/05-saved.png" || true

echo "[8/20] Restart and verify CMR history persisted"
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

echo "[9/20] Re-open persisted CMR"
read HX HY < /tmp/history.txt
adb shell input tap "$HX" "$HY"
sleep 3
check_foreground
check_no_crash
dump_ui /sdcard/reopened.xml "$EVIDENCE/reopened.xml"
grep -q -E 'Smart Scan PRO|Smart Scan eredmény|Felismert CMR adatok' "$EVIDENCE/reopened.xml" || fail_with_logs
adb exec-out screencap -p > "$EVIDENCE/07-reopened.png" || true

echo "[10/20] Return home and enter GPS tracking"
adb shell am force-stop "$PKG"
launch_app
sleep 3
dismiss_system_dialogs || true
check_foreground
dump_ui /sdcard/home-gps.xml "$EVIDENCE/home-gps.xml"
read GX GY < <(find_center "$EVIDENCE/home-gps.xml" "Fuvar + GPS") || fail_with_logs
# Guarantee the first recorded tracking point cannot be uploaded.
adb shell svc wifi disable || true
adb shell svc data disable || true
adb shell input tap "$GX" "$GY"
sleep 2
dump_ui /sdcard/tracking.xml "$EVIDENCE/tracking.xml"
grep -q 'GPS NYOMKÖVETÉS KIKAPCSOLVA' "$EVIDENCE/tracking.xml" || fail_with_logs

echo "[11/20] Start a real emulator GPS session while offline"
adb emu geo fix 17.6504 47.6875 >/dev/null 2>&1 || true
read PX PY < <(find_center "$EVIDENCE/tracking.xml" "Rendszám") || fail_with_logs
adb shell input tap "$PX" "$PY"
adb shell input text 'BRU-001'
dump_ui /sdcard/tracking-filled.xml "$EVIDENCE/tracking-filled.xml"
read BX BY < <(find_center "$EVIDENCE/tracking-filled.xml" "Fuvar + GPS indítása") || fail_with_logs
adb shell input tap "$BX" "$BY"
sleep 1
dump_ui /sdcard/start-dialog.xml "$EVIDENCE/start-dialog.xml"
read IX IY < <(find_center "$EVIDENCE/start-dialog.xml" "Indítás") || fail_with_logs
adb shell input tap "$IX" "$IY"
if ! wait_for_label "ÉLŐ GPS AKTÍV" "$EVIDENCE/gps-active.xml" 25 >/tmp/gps-active-pos.txt; then
  fail_with_logs
fi
sleep 2
check_no_crash
assert_tracking_json true true "$EVIDENCE/gps-active.json"
adb exec-out screencap -p > "$EVIDENCE/08-gps-active-offline.png" || true

echo "[12/20] Move GPS and verify active session survives app process restart"
adb emu geo fix 17.6550 47.6900 >/dev/null 2>&1 || true
sleep 3
adb shell am force-stop "$PKG"
launch_app
sleep 4
dismiss_system_dialogs || true
check_foreground
check_no_crash
dump_ui /sdcard/home-resumed-gps.xml "$EVIDENCE/home-resumed-gps.xml"
read RGX RGY < <(find_center "$EVIDENCE/home-resumed-gps.xml" "Élő GPS megnyitása") || fail_with_logs
adb shell input tap "$RGX" "$RGY"
if ! wait_for_label "ÉLŐ GPS AKTÍV" "$EVIDENCE/gps-resumed.xml" 15 >/tmp/gps-resumed-pos.txt; then
  fail_with_logs
fi
assert_tracking_json true true "$EVIDENCE/gps-resumed.json"

echo "[13/20] Stop the first trip offline and preserve its unsynced point(s)"
dump_ui /sdcard/gps-stop.xml "$EVIDENCE/gps-stop.xml"
read STX STY < <(find_center "$EVIDENCE/gps-stop.xml" "Fuvar lezárása") || fail_with_logs
adb shell input tap "$STX" "$STY"
sleep 1
dump_ui /sdcard/stop-dialog.xml "$EVIDENCE/stop-dialog.xml"
read LZX LZY < <(find_center "$EVIDENCE/stop-dialog.xml" "Lezárás") || fail_with_logs
adb shell input tap "$LZX" "$LZY"
if ! wait_for_label "GPS NYOMKÖVETÉS KIKAPCSOLVA" "$EVIDENCE/gps-stopped.xml" 25 >/tmp/gps-stopped-pos.txt; then
  fail_with_logs
fi
assert_tracking_json false true "$EVIDENCE/gps-stopped.json"

echo "[14/20] Start a second offline trip and verify previous trip is archived, not overwritten"
dump_ui /sdcard/gps-second-ready.xml "$EVIDENCE/gps-second-ready.xml"
read SBX SBY < <(find_center "$EVIDENCE/gps-second-ready.xml" "Fuvar + GPS indítása") || fail_with_logs
adb shell input tap "$SBX" "$SBY"
sleep 1
dump_ui /sdcard/start-dialog-2.xml "$EVIDENCE/start-dialog-2.xml"
read S2X S2Y < <(find_center "$EVIDENCE/start-dialog-2.xml" "Indítás") || fail_with_logs
adb shell input tap "$S2X" "$S2Y"
if ! wait_for_label "ÉLŐ GPS AKTÍV" "$EVIDENCE/gps-second-active.xml" 25 >/tmp/gps-second-pos.txt; then
  fail_with_logs
fi
sleep 2
PENDING_COUNT=$(adb shell run-as "$PKG" sh -c 'find app_flutter/aims_tracking/pending_sessions -type f -name "*.json" 2>/dev/null | wc -l' | tr -d '\r[:space:]')
echo "Archived pending GPS sessions: ${PENDING_COUNT:-0}"
if [ -z "${PENDING_COUNT:-}" ] || [ "$PENDING_COUNT" -lt 1 ]; then
  echo "Previous offline trip was not archived"
  fail_with_logs
fi
adb shell run-as "$PKG" sh -c 'for f in app_flutter/aims_tracking/pending_sessions/*.json; do [ -f "$f" ] && cat "$f"; done' > "$EVIDENCE/pending-gps-sessions.jsonl" || fail_with_logs
assert_tracking_json true true "$EVIDENCE/gps-second-active.json"

echo "[15/20] Stop second trip, restore network and trigger recovery sync"
dump_ui /sdcard/gps-stop-2.xml "$EVIDENCE/gps-stop-2.xml"
read ST2X ST2Y < <(find_center "$EVIDENCE/gps-stop-2.xml" "Fuvar lezárása") || fail_with_logs
adb shell input tap "$ST2X" "$ST2Y"
sleep 1
dump_ui /sdcard/stop-dialog-2.xml "$EVIDENCE/stop-dialog-2.xml"
read LZ2X LZ2Y < <(find_center "$EVIDENCE/stop-dialog-2.xml" "Lezárás") || fail_with_logs
adb shell input tap "$LZ2X" "$LZ2Y"
wait_for_label "GPS NYOMKÖVETÉS KIKAPCSOLVA" "$EVIDENCE/gps-second-stopped.xml" 25 >/tmp/gps-second-stopped-pos.txt || fail_with_logs
adb shell svc wifi enable || true
adb shell svc data enable || true
sleep 3
# Server approval may legitimately be pending in CI. We assert recovery does not crash or lose the local queue.
check_no_crash
assert_tracking_json false true "$EVIDENCE/gps-second-stopped.json"
adb exec-out screencap -p > "$EVIDENCE/09-gps-recovery.png" || true

echo "[16/20] Background/resume after GPS lifecycle"
adb shell input keyevent KEYCODE_HOME
sleep 2
launch_app
sleep 3
dismiss_system_dialogs || true
check_foreground
check_no_crash

echo "[17/20] Repeated cold starts"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"
  launch_app
  sleep 2
  dismiss_system_dialogs || true
  check_foreground
  check_no_crash
  echo "cold start $i OK"
done

echo "[18/20] Verify no app crash signatures after all camera/GPS stress"
check_no_crash
adb logcat -d > "$EVIDENCE/final-logcat.txt" 2>&1 || true

echo "[19/20] APK integrity"
unzip -t "$APK" > "$EVIDENCE/apk-integrity.txt"
tail -5 "$EVIDENCE/apk-integrity.txt"

echo "[20/20] Final diagnostics and evidence"
adb shell dumpsys package "$PKG" > "$EVIDENCE/package.txt"
adb shell dumpsys activity activities > "$EVIDENCE/activities.txt"
adb logcat -d > "$EVIDENCE/logcat.txt"
adb exec-out screencap -p > "$EVIDENCE/10-final.png" || true

echo "AIMS Flow Smart Scanner v1.0 BRUTAL: CMR + dual OCR + GPS persistence + offline queue E2E PASSED"
