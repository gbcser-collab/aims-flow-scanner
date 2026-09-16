# AIMS Flow — CMR + device-control backend

Portable PHP backend for `https://logistic-aims.hu/api`. It uses a lock-protected private JSON data store, so it does not require MySQL/SQLite.

## Server configuration

Required/recommended environment variables:

- `AIMS_ADMIN_PASSWORD_HASH` — required for web admin login. Generate with PHP `password_hash()`.
- `AIMS_MAIL_TO` — defaults to `office@logistic-aims.hu`.
- `AIMS_MAIL_FROM` — defaults to `office@logistic-aims.hu`.
- `AIMS_STORAGE_DIR` — strongly recommended; point it outside `public_html`/the public web root.
- `AIMS_ADMIN_TOKEN` — optional server-to-server admin bearer token. Never put this in browser JavaScript or the APK.
- `AIMS_DEVICE_TOKEN` — temporary legacy migration only; new builds use per-installation credentials and do not need a shared APK secret.
- `AIMS_MAIL_MODE=log` — TEST ONLY. Writes `.eml` files to the private outbox instead of sending real mail.

Example admin password hash:

```bash
php -r "echo password_hash('CHANGE-ME', PASSWORD_DEFAULT), PHP_EOL;"
```

## Device registration / remote revoke

Every app installation creates a random device ID plus a random device secret in app-private storage. The server stores only the SHA-256 hash of the secret.

1. First launch: `POST /api/device/enroll` → device state `pending`.
2. Admin dashboard: approve the device → state `approved`.
3. Only approved devices may upload/read CMR status.
4. Admin can revoke the device → state `revoked`.
5. At the next server check the app locks itself and shows that access has been revoked.

A normal Android app cannot guarantee self-uninstall. Forced remote uninstall requires Android Enterprise / MDM / Device Owner management.

## API routes

Device:
- `POST /api/device/enroll`
- `GET /api/device/status`
- `POST /api/cmr/sync`
- `GET /api/cmr/status?serverDocumentId=...&localId=...`

Admin:
- `POST /api/admin/login`
- `POST /api/admin/logout`
- `GET /api/admin/devices`
- `POST /api/admin/devices/{id}/approve`
- `POST /api/admin/devices/{id}/revoke`
- `GET /api/admin/cmr`
- `POST /api/admin/cmr/{id}/approve`
- `POST /api/admin/cmr/{id}/retry-email`

Health:
- `GET /api/health`

## CMR lifecycle

1. Scanner saves the CMR only in the application's private storage — not Gallery/Downloads.
2. When the device is approved and network is available, the app uploads through HTTPS.
3. Backend keeps a server/archive copy and sends the JPG + CMR data to `office@logistic-aims.hu`.
4. The admin dashboard shows the document and the admin explicitly approves it.
5. Approval returns `approvedAt` and `deleteAfter = approvedAt + 15 days`.
6. The Android app deletes its local image only after both approval and the 15-day deadline.
7. If e-mail failed or admin has not approved, the app must not delete the local CMR.

The server/archive copy is independent from the 15-day device-retention rule.

## Security notes

- Keep `AIMS_STORAGE_DIR` outside the public web root when hosting allows it.
- The included `storage/.htaccess` blocks direct access when storage must sit under Apache web root.
- Admin auth uses a HttpOnly, SameSite=Strict session cookie over HTTPS.
- No SMTP/admin password is embedded in the APK.
- The GitHub repository contains no production secret; configure secrets on the server only.
