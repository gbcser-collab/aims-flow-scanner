#!/usr/bin/env bash
set -euxo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -rf data

export AIMS_TRACKING_TOKEN='write-token-test-1234567890'
export AIMS_ADMIN_TRACKING_TOKEN='admin-token-test-1234567890'
php -S 127.0.0.1:8092 >/tmp/aims-tracking-test.log 2>&1 &
SERVER_PID=$!
trap 'status=$?; if [ $status -ne 0 ]; then cat /tmp/aims-tracking-test.log || true; fi; kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$ROOT/data"; exit $status' EXIT
sleep 1

curl -fsS -H "Authorization: Bearer $AIMS_ADMIN_TRACKING_TOKEN" -H "Content-Type: application/json" -X POST   --data '{"plate":"SIP-115","label":"SIP-115"}'   http://127.0.0.1:8092/vehicle_registry.php >/tmp/vehicle.json

curl -fsS -H "Authorization: Bearer $AIMS_ADMIN_TRACKING_TOKEN" -H "Content-Type: application/json" -X POST   --data '{"plate":"SIP-115","driverJob":{"reference":"TEST-001","pickups":[{"company":"Test Pickup","address":"Test address","latitude":47.1000,"longitude":18.1000}],"deliveries":[{"company":"Test Delivery","address":"Test delivery","latitude":48.1000,"longitude":19.1000}]}}'   http://127.0.0.1:8092/job_assign.php >/tmp/job.json

point () {
  local ts="$1" lat="$2" lng="$3" speed="$4"
  local payload
  payload="$(python3 - "$ts" "$lat" "$lng" "$speed" <<'PY'
import json, sys
print(json.dumps({
    "deviceId": "test-device-1",
    "vehicleLabel": "SIP-115",
    "timestamp": sys.argv[1],
    "latitude": float(sys.argv[2]),
    "longitude": float(sys.argv[3]),
    "accuracy": 5,
    "speedMps": float(sys.argv[4]),
    "source": "heartbeat",
}))
PY
)"
  curl -fsS -H "Authorization: Bearer $AIMS_TRACKING_TOKEN" -H "Content-Type: application/json" -X POST     --data "$payload" http://127.0.0.1:8092/ingest.php >/dev/null
}

point '2026-09-18T08:00:00Z' 46.0000 17.0000 0
point '2026-09-18T08:15:00Z' 46.0000 17.0000 0
point '2026-09-18T08:30:00Z' 46.0000 17.0000 0
point '2026-09-18T09:00:00Z' 46.0000 17.0000 0

point '2026-09-18T09:01:00Z' 46.0001 17.0000 1.0
point '2026-09-18T09:16:00Z' 46.0001 17.0000 0

point '2026-09-18T09:20:00Z' 47.1000 18.1000 1.0
point '2026-09-18T09:21:00Z' 47.1000 18.1000 0

curl -fsS -H "Authorization: Bearer $AIMS_ADMIN_TRACKING_TOKEN"   http://127.0.0.1:8092/notifications.php >/tmp/notifications.json

python3 - <<'PY'
import json
d=json.load(open('/tmp/notifications.json'))
items=d['notifications']
stationary=[x for x in items if x['type']=='stationary']
arrival=[x for x in items if x['type']=='job_arrival']
assert len(stationary)==4, stationary
titles=' | '.join(x['title'] for x in stationary)
assert '15 perce' in titles and '30 perce' in titles and '60 perce' in titles, titles
assert len(arrival)==1, arrival
assert 'felrakóra' in arrival[0]['title'], arrival[0]
print('tracking endpoint integration: PASS')
PY

PNG='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z6mQAAAAASUVORK5CYII='
FUEL_PAYLOAD="$(python3 - "$PNG" <<'PY'
import json, sys
print(json.dumps({
    "deviceId": "test-device-1",
    "plate": "SIP-115",
    "capturedAt": "2026-09-18T09:30:00Z",
    "station": "Test Fuel",
    "totalAmount": 25000,
    "currency": "HUF",
    "liters": 40.5,
    "image": {"mimeType": "image/png", "base64": sys.argv[1]},
}))
PY
)"
curl -fsS -H "Authorization: Bearer $AIMS_TRACKING_TOKEN" -H "Content-Type: application/json" -X POST   --data "$FUEL_PAYLOAD" http://127.0.0.1:8092/fuel_receipt.php >/tmp/fuel-upload.json

curl -fsS -H "Authorization: Bearer $AIMS_ADMIN_TRACKING_TOKEN"   http://127.0.0.1:8092/fuel_receipt.php >/tmp/fuel-list.json

python3 - <<'PY'
import json
d=json.load(open('/tmp/fuel-list.json'))
assert len(d['receipts'])==1, d
assert d['receipts'][0]['plate']=='SIP-115', d
assert d['receipts'][0]['liters']==40.5, d
print('fuel receipt integration: PASS')
PY
