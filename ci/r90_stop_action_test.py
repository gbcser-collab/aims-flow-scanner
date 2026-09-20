import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE_URL = os.environ.get("AIMS_CI_BASE_URL", "http://127.0.0.1:18080")
TOKEN = os.environ.get("AIMS_TRACKING_TOKEN", "ci-test-token")
DB_PATH = os.environ["AIMS_CI_DB_PATH"]


def request(path: str, method: str = "GET", body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw)
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw}
        return error.code, parsed


def expect(condition: bool, message: str):
    if not condition:
        print("FAIL:", message, file=sys.stderr)
        raise SystemExit(1)


def seed():
    db = sqlite3.connect(DB_PATH)
    now = datetime.now(timezone.utc).isoformat()
    vehicle_id = db.execute(
        "SELECT id FROM vehicles WHERE plate='SIP115' LIMIT 1"
    ).fetchone()[0]
    cur = db.execute(
        """INSERT INTO jobs
        (reference, vehicle_id, status, created_at, updated_at, driver_accepted_at)
        VALUES (?, ?, 'active', ?, ?, ?)""",
        ("R90-STOP-E2E", vehicle_id, now, now, now),
    )
    job_id = cur.lastrowid
    stops = [
        ("pickup", 1, "Pickup Kft.", "Győr, Ipari park 1.", "+36301234567", 47.687, 17.650),
        ("delivery", 2, "Delivery GmbH", "Wien, Handelskai 1.", "+4312345678", 48.230, 16.410),
    ]
    ids = []
    for stop_type, order, company, address, phone, lat, lng in stops:
        cur = db.execute(
            """INSERT INTO job_stops
            (job_id, stop_type, stop_order, company, address, contact_phone,
             latitude, longitude, radius_m, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 180, ?)""",
            (job_id, stop_type, order, company, address, phone, lat, lng, now),
        )
        ids.append(cur.lastrowid)
    db.commit()
    db.close()
    return job_id, ids


def main():
    job_id, stop_ids = seed()

    status, jobs = request("/driver_jobs.php?plate=SIP-115")
    expect(status == 200 and jobs.get("ok") is True, "driver_jobs initial request")
    expect(len(jobs.get("jobs", [])) == 1, "one active job expected")
    initial_stops = jobs["jobs"][0]["stops"]
    expect([s["order"] for s in initial_stops] == [1, 2], "stop order must be 1,2")
    expect(initial_stops[0]["phone"] == "+36301234567", "pickup phone must survive API")
    expect(initial_stops[1]["phone"] == "+4312345678", "delivery phone must survive API")

    event_base = datetime.now(timezone.utc).replace(microsecond=0)
    arrived_at = event_base - timedelta(minutes=2)
    first_done_at = event_base - timedelta(minutes=1)
    second_done_at = event_base - timedelta(seconds=20)

    status, arrived = request(
        "/driver_stop_action.php",
        "POST",
        {
            "plate": "SIP-115",
            "stopId": stop_ids[0],
            "action": "arrived",
            "source": "touch",
            "occurredAt": arrived_at.isoformat(),
        },
    )
    expect(status == 200 and arrived.get("changed") is True, "arrival should change once")
    expect(arrived.get("arrived") is True and arrived.get("completed") is False, "arrival flags")

    status, arrived_again = request(
        "/driver_stop_action.php",
        "POST",
        {
            "plate": "SIP-115",
            "stopId": stop_ids[0],
            "action": "arrived",
            "source": "touch",
            "occurredAt": arrived_at.isoformat(),
        },
    )
    expect(status == 200 and arrived_again.get("changed") is False, "arrival must be idempotent")

    status, first_done = request(
        "/driver_stop_action.php",
        "POST",
        {
            "plate": "SIP-115",
            "stopId": stop_ids[0],
            "action": "completed",
            "source": "touch",
            "occurredAt": first_done_at.isoformat(),
        },
    )
    expect(status == 200 and first_done.get("completed") is True, "first stop completion")

    status, jobs_mid = request("/driver_jobs.php?plate=SIP-115")
    expect(status == 200 and len(jobs_mid.get("jobs", [])) == 1, "job remains active after first stop")
    expect(jobs_mid["jobs"][0]["stops"][0]["completed"] is True, "first stop is completed")
    expect(jobs_mid["jobs"][0]["stops"][1]["completed"] is False, "second stop still open")

    status, second_done = request(
        "/driver_stop_action.php",
        "POST",
        {
            "plate": "SIP-115",
            "stopId": stop_ids[1],
            "action": "completed",
            "source": "touch",
            "occurredAt": second_done_at.isoformat(),
        },
    )
    expect(status == 200 and second_done.get("completed") is True, "second stop completion")

    status, jobs_end = request("/driver_jobs.php?plate=SIP-115")
    expect(status == 200 and jobs_end.get("jobs") == [], "completed job must leave active list")

    db = sqlite3.connect(DB_PATH)
    job_status = db.execute("SELECT status FROM jobs WHERE id=?", (job_id,)).fetchone()[0]
    rows = db.execute(
        """SELECT arrival_notified_at, arrival_source, completed_at, completion_source
        FROM job_stops WHERE job_id=? ORDER BY stop_order""",
        (job_id,),
    ).fetchall()
    db.close()

    expect(job_status == "completed", "job database status must be completed")
    expect([row[3] for row in rows] == ["touch", "touch"], "touch completion source must be preserved")
    expect(rows[0][1] == "touch", "touch arrival source must be preserved")
    expect(rows[0][0] == arrived_at.isoformat(), "offline arrival timestamp must be preserved")
    expect(rows[0][2] == first_done_at.isoformat(), "first completion timestamp must be preserved")
    expect(rows[1][2] == second_done_at.isoformat(), "second completion timestamp must be preserved")
    print(
        "PASS stop_action_e2e "
        f"job={job_id} stops={stop_ids} final_status={job_status} "
        f"arrival={rows[0][0]} completions={[row[2] for row in rows]}"
    )


if __name__ == "__main__":
    main()