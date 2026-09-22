#!/usr/bin/env python3
import json
import os
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "r94-integration-token-0123456789"

def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]

def request(port, path, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/{path}",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode())

with tempfile.TemporaryDirectory(prefix="aims-r94-") as temp:
    env = os.environ.copy()
    env["AIMS_TRACKING_DATA_DIR"] = temp
    env["AIMS_TRACKING_TOKEN"] = TOKEN
    env["AIMS_DEFAULT_ADMIN_NAME"] = "R94 Test Admin"

    seed = r'''
    require "server/aims-tracking/bootstrap.php";
    $pdo=aims_db();
    $now=gmdate(DateTimeInterface::ATOM);
    $pdo->prepare("INSERT OR IGNORE INTO vehicles (plate,label,admin_user_id,enabled,created_at) VALUES (:p,:l,1,1,:c)")
        ->execute([":p"=>"SIP115",":l"=>"SIP-115",":c"=>$now]);
    $pdo->prepare("INSERT INTO jobs (reference,vehicle_id,status,created_at,updated_at) VALUES (:r,1,'active',:c,:u)")
        ->execute([":r"=>"R94-IDEMPOTENCY",":c"=>$now,":u"=>$now]);
    $jobId=(int)$pdo->lastInsertId();
    $pdo->prepare("INSERT INTO job_stops (job_id,stop_type,stop_order,address,latitude,longitude,created_at) VALUES (:j,'pickup',1,'R94 Test Stop',47.68,17.63,:c)")
        ->execute([":j"=>$jobId,":c"=>$now]);
    '''
    subprocess.run(["php", "-r", seed], cwd=ROOT, env=env, check=True)

    port = free_port()
    server = subprocess.Popen(
        ["php", "-S", f"127.0.0.1:{port}", "-t", str(ROOT)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=.2):
                    break
            except OSError:
                time.sleep(.05)
        else:
            raise AssertionError("PHP test server did not start")

        message = {
            "plate": "SIP-115",
            "message": "R94 idempotency test",
            "clientMessageId": "msg_r94_001",
        }
        s1, a = request(port, "server/aims-tracking/driver_messages.php", message)
        s2, b = request(port, "server/aims-tracking/driver_messages.php", message)
        assert s1 == 200 and s2 == 200, (s1, a, s2, b)
        assert a["message"]["id"] == b["message"]["id"], (a, b)
        assert a.get("deduplicated") is False, a
        assert b.get("deduplicated") is True, b

        s3, c = request(port, "server/aims-tracking/driver_messages.php", {
            **message, "message": "DIFFERENT BODY",
        })
        assert s3 == 409 and c.get("error") == "client_message_id_conflict", (s3, c)

        signal = {
            "plate": "SIP-115",
            "type": "Késés",
            "message": "Forgalom",
            "eventId": "sig_r94_001",
            "occurredAt": "2026-09-22T03:00:00Z",
            "urgent": False,
            "latitude": 47.68,
            "longitude": 17.63,
        }
        s4, d = request(port, "server/aims-tracking/driver_event.php", signal)
        s5, e = request(port, "server/aims-tracking/driver_event.php", signal)
        assert s4 == 200 and s5 == 200, (s4, d, s5, e)

        arrived = {
            "plate": "SIP-115",
            "stopId": 1,
            "action": "arrived",
            "source": "touch",
            "occurredAt": "2026-09-22T03:01:00Z",
        }
        sa1, ra1 = request(port, "server/aims-tracking/driver_stop_action.php", arrived)
        sa2, ra2 = request(port, "server/aims-tracking/driver_stop_action.php", arrived)
        assert sa1 == 200 and sa2 == 200, (sa1, ra1, sa2, ra2)
        assert ra1.get("changed") is True, ra1
        assert ra2.get("changed") is False, ra2

        completed = {**arrived, "action": "completed", "occurredAt": "2026-09-22T03:02:00Z"}
        sc1, rc1 = request(port, "server/aims-tracking/driver_stop_action.php", completed)
        sc2, rc2 = request(port, "server/aims-tracking/driver_stop_action.php", completed)
        assert sc1 == 200 and sc2 == 200, (sc1, rc1, sc2, rc2)
        assert rc1.get("changed") is True, rc1
        assert rc2.get("changed") is False, rc2

        db = sqlite3.connect(Path(temp) / "tracking.sqlite")
        message_count = db.execute(
            "SELECT COUNT(*) FROM driver_messages WHERE vehicle_id=1 AND client_message_id=?",
            ("msg_r94_001",),
        ).fetchone()[0]
        signal_count = db.execute(
            "SELECT COUNT(*) FROM notifications WHERE vehicle_id=1 AND type='driver_signal'"
        ).fetchone()[0]
        arrival_count = db.execute(
            "SELECT COUNT(*) FROM notifications WHERE vehicle_id=1 AND type='job_arrival'"
        ).fetchone()[0]
        completion_count = db.execute(
            "SELECT COUNT(*) FROM notifications WHERE vehicle_id=1 AND type='job_stop_completed'"
        ).fetchone()[0]
        job_status = db.execute(
            "SELECT status FROM jobs WHERE reference='R94-IDEMPOTENCY'"
        ).fetchone()[0]
        assert message_count == 1, message_count
        assert signal_count == 1, signal_count
        assert arrival_count == 1, arrival_count
        assert completion_count == 1, completion_count
        assert job_status == "document_pending", job_status

        print("R94_BACKEND_IDEMPOTENCY_PASS")
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
