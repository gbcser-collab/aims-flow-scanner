"""Real session endpoint: immutable document retries and driver ownership."""
import base64
import hashlib
import json
import os
import sqlite3
import struct
import urllib.error
import urllib.request
import zlib
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ['AIMS_TRACKING_DATA_DIR'])
db = sqlite3.connect(root / 'tracking.sqlite')
now = datetime.now(timezone.utc).isoformat()
admin = db.execute('SELECT admin_user_id FROM vehicles WHERE plate="V190001"').fetchone()[0]
db.execute('INSERT INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?)',
           ('V199001', 'Smart Test', admin, 1, now))
vehicle = db.execute('SELECT last_insert_rowid()').fetchone()[0]
for flow, token in [('199001', '9' * 64), ('199002', '8' * 64)]:
    db.execute('INSERT INTO driver_accounts(flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
               (flow, 'test-only', flow + '@example.test', 'Smart Test', vehicle, 1, 1, now, now))
    account = db.execute('SELECT last_insert_rowid()').fetchone()[0]
    db.execute('INSERT INTO driver_sessions(token_hash,account_id,device_id,created_at,expires_at,last_seen_at) VALUES (?,?,?,?,?,?)',
               (hashlib.sha256(token.encode()).hexdigest(), account, token, now, '2099-01-01T00:00:00+00:00', now))
db.commit()

def png(color):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 3, 3, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress((b'\0' + bytes(color) * 3) * 3)) + chunk(b'IEND', b''))

image = png((80, 120, 200))
first = {'localId': 'http199-first', 'plate': 'V199001', 'flowId': '199001', 'type': 'pod',
         'capturedAt': '2026-10-22T08:00:00.123456Z', 'ocrText': 'POD test', 'confidence': 0.9,
         'image': {'base64': base64.b64encode(image).decode()}}

def post(payload, token='9' * 64):
    request = urllib.request.Request('http://127.0.0.1:8099/session/smart_document.php',
        data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())

for repeat in range(2):
    status, body = post(first)
    assert status == 200 and body['ok'] and body['duplicate'] == bool(repeat), (status, body)
    assert body['localId'] == first['localId'] and body['state'] == 'uploaded', body
row = db.execute('SELECT id,vehicle_id,flow_id,payload_hash,image_path FROM smart_documents WHERE local_id=?', (first['localId'],)).fetchone()
assert row[1:3] == (vehicle, '199001') and len(row[3]) == 64, row
saved = root / row[4]
assert saved.read_bytes() == image
for changes in [{'ocrText': 'different'}, {'confidence': 0.8}, {'type': 'other'},
                {'capturedAt': '2026-10-22T08:00:00.123457Z'},
                {'image': {'base64': base64.b64encode(png((1, 2, 3))).decode()}}]:
    status, body = post(dict(first, **changes))
    assert status == 409 and body['error'] == 'document_identity_conflict', (status, body)
    assert saved.read_bytes() == image
status, body = post(dict(first, localId='wrong-owner', flowId='199002'))
assert status == 403 and body['error'] == 'document_owner_forbidden', (status, body)
status, body = post(dict(first, localId='smart_199002_forged'))
assert status == 403 and body['error'] == 'document_owner_forbidden', (status, body)
status, body = post(dict(first, flowId='199002'), token='8' * 64)
assert status == 409 and body['error'] == 'document_identity_conflict', (status, body)
status, body = post(dict(first, plate='OTHER123'))
assert status == 403 and body['error'] == 'plate_forbidden', (status, body)
# Pre-owner clients still get the authenticated owner for newly captured data.
legacy_client = dict(first, localId='http199-no-owner-claim')
del legacy_client['flowId']
status, body = post(legacy_client)
assert status == 200 and body['ok'], (status, body)
assert db.execute('SELECT flow_id FROM smart_documents WHERE local_id=?', (legacy_client['localId'],)).fetchone()[0] == '199001'
# Loss/corruption of an already stored image cannot receive a success receipt.
saved.write_bytes(b'damaged')
status, body = post(first)
assert status == 500 and body['error'] == 'stored_image_unavailable', (status, body)
saved.write_bytes(image)
status, body = post(first)
assert status == 200 and body['duplicate'], (status, body)
assert db.execute('SELECT count(*) FROM smart_documents WHERE vehicle_id=?', (vehicle,)).fetchone()[0] == 2
assert not list((root / 'smart-documents').rglob('*.tmp'))
db.close()
print('SMART DOCUMENT SESSION OWNERSHIP, IMMUTABLE REPLAY AND STORED-IMAGE HTTP CHECKS PASSED')
