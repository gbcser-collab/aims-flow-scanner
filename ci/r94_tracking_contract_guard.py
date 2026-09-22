from pathlib import Path

tracking=Path("lib/services/vehicle_tracking_service.dart").read_text(encoding="utf-8")
backend=Path("server/aims-tracking/ingest.php").read_text(encoding="utf-8")

checks={
    "stable point identity": "'pointId': RoamingResilience.pointId(" in tracking,
    "server idempotency": "INSERT OR IGNORE INTO points" in backend and "'duplicatePoint'" in backend,
    "client validates json": "jsonDecode(response.body)" in tracking,
    "client validates ok": "body == null || body['ok'] != true" in tracking,
    "client requires linked vehicle": "body['registeredVehicle'] != true" in tracking,
    "client retains malformed success": "A GPS-pont helyben marad" in tracking,
    "invalid local json quarantined": "_quarantineLine(line, 'invalid_json')" in tracking,
}
bad=[name for name,ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_TRACKING_CONTRACT_FAIL: "+", ".join(bad))
print("R94_TRACKING_CONTRACT_GUARD_PASS")
