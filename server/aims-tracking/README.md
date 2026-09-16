# AIMS Flow vehicle tracking backend

This directory is intentionally secret-free. Never commit production tokens to GitHub.

## What it does

- `ingest.php`: receives authenticated vehicle position updates from AIMS Flow.
- `feed.php`: returns latest positions plus a selected vehicle trail for the admin map.
- `admin/tracking.html`: live admin dashboard using Leaflet + OpenStreetMap; no paid map API key is required.
- `data/tracking.sqlite`: created automatically at runtime. Keep the data directory private and writable by PHP.

## Required server configuration

Set these environment variables outside the web root:

- `AIMS_TRACKING_TOKEN`: write token used by the Android app.
- `AIMS_ADMIN_TRACKING_TOKEN`: separate read/admin token used by the map dashboard.

The Android production build must receive the write token using Dart defines, for example:

`--dart-define=AIMS_TRACKING_ENDPOINT=https://logistic-aims.hu/api/aims-tracking/ingest.php`

`--dart-define=AIMS_TRACKING_TOKEN=<secret>`

Do not use the admin token in the app.

## Android behavior

Tracking updates target roughly every 15 seconds / 20 metres while active. If the phone has no internet, positions are queued inside the app and are retried when a later location update occurs with connectivity.

Android displays a persistent foreground notification while continuous background location tracking is active. The first activation requires location permission. Background location must be permitted by the device/OS for reliable always-on tracking.

## Privacy / employment use

Continuous employee/driver location is personal data. Deploy it with an appropriate lawful basis, written employee information/privacy notice, retention policy, access control, and a clear work-purpose scope. The app intentionally does not implement hidden tracking: Android shows the tracking notification and the AIMS Flow UI exposes tracking status.

## Before production

- put the dashboard behind the existing Logistic-A.I.M.S. admin login (and preferably 2FA);
- force HTTPS;
- protect the SQLite data path from direct web access;
- use long random production tokens and rotate them if exposed;
- change retention from the current 60-day raw-point default if your documented policy requires another period;
- test Samsung battery optimisation/background restrictions on the actual driver devices.
