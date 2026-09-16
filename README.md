# AIMS Flow

AIMS Flow is the Android driver-operations application for Logistic-A.I.M.S. It combines freight execution, CMR scanning/OCR, GPS tracking, offline-first persistence and synchronization in one driver-facing workflow.

## Driver workflow

The main navigation is intentionally reduced to three operational areas:

- **FUVAR** — active freight, stage progression, route, checklist, incidents, waiting time, evidence, notes and manual sync.
- **SCANNER** — camera-based CMR capture, image processing, OCR, structured CMR fields and offline document queue.
- **FLOW** — system health, GPS/CMR queue, event log and synchronization status.

The freight lifecycle is represented as a real state machine:

`KIADVA → ELFOGADVA → ÚTON FELRAKÓRA → FELRAKÓN → FELRAKVA → ÚTON LERAKÓRA → LERAKÓN → CMR ELLENŐRZÉS → TELJESÍTVE → ADMIN JÓVÁHAGYVA`

## Offline-first behavior

Driver-operation state is persisted locally as JSON using an atomic temporary-file replacement. CMR and GPS already maintain their own local queues. If the backend is unavailable, the app stays usable and queued data can be retried from the FLOW view.

## Safety gates

- The driver cannot start the pickup leg until the pre-trip checklist is complete.
- Critical incidents are visually separated in the event log.
- Waiting time is measured and persisted across app restarts.
- CMR and GPS queue counts are surfaced on the freight dashboard.
- Device approval/revocation state is visible to the driver.

## Android build

The `flow-production` branch is built by `.github/workflows/flow-android.yml`. CI checks branding, runs static analysis, executes the CMR parser and freight-flow tests, builds the debug APK, performs a non-empty artifact sanity check, calculates SHA-256 and publishes `AIMS-Flow-debug.apk`.
