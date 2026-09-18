from __future__ import annotations

import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class JobActivationError(RuntimeError):
    pass


def activate_tracking_job(*, plate: str, driver_job: dict) -> dict:
    url = os.getenv(
        "AIMS_TRACKING_JOB_ASSIGN_URL",
        "http://127.0.0.1/api/aims-tracking/job_assign.php",
    ).strip()
    token = os.getenv("AIMS_TRACKING_ADMIN_TOKEN", "").strip()
    if not url or not token:
        raise JobActivationError("A tracking job activation nincs konfigurálva.")

    payload = json.dumps(
        {"plate": plate.strip(), "driverJob": driver_job},
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "AIMS-Flow-Document-Intelligence/1.3",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            body = response.read().decode("utf-8", "replace")
            parsed = json.loads(body) if body.strip() else {}
            if not isinstance(parsed, dict):
                raise JobActivationError("Érvénytelen tracking válasz.")
            return parsed
    except HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(body)
            code = parsed.get("error", f"http_{exc.code}") if isinstance(parsed, dict) else f"http_{exc.code}"
        except Exception:
            code = f"http_{exc.code}"
        raise JobActivationError(f"Tracking aktiválási hiba: {code}") from exc
    except (URLError, TimeoutError) as exc:
        raise JobActivationError("A tracking szerver nem érhető el.") from exc
