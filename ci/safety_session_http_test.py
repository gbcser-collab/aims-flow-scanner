"""Real multipart requests against the isolated CI backend, never production."""
import hashlib
import json
import os
import sqlite3
import struct
import urllib.error
import urllib.request
import uuid
import zlib
from pathlib import Path

root = Path(os.environ['AIMS_TRACKING_DATA_DIR'])
db = sqlite3.connect(root / 'tracking.sqlite')
token = (Path(os.environ['RUNNER_TEMP']) / 'flow-session-token').read_text()

def png(rgb):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\0' + bytes(rgb))) + chunk(b'IEND', b'')

image = png((10, 20, 30))
other_image = png((90, 80, 70))
kinds = ('oil', 'coolant', 'tires', 'odometer')
baseline = {'action': 'safety_check', 'flowId': '190001', 'plate': 'V190001',
            'id': 'safety-ci-1', 'km': '100250', 'createdAt': '2026-10-21T08:30:00Z',
            'statuses': json.dumps({'oil': 'ok', 'coolant': 'ok', 'tires': 'ok', 'steering': 'ok'})}

def post(fields, files=None, auth=token):
    files = files if files is not None else {kind: image for kind in kinds}
    boundary = 'flow-' + uuid.uuid4().hex
    body = bytearray()
    for key, value in fields.items():
        body.extend(('--' + boundary + '\r\nContent-Disposition: form-data; name="' + key + '"\r\n\r\n' + value + '\r\n').encode())
    for kind, data in files.items():
        body.extend(('--' + boundary + '\r\nContent-Disposition: form-data; name="photo_' + kind + '"; filename="' + kind + '.png"\r\nContent-Type: image/png\r\n\r\n').encode())
        body.extend(data + b'\r\n')
    body.extend(('--' + boundary + '--\r\n').encode())
    request = urllib.request.Request('http://127.0.0.1:8099/session/driver_ops_v2.php',
        data=bytes(body), headers={'Authorization': 'Bearer ' + auth,
                                'Content-Type': 'multipart/form-data; boundary=' + boundary})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())

def count(table):
    assert table in ('vehicle_safety_checks', 'vehicle_safety_photos', 'vehicle_odometer_log')
    return db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0]

odo = count('vehicle_odometer_log')
for _ in range(2):
    status, body = post(baseline)
    assert status == 200 and body['ok'], (status, body)
assert count('vehicle_safety_checks') == 1

# A storage failure on the fourth photo rolls back rows and earlier files.
vehicle_id = db.execute('SELECT id FROM vehicles WHERE plate="V190001"').fetchone()[0]
failure_id = 'rollback-last-photo'
blocked = root / 'safety' / str(vehicle_id) / (hashlib.sha256(failure_id.encode()).hexdigest() + '_odometer_' + hashlib.sha256(image).hexdigest() + '.png')
blocked.mkdir()
try:
    status, body = post(dict(baseline, id=failure_id))
    assert status == 503 and body['error'] == 'photo_store_odometer', (status, body)
finally:
    blocked.rmdir()
assert count('vehicle_safety_checks') == 1 and count('vehicle_safety_photos') == 4
assert len([p for p in (root / 'safety').rglob('*') if p.is_file()]) == 4
assert count('vehicle_odometer_log') == odo + 1
row = db.execute('SELECT flow_id,km FROM vehicle_safety_checks').fetchone()
assert row == ('190001', 100250), row
stored = db.execute('SELECT relative_path FROM vehicle_safety_photos').fetchall()
assert all((root / item[0]).read_bytes() == image for item in stored)

for fields, files, error in [
    (dict(baseline, km='100251'), None, 'safety_snapshot_conflict'),
    (dict(baseline, statuses=json.dumps({'oil': 'problem', 'coolant': 'ok', 'tires': 'ok', 'steering': 'ok'})), None, 'safety_snapshot_conflict'),
    (baseline, {kind: other_image if kind == 'oil' else image for kind in kinds}, 'safety_photo_conflict'),
]:
    status, body = post(fields, files)
    assert status == 409 and body['error'] == error, (status, body)
assert all((root / item[0]).read_bytes() == image for item in stored)
assert count('vehicle_odometer_log') == odo + 1

