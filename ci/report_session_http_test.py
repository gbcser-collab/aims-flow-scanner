"""Exercise real local session endpoints; never contact production or send mail."""
import json
import os
import sqlite3
import urllib.error
import urllib.request
from pathlib import Path

token = (Path(os.environ['RUNNER_TEMP']) / 'flow-session-token').read_text()
db = sqlite3.connect(str(Path(os.environ['AIMS_TRACKING_DATA_DIR']) / 'tracking.sqlite'))

def post(endpoint, data):
    request = urllib.request.Request(
        'http://127.0.0.1:8099/session/' + endpoint,
        data=json.dumps(data).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)

status, body = post('driver_ops_v2.php', {
    'action': 'workday_start', 'plate': 'V190001', 'workdayId': '999999-wrong-owner',
    'startedAt': '2026-10-21T06:00:00Z', 'startKm': 100000,
})
assert status == 403 and body['error'] == 'workday_owner_forbidden', (status, body)
for _ in range(2):
    status, body = post('driver_rest_mode.php', {
        'plate': 'V190001', 'enabled': True, 'durationMinutes': 60, 'flowId': '999999',
    })
    assert status == 200 and body['restMode']['active'], (status, body)
rows = db.execute('SELECT flow_id,ended_at FROM driver_rest_periods').fetchall()
assert rows == [('190001', None)], rows
status, body = post('driver_rest_mode.php', {'plate': 'V190001', 'enabled': False})
assert status == 200 and not body['restMode']['active'], (status, body)
assert db.execute('SELECT ended_at FROM driver_rest_periods').fetchone()[0]
db.close()
print('REST SESSION OWNERSHIP, IDEMPOTENCY AND WORKDAY OWNER HTTP CHECKS OK')
