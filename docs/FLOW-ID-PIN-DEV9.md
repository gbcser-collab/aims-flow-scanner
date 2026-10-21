# DEV9 FLOW ID + PIN — implementation and activation contract

Base: `86a7f73d0aa533d62cc8759c0d956d02fd281725`. This branch is an integration candidate, not a production activation.

## Implemented

The existing R105 driver shell, navigation, job, workday and Safety Check screens are retained. Driver login accepts six ASCII digits for FLOW ID and five for PIN, preserving leading zeroes. Admin password + TOTP validation and successful response generation remain unchanged in `api/aims-flow-login.php`. Its old driver branch returns 426; failed ADMIN attempts still increment the existing limiter and return 401.

`driver_auth.php` provides POST actions `login`, `refresh`, `session`, `logout`. The login request is `{action:"login",flowId:"004271",pin:"03816",deviceId:"<32–64 lowercase hex>"}`. Format errors are 422. Invalid credentials are 401. Rate limit is 429 with Retry-After: 900. Infrastructure errors are 503. No redirects, logging of credentials, or local fallback to old driver codes.

A successful response includes tokenType=Bearer, independent 256-bit access/refresh tokens, accessExpiresAt, refreshExpiresAt, sessionId, principal(subjectId,tenantId,flowId,role,displayName,language), assignment(assignmentId,vehicleId,plate), and permissions. Timestamps are UTC ISO 8601 strings. Tokens expire after 15 minutes / 30 days absolute respectively. Server database stores only SHA-256 token digests. Each refresh rotates both tokens transactionally; replay revokes the session family. Lost refresh responses require another PIN login; there is no unsafe replay grace window.

Flutter stores the refresh token and allowlisted identity metadata using flutter_secure_storage 11.2.0 (Android AES-GCM with RSA OAEP / KeyStore; iOS device-only Keychain). The access token is memory-only. PIN is transient only and never written to storage, offline queues or logs. Controllers are cleared after submission, disposal and mode changes. Application memory cannot promise cryptographic zeroization of immutable Dart strings.

All `AIMS_TRACKING_TOKEN` driver guards now resolve a personal session through `flow_require_driver_request`. The fleet-wide token is rejected even if it remains configured on the server. Every call revalidates CONTROL status and credential version, verifies the tenant-to-vehicle binding, endpoint permission, supplied plate and resource ownership. GPS vehicle resolution uses the authorized vehicle, never auto-binds a client-provided identity. Multipart Safety uploads use the same guard. Driver pushes require a live CONTROL-authorized session. The separate admin-token path is preserved.

## CONTROL backend must implement this contract

`AIMS_CONTROL_FLOW_URL` is an HTTPS base URL whose `/verify` and `/authorize` methods accept server-to-server POST JSON. `Authorization: Bearer <AIMS_CONTROL_FLOW_SERVICE_TOKEN>` authenticates FLOW, not a mobile app. The service secret must be at least 32 characters, provisioned outside webroot. TLS verification is always on, redirects off, connect timeout 3 seconds, total timeout 8 seconds. Optional `AIMS_CONTROL_CA_FILE` supplies an explicit trusted private CA.

`POST /verify`: `{flowId,pin}`. CONTROL verifies the PIN with a memory-hard password hash and private pepper, implements its own distributed attempt limit, and returns the authoritative active assignment. A successful HTTP 200 response:

```json
{"ok":true,"identity":{"subjectId":"immutable-user-id","tenantId":"tenant-id","flowId":"004271","assignmentId":"assignment-id","vehicleId":"control-vehicle-id","credentialVersion":"1","active":true,"flowEnabled":true,"role":"driver","displayName":"Driver name","language":"hu","permissions":["flow.jobs.read","flow.jobs.write","flow.workday.write","flow.events.write","flow.vehicle.read","flow.push","flow.documents.write","flow.messages","flow.rest","flow.tracking.write"]}}
```

`POST /authorize`: `{subjectId,tenantId,assignmentId,credentialVersion}`. Recompute current user, company, entitlement and assignment state; return the same identity schema. Never blindly echo the input. Disablement, PIN reset/version change or assignment changes invalidate the existing FLOW session. Return 401/403 for rejection, 429 for throttling, 503 for outage. The FLOW adapter fails closed on malformed or unavailable responses; no cached authorization grace period is implemented.

CONTROL alone creates, changes and resets PINs. FLOW does not store PIN hashes. The six-digit FLOW ID namespace must be globally unique; immutable subjectId carries the real identity. No immediate reassignment of a retired ID. CONTROL must decide the initial PIN delivery and identity verification process for reset requests.

## Local tenant mapping

