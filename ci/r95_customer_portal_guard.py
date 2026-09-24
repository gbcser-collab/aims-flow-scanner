from pathlib import Path

root = Path(__file__).resolve().parents[1]
bootstrap = (root / "server/aims-tracking/bootstrap.php").read_text(encoding="utf-8")
share = (root / "server/aims-tracking/customer_share.php").read_text(encoding="utf-8")
tracking = (root / "server/aims-tracking/customer_tracking.php").read_text(encoding="utf-8")
portal = (root / "server/aims-tracking/customer_portal.php").read_text(encoding="utf-8")

checks = {
    "hashed_token_column": "customer_tracking_token_hash" in bootstrap,
    "expiry_column": "customer_tracking_expires_at" in bootstrap,
    "share_admin_auth": "aims_admin_user_id($pdo)" in share,
    "cryptographic_token": "random_bytes(32)" in share,
    "raw_token_not_stored": "customer_tracking_token_hash = :hash" in share and "hash('sha256', $token)" in share,
    "revoke_supported": "$action === 'revoke'" in share,
    "public_lookup_by_hash": "j.customer_tracking_token_hash = :hash" in tracking,
    "expired_link_blocked": "link_expired" in tracking,
    "no_store": "Cache-Control: no-store" in tracking and "Cache-Control: no-store" in portal,
    "no_referrer": "Referrer-Policy: no-referrer" in tracking and "Referrer-Policy: no-referrer" in portal,
    "csp_present": "Content-Security-Policy:" in portal,
    "token_removed_from_url": "history.replaceState" in portal and "sessionStorage" in portal,
    "gps_output": "'gps' => $gps" in tracking,
    "eta_output": "'eta' => $eta" in tracking,
    "timeline_output": "'timeline' => $timeline" in tracking,
    "documents_output": "'document' => [" in tracking,
    "customer_poll": "setInterval(refresh,20000)" in portal,
    "no_driver_phone_public": "driver_phone" not in tracking,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("R95_CUSTOMER_PORTAL_GUARD_FAIL: " + ", ".join(failed))

print("R95_CUSTOMER_PORTAL_GUARD_PASS")
print("checks=" + ",".join(checks))