# Validate the last photo before storing any row or file.
before_files = set((root / 'safety').rglob('*'))
bad_files = {kind: image if kind != 'odometer' else b'not-an-image' for kind in kinds}
status, body = post(dict(baseline, id='invalid-last-photo'), bad_files)
assert status == 422 and body['error'] == 'photo_type_odometer', (status, body)
assert count('vehicle_safety_checks') == 1 and count('vehicle_safety_photos') == 4
assert set((root / 'safety').rglob('*')) == before_files
status, body = post(dict(baseline, id='incomplete-checklist', statuses='{"oil":"ok"}'))
assert status == 422 and body['error'] == 'invalid_statuses', (status, body)
assert count('vehicle_safety_checks') == 1

# IDs that used to sanitize to the same filename must keep different bytes.
for client_id, photo in [('colon:check', image), ('colon_check', other_image)]:
    status, body = post(dict(baseline, id=client_id), {kind: photo for kind in kinds})
    assert status == 200 and body['ok'], (status, body)
paths = db.execute('SELECT p.relative_path FROM vehicle_safety_photos p JOIN vehicle_safety_checks c ON c.id=p.safety_check_id WHERE c.client_check_id IN (?,?)', ('colon:check', 'colon_check')).fetchall()
assert len(set(p[0] for p in paths)) == 8
for client_id, photo in [('colon:check', image), ('colon_check', other_image)]:
    paths_for_id = db.execute('SELECT p.relative_path FROM vehicle_safety_photos p JOIN vehicle_safety_checks c ON c.id=p.safety_check_id WHERE c.client_check_id=?', (client_id,)).fetchall()
    assert all((root / p[0]).read_bytes() == photo for p in paths_for_id)

# Another authenticated account cannot attach photos to this check ID.
now = '2026-10-21T00:00:00+00:00'
vehicle, admin = db.execute('SELECT id,admin_user_id FROM vehicles WHERE plate="V190001"').fetchone()
db.execute('INSERT INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?)', ('V193002', 'V193002', admin, 1, now))
other_vehicle = db.execute('SELECT last_insert_rowid()').fetchone()[0]
db.execute('INSERT INTO driver_accounts(flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
           ('190002', 'unused-test-hash', 'other@example.test', 'Other test driver', other_vehicle, 1, 1, now, now))
other_account = db.execute('SELECT last_insert_rowid()').fetchone()[0]
other_token = 'e' * 64
db.execute('INSERT INTO driver_sessions(token_hash,account_id,device_id,created_at,expires_at,last_seen_at) VALUES (?,?,?,?,?,?)',
           (hashlib.sha256(other_token.encode()).hexdigest(), other_account, 'e' * 64, now, '2099-01-01T00:00:00+00:00', now))
db.commit()
status, body = post(dict(baseline, plate='V193002', flowId='190002'), auth=other_token)
assert status == 409 and body['error'] == 'safety_id_conflict', (status, body)
db.execute('UPDATE driver_accounts SET vehicle_id=? WHERE id=?', (vehicle, other_account))
db.commit()
status, body = post(dict(baseline, flowId='190002'), auth=other_token)
assert status == 403 and body['error'] == 'safety_owner_forbidden', (status, body)
status, body = post(dict(baseline, flowId='999999', id='new-forged-owner'))
assert status == 403 and body['error'] == 'safety_owner_forbidden', (status, body)
assert count('vehicle_safety_checks') == 3 and count('vehicle_safety_photos') == 12
assert count('vehicle_odometer_log') == odo + 3

problem = dict(baseline, id='problem-once', statuses=json.dumps({'oil': 'problem', 'coolant': 'ok', 'tires': 'ok', 'steering': 'ok'}))
for _ in range(2):
    status, body = post(problem)
    assert status == 200 and body['hasProblem'], (status, body)
assert db.execute('SELECT COUNT(*) FROM notifications WHERE type="safety_check_problem"').fetchone()[0] == 1
assert count('vehicle_odometer_log') == odo + 4
db.close()
print('SAFETY MULTIPART OWNERSHIP, IMMUTABLE RETRIES, PHOTO VALIDATION AND FILENAME ISOLATION OK')