`flow_vehicle_bindings(vehicle_id,tenant_id,control_vehicle_id,portal_company_id)` maps an existing FLOW vehicle to CONTROL ownership. This is not inferred from admin_user_id or from a matching license plate. Populate audited mappings before enabling auth. vehicle_id references existing vehicles; the tenant/control_vehicle pair is unique. Portal invoice uploads additionally require the matching portal_company_id. Missing mappings deny access.

`flow_sessions`, `flow_used_refresh`, `flow_auth_limits`, `flow_resource_owners`, `flow_push_sessions` are additive tables. Existing operations data is not replaced. The per-ID limit is 6 attempts/15 minutes across IPs; per-IP limit 60/15 minutes across IDs. Reservations are atomic and include successful logins; old buckets should be cleaned by a scheduled DB maintenance task after reset_at. Only REMOTE_ADDR is used; the reverse proxy must provide trustworthy client IP handling before production.

## Offline and migration boundaries

Legacy SharedPreferences and file queues have no trustworthy person/tenant owner. They are left intact and not automatically uploaded or assigned to the next driver. New work is scoped by tenant + immutable user + assignment + plate. Existing server idempotency keys without ownership are rejected with legacy_owner_required, requiring audited migration. No data is silently deleted.

An already open authorized driver session can retain offline work. Cold-start restoration requires online refresh and local device unlock when available. Offline cold-start authorization is intentionally not activated; its signed lease/expiry and revocation policy need a separate decision. A five-digit PIN must never become an offline verifier.

Within one app process, changing driver/assignment requires completely closing and reopening the app. This prevents legacy singleton callbacks attaching old pending data to a newly selected account. Same-driver reauthentication is supported. This restriction must remain until all background workers support cancellation and owner-captured completion.

Logout invalidates local state and calls server revocation. Offline logout cannot immediately revoke a remote token; CONTROL can revoke it centrally. The next API request or push revalidates status. Token/device IDs are bearer metadata, not hardware attestation.

## Explicit production blockers

1. Deploy the real CONTROL verify/authorize service with hashing, reset, audit and rate-limiting; supply URL, service credential and `AIMS_FLOW_ID_AUTH_ENABLED=1`.
2. Approve/populate tenant, vehicle and portal company mappings; migrate legacy queues/workdays with verified ownership.
3. Supply the existing external `/api/device/*`, `/api/cmr/*`, `/api/tracking/*` backend source and implement its personal-token bridge. That backend is absent from DEV9. Its legacy device-secret transport is disabled here; CMR files remain local and CMR job completion returns scanner_auth_bridge_required (503). Smart-document uploads use the personal-token route independently. This branch must not be deployed for full operational use until CMR upload and document-gate integration pass.
4. Validate missing `inc/*` site dependencies, portal invoice tenant mapping, and production reverse-proxy/TLS configuration. The admin TOTP implementation is outside the repository; this branch preserves its caller but cannot prove its actual live behavior.
5. Decide offline relaunch, device limits, background authorization outage tolerance, PIN provisioning/reset, session retention/cleanup, and lost-phone handling.
6. Phone smoke test on a separate NEXT install: login, ELFOGADOM timestamp, start/end km, GPS, Safety multipart, HOLD, chat, scanner, restored workday, push and admin TOTP. No production merge/deploy before these gates.

## Regression commands

```sh
AIMS_TRACKING_DATA_DIR=$(mktemp -d) php tests/flow_auth_test.php
python3 tests/flow_auth_http_test.py
flutter analyze
flutter test
python3 ci/r105_white_text_guard.py
python3 ci/r102_driver_first_guard.py
python3 ci/r100_message_signal_guard.py
```

The HTTP suite starts an isolated PHP backend and a localhost TLS CONTROL fixture with a temporary trusted CA, seeded users and vehicles, and no live service credentials. It exercises actual login, wrong PIN, leading zeroes, tenant isolation, old-key rejection, multipart Safety, stable workday, HOLD, refresh rotation/replay/concurrency, suspension and logout.

## Validation result — 2026-10-21

Local Flutter 3.47.7 / Dart 3.13.5: `flutter analyze --no-pub` reports no issues; the complete Flutter suite passes all 58 tests. This includes authenticated R105 layout/navigation rendering, quick signal/message behavior, narrow-phone overflow, numeric login, separate admin 2FA visibility, rejection of legacy local-profile login, token storage, concurrent refresh and logout races. Rendering tests inject identity only in test fixtures; production has no test-login bypass.

PHP 8.3: syntax checks pass for all API/tracking/test files, authentication unit tests pass, and the real HTTP + TLS CONTROL-fixture suite passes, including concurrent refresh. R100/R102/R105 guards pass. The existing admin validation prefix is byte-for-byte unchanged. `git diff --check` is clean. Package versions are captured in pubspec.lock.

No Android APK/device test, live CONTROL verification, live admin TOTP test, production deployment or merge has been performed. GitHub workflows provide the next independent regression and NEXT APK build gates. Do not treat fixture success as proof of the missing production integrations.
