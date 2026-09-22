from pathlib import Path

bootstrap=Path("server/aims-tracking/bootstrap.php").read_text(encoding="utf-8")
assign=Path("server/aims-tracking/job_assign.php").read_text(encoding="utf-8")
ingest=Path("server/aims-tracking/ingest.php").read_text(encoding="utf-8")
jobs=Path("server/aims-tracking/driver_jobs.php").read_text(encoding="utf-8")

checks={
    "new schema nullable latitude": "latitude REAL,\n        longitude REAL," in bootstrap,
    "existing schema migration": "CREATE TABLE job_stops_r94" in bootstrap and "coordinateNotNull" in bootstrap,
    "assignment no hard geocode error": "stop_geocode_failed" not in assign,
    "assignment exposes warning": "geocodeWarnings" in assign,
    "geofence skips no coords": ingest.count("if ($stop['latitude'] === null || $stop['longitude'] === null) continue;") >= 3,
    "feed preserves null coords": "'latitude'=>$row['latitude'] === null ? null" in jobs,
}
bad=[name for name,ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_GEOCODE_FALLBACK_FAIL: "+", ".join(bad))
print("R94_GEOCODE_FALLBACK_GUARD_PASS")
