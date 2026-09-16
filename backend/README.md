# AIMS Flow CMR backend

PHP + SQLite MVP for `https://logistic-aims.hu/api`.

## Environment variables

- `AIMS_DEVICE_TOKEN` — device API bearer token (required)
- `AIMS_ADMIN_PASSWORD_HASH` — PHP `password_hash()` output for admin login (required for browser admin)
- `AIMS_ADMIN_TOKEN` — optional server-to-server admin bearer token; never put it in browser JavaScript
- `AIMS_MAIL_TO` — default: `office@logistic-aims.hu`
- `AIMS_MAIL_FROM` — default: `office@logistic-aims.hu`
- `AIMS_STORAGE_DIR` — strongly recommended: a directory outside `public_html`

Example password hash generation on the server:

```bash
php -r "echo password_hash('CHANGE-ME', PASSWORD_DEFAULT), PHP_EOL;"
```

## Routes

Device:
- `POST /api/cmr/sync`
- `GET /api/cmr/status?serverDocumentId=...&localId=...`

Admin:
- `POST /api/admin/login`
- `POST /api/admin/logout`
- `GET /api/admin/cmr`
- `POST /api/admin/cmr/{id}/approve`
- `POST /api/admin/cmr/{id}/retry-email`

Health:
- `GET /api/health`

## Lifecycle

1. App stores the CMR only in app-private storage.
2. App uploads through HTTPS when network is available.
3. Backend stores a server copy and sends the CMR to `office@logistic-aims.hu`.
4. Admin approves the received CMR.
5. Backend returns `approvedAt` and `deleteAfter = approvedAt + 15 days`.
6. App deletes its local copy only after the server approval and the 15-day deadline.

The server/archive copy is independent from the device-retention rule.
