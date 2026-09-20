import concurrent.futures
import datetime as dt
import json
import os
import sqlite3
import statistics
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.environ.get("AIMS_CI_BASE_URL", "http://127.0.0.1:18080")
TOKEN = os.environ.get("AIMS_TRACKING_TOKEN", "ci-test-token")
DB_PATH = os.environ["AIMS_CI_DB_PATH"]
TOTAL = int(os.environ.get("AIMS_CI_LOAD_TOTAL", "10000"))
WORKERS = int(os.environ.get("AIMS_CI_LOAD_WORKERS", "16"))
COUNTRIES = ["HU", "SK", "AT", "DE", "PL", "CZ", "LT", "LV", "EE", "PL"]
START = dt.datetime(2026, 9, 20, tzinfo=dt.timezone.utc)


def point_id(i: int) -> str:
    if i > 0 and i % 10 == 0:
        return f"load-{i - 1}"
    return f"load-{i}"


def payload(i: int) -> bytes:
    country = COUNTRIES[min(len(COUNTRIES) - 1, i // max(1, TOTAL // len(COUNTRIES)))]
    timestamp = START + dt.timedelta(seconds=i * 15)
    body = {
        "pointId": point_id(i),
        "deviceId": "ci-load-device",
        "vehicleLabel": "SIP-115",
        "countryCode": country,
        "timestamp": timestamp.isoformat().replace("+00:00", "Z"),
        "latitude": 47.0 + (i % 1000) / 100000.0,
        "longitude": 17.0 + ((i * 37) % 1000) / 100000.0,
        "accuracy": 8.0 + (i % 30),
        "speedMps": float(i % 35),
        "heading": float(i % 360),
        "altitude": 100.0 + (i % 50),
        "source": "stream",
    }
    return json.dumps(body).encode("utf-8")


def send(i: int):
    request = urllib.request.Request(
        BASE_URL + "/ingest.php",
        data=payload(i),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + TOKEN,
        },
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read()
            elapsed = time.perf_counter() - started
            data = json.loads(raw.decode("utf-8"))
            return i, response.status, elapsed, data
    except urllib.error.HTTPError as error:
        elapsed = time.perf_counter() - started
        raw = error.read().decode("utf-8", errors="replace")
        return i, error.code, elapsed, {"raw": raw}
    except Exception as error:
        return i, 0, time.perf_counter() - started, {"error": repr(error)}


def main() -> int:
    latencies = []
    failures = []
    duplicates = 0
    started = time.perf_counter()

    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(send, i) for i in range(TOTAL)]
        for future in concurrent.futures.as_completed(futures):
            i, status, elapsed, data = future.result()
            latencies.append(elapsed)
            if status != 200 or data.get("ok") is not True:
                failures.append((i, status, data))
            if data.get("duplicatePoint") is True:
                duplicates += 1

    wall = time.perf_counter() - started
    expected_unique = len({point_id(i) for i in range(TOTAL)})

    db = sqlite3.connect(DB_PATH)
    point_count = db.execute(
        "SELECT COUNT(*) FROM points WHERE device_id='ci-load-device'"
    ).fetchone()[0]
    stay_count = db.execute(
        "SELECT COUNT(*) FROM country_stays"
    ).fetchone()[0]
    open_count = db.execute(
        "SELECT COUNT(*) FROM country_stays WHERE exited_at IS NULL"
    ).fetchone()[0]
    db.close()
    ordered = sorted(latencies)
    p95 = ordered[max(0, int(len(ordered) * 0.95) - 1)]
    p99 = ordered[max(0, int(len(ordered) * 0.99) - 1)]
    print(
        "LOAD_RESULT "
        f"requests={TOTAL} workers={WORKERS} failures={len(failures)} "
        f"duplicates={duplicates} points={point_count}/{expected_unique} "
        f"stays={stay_count} open={open_count} "
        f"wall={wall:.2f}s avg={statistics.mean(latencies):.4f}s "
        f"p95={p95:.4f}s p99={p99:.4f}s"
    )

    if failures:
        print("FIRST_FAILURE", failures[0], file=sys.stderr)
        return 1
    if point_count != expected_unique:
        print(
            f"Point idempotency mismatch: {point_count} != {expected_unique}",
            file=sys.stderr,
        )
        return 2
    if open_count > 1:
        print("More than one open country stay", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())