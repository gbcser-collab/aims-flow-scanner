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
print('REST SESSION OWNERSHIP, IDEMPOTENCY AND WORKDAY OWNER HTTP CHECKS OK')

# A lost HTTP response must be safe to retry, including a whole offline day.
start = {'action': 'workday_start', 'plate': 'V190001',
         'workdayId': '190001-retry-day', 'startedAt': '2026-10-20T06:00:00Z',
         'startKm': 100100}
finish = dict(start, action='workday_finish', finishedAt='2026-10-20T14:00:00Z', endKm=100200)
count_before = db.execute('SELECT COUNT(*) FROM vehicle_odometer_log').fetchone()[0]
for payload in [start, start, finish, finish, start]:
    status, body = post('driver_ops_v2.php', payload)
    assert status == 200 and body['ok'], (status, body)
assert db.execute('SELECT COUNT(*) FROM vehicle_odometer_log').fetchone()[0] == count_before + 2
row = db.execute('SELECT finished_at,end_km FROM driver_workdays WHERE workday_key=?',
                 (start['workdayId'],)).fetchone()
assert row == ('2026-10-20T14:00:00+00:00', 100200), row
for payload, error in [
    (dict(start, startKm=99999), 'workday_start_conflict'),
    (dict(finish, endKm=100201), 'workday_finish_conflict'),
    (dict(finish, finishedAt='2026-10-20T15:00:00Z'), 'workday_finish_conflict'),
]:
    status, body = post('driver_ops_v2.php', payload)
    assert status == 409 and body['error'] == error, (status, body)
assert db.execute('SELECT finished_at,end_km FROM driver_workdays WHERE workday_key=?',
                  (start['workdayId'],)).fetchone() == row

for payload, error in [
    (dict(finish, workdayId='190001-bad-km', endKm=100099), 'end_km_before_start'),
    (dict(finish, workdayId='190001-bad-time', finishedAt='2026-10-20T05:00:00Z'), 'finish_before_start'),
]:
    status, body = post('driver_ops_v2.php', payload)
    assert status == 409 and body['error'] == error, (status, body)
    assert db.execute('SELECT COUNT(*) FROM driver_workdays WHERE workday_key=?',
                      (payload['workdayId'],)).fetchone()[0] == 0
assert db.execute('SELECT COUNT(*) FROM vehicle_odometer_log').fetchone()[0] == count_before + 2

offline = dict(finish, workdayId='190001-entire-offline-day')
for _ in range(2):
    status, body = post('driver_ops_v2.php', offline)
    assert status == 200 and body['ok'], (status, body)
assert db.execute('SELECT COUNT(*) FROM vehicle_odometer_log').fetchone()[0] == count_before + 4
assert db.execute('SELECT COUNT(*) FROM driver_workdays WHERE workday_key=?',
                  (offline['workdayId'],)).fetchone()[0] == 1

db.close()
print('WORKDAY RETRY, IMMUTABILITY, OFFLINE RECONSTRUCTION AND ROLLBACK HTTP CHECKS OK')
