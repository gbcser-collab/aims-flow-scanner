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

        db = sqlite3.connect(Path(temp) / "tracking.sqlite")
        message_count = db.execute(
            "SELECT COUNT(*) FROM driver_messages WHERE vehicle_id=1 AND client_message_id=?",
            ("msg_r94_001",),
        ).fetchone()[0]
        signal_count = db.execute(
            "SELECT COUNT(*) FROM notifications WHERE vehicle_id=1 AND type='driver_signal'"
        ).fetchone()[0]
        assert message_count == 1, message_count
        assert signal_count == 1, signal_count

        print("R94_BACKEND_IDEMPOTENCY_PASS")
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
