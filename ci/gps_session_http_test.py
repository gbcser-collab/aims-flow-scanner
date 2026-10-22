"""GPS retries and account/vehicle handoff on an isolated local PHP server."""
import hashlib
import json
import os
import sqlite3
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

db = sqlite3.connect(Path(os.environ['AIMS_TRACKING_DATA_DIR']) / 'tracking.sqlite')
now = datetime.now(timezone.utc).replace(microsecond=0)
def stamp(value): return value.isoformat()
admin = db.execute('SELECT admin_user_id FROM vehicles WHERE plate="V190001"').fetchone()[0]
vehicles = []
for plate in ['V194001', 'V194002']:
    db.execute('INSERT INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?)',
               (plate, plate, admin, 1, stamp(now)))
    vehicles.append(db.execute('SELECT last_insert_rowid()').fetchone()[0])
db.execute('INSERT INTO driver_accounts(flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
           ('194001', 'test-only', 'gps@example.test', 'GPS Test', vehicles[0], 1, 1, stamp(now), stamp(now)))
account = db.execute('SELECT last_insert_rowid()').fetchone()[0]
token = 'f' * 64
device = 'f' * 64
db.execute('INSERT INTO driver_sessions(token_hash,account_id,device_id,created_at,expires_at,last_seen_at) VALUES (?,?,?,?,?,?)',
           (hashlib.sha256(token.encode()).hexdigest(), account, device, stamp(now), '2099-01-01T00:00:00+00:00', stamp(now)))
db.commit()

def post(payload):
    request = urllib.request.Request('http://127.0.0.1:8099/session/ingest.php',
        data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())

first = {'pointId': 'gps194-first', 'flowId': '194001', 'deviceId': device,
         'plate': 'V194001', 'vehicleLabel': 'V194001',
         'timestamp': stamp(now - timedelta(minutes=10)), 'latitude': 47.6875,
         'longitude': 17.6504, 'accuracy': 8, 'speedMps': 0, 'heading': 90,
         'altitude': 100, 'source': 'stream', 'countryCode': 'HU', 'delayed': True}
for retry in range(2):
    status, body = post(first)
    assert status == 200 and body['ok'] and body['registeredVehicle'], (status, body)
    assert body['duplicatePoint'] == bool(retry), body
row = db.execute('SELECT vehicle_id,flow_id,latitude,payload_hash FROM points WHERE point_key=?', (first['pointId'],)).fetchone()
assert row[:3] == (vehicles[0], '194001', 47.6875) and len(row[3]) == 64, row
for changes in [{'latitude': 47.0}, {'accuracy': 9}, {'countryCode': 'SK'},
                {'timestamp': stamp(now - timedelta(minutes=10, microseconds=500))}]:
    status, body = post(dict(first, **changes))
    assert status == 409 and body['error'] == 'point_identity_conflict', (status, body)
assert db.execute('SELECT vehicle_id,flow_id,latitude,payload_hash FROM points WHERE point_key=?', (first['pointId'],)).fetchone() == row
status, body = post(dict(first, pointId='gps194-forged', flowId='999999'))
assert status == 403 and body['error'] == 'point_owner_forbidden', (status, body)

# A historical point must not move current vehicle/country state backwards.
newest = dict(first, pointId='gps194-newest', timestamp=stamp(now - timedelta(minutes=1)))
status, body = post(newest)
assert status == 200 and not body['historicalPoint'], (status, body)
state_before = db.execute('SELECT * FROM vehicle_state WHERE vehicle_id=?', (vehicles[0],)).fetchall()
country_before = db.execute('SELECT * FROM vehicle_country_state WHERE vehicle_id=?', (vehicles[0],)).fetchall()
older = dict(first, pointId='gps194-old', timestamp=stamp(now - timedelta(minutes=20)),
             latitude=48.1, longitude=18.1, countryCode='SK', delayed=False)
status, body = post(older)
assert status == 200 and body['historicalPoint'], (status, body)
assert db.execute('SELECT * FROM vehicle_state WHERE vehicle_id=?', (vehicles[0],)).fetchall() == state_before
assert db.execute('SELECT * FROM vehicle_country_state WHERE vehicle_id=?', (vehicles[0],)).fetchall() == country_before
assert db.execute('SELECT COUNT(*) FROM points WHERE point_key=?', (older['pointId'],)).fetchone()[0] == 1

for bad_time in ['tomorrow', '2026-02-30T00:00:00Z', stamp(now + timedelta(days=2))]:
    status, body = post(dict(first, pointId='gps194-invalid-time', timestamp=bad_time))
    assert status == 422, (status, body)
assert db.execute('SELECT COUNT(*) FROM points WHERE point_key="gps194-invalid-time"').fetchone()[0] == 0

# The same authenticated phone is reassigned to a second vehicle. Old device
# binding must not override the explicitly authorized plate.
db.execute('UPDATE driver_accounts SET vehicle_id=? WHERE id=?', (vehicles[1], account))
db.commit()
second = dict(first, pointId='gps194-second-car', plate='V194002', vehicleLabel='V194002')
status, body = post(second)
assert status == 200 and body['registeredVehicle'], (status, body)
assert db.execute('SELECT vehicle_id FROM points WHERE point_key=?', (second['pointId'],)).fetchone()[0] == vehicles[1]
status, body = post(dict(second, pointId=first['pointId']))
assert status == 409 and body['error'] == 'point_identity_conflict', (status, body)
status, body = post(first)
assert status == 403 and body['error'] == 'plate_forbidden', (status, body)
# Omitting a plate also stays bound to the authenticated assignment.
missing_plate = dict(second, pointId='gps194-no-label')
del missing_plate['plate']; del missing_plate['vehicleLabel']
status, body = post(missing_plate)
assert status == 200 and body['registeredVehicle'], (status, body)
assert db.execute('SELECT vehicle_id FROM points WHERE point_key=?', (missing_plate['pointId'],)).fetchone()[0] == vehicles[1]

db.close()
print('GPS OWNERSHIP, IMMUTABLE RETRIES, VEHICLE HANDOFF AND HISTORICAL REPLAY HTTP CHECKS OK')
