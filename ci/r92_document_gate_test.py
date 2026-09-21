#!/usr/bin/env python3
import json
import os
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "ci-test-token"
BASE = "http://127.0.0.1:18082"


def request(path, method="GET", payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {TOKEN}",
        },
    )
    with urllib.request.urlopen(req, timeout=8) as response:
        body = json.loads(response.read().decode("utf-8"))
        if not body.get("ok"):
            raise AssertionError(f"{path} returned not-ok: {body}")
        return body


def main():
    with tempfile.TemporaryDirectory(prefix="aims-r92-document-gate-") as data_dir:
        env = os.environ.copy()
        env["AIMS_TRACKING_DATA_DIR"] = data_dir
        env["AIMS_TRACKING_TOKEN"] = TOKEN

        subprocess.run(
            [
                "php",
                "-r",
                'require "server/aims-tracking/bootstrap.php"; aims_db();',
            ],
            cwd=ROOT,
            env=env,
            check=True,
        )

        db_path = Path(data_dir) / "tracking.sqlite"
        con = sqlite3.connect(db_path)
        now = "2026-09-21T12:00:00+00:00"
        con.execute(
            "INSERT INTO vehicles (plate,label,device_id,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?,?)",
            ("SIP115", "SIP-115", "ci-doc-device", 1, 1, now),
        )
        vehicle_id = con.execute(
            "SELECT id FROM vehicles WHERE plate='SIP115'"
        ).fetchone()[0]
        con.execute(
            """INSERT INTO jobs
               (reference,vehicle_id,status,created_at,updated_at,driver_accepted_at)
               VALUES (?,?,?,?,?,?)""",
            ("DOC-GATE-1", vehicle_id, "active", now, now, now),
        )
        job_id = con.execute(
            "SELECT id FROM jobs WHERE reference='DOC-GATE-1'"
        ).fetchone()[0]
        con.execute(
            """INSERT INTO job_stops
               (job_id,stop_type,stop_order,company,address,latitude,longitude,radius_m,created_at)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            (
                job_id,
                "delivery",
                1,
                "CI Delivery",
                "Test address 1",
                47.0,
                19.0,
                180.0,
                now,
            ),
        )
        stop_id = con.execute(
            "SELECT id FROM job_stops WHERE job_id=?", (job_id,)
        ).fetchone()[0]
        con.commit()
        con.close()

        server = subprocess.Popen(
            ["php", "-S", "127.0.0.1:18082", "-t", "server/aims-tracking"],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            time.sleep(1.0)

            request(
                "/driver_stop_action.php",
                "POST",
                {
                    "plate": "SIP-115",
                    "stopId": stop_id,
                    "action": "completed",
                    "source": "touch",
                    "occurredAt": now,
                },
            )

            con = sqlite3.connect(db_path)
            row = con.execute(
                "SELECT status,document_received_at FROM jobs WHERE id=?",
                (job_id,),
            ).fetchone()
            assert row == ("document_pending", None), row
            con.close()

            visible = request("/driver_jobs.php?plate=SIP-115")
            jobs = visible.get("jobs", [])
            assert len(jobs) == 1, jobs
            assert jobs[0]["id"] == job_id, jobs
            assert jobs[0]["status"] == "document_pending", jobs

            request(
                "/driver_job_document.php",
                "POST",
                {
                    "plate": "SIP-115",
                    "jobId": job_id,
                    "documentId": "local-cmr-ci-1",
                    "syncState": "pending",
                },
            )

            con = sqlite3.connect(db_path)
            row = con.execute(
                """SELECT status,document_local_id,document_sync_state,
                          document_received_at
                   FROM jobs WHERE id=?""",
                (job_id,),
            ).fetchone()
            assert row[0] == "completed", row
            assert row[1] == "local-cmr-ci-1", row
            assert row[2] == "pending", row
            assert row[3], row
            con.close()

            hidden = request("/driver_jobs.php?plate=SIP-115")
            assert hidden.get("jobs") == [], hidden

            print("PASS: R92 document gate lifecycle")
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
            if server.stdout:
                tail = server.stdout.read()
                if server.returncode not in (0, -15):
                    print(tail)


if __name__ == "__main__":
    main()
