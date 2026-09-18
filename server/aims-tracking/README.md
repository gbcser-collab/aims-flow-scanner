# AIMS Flow Smart Operations v1.3

This layer combines the document-intelligence freight workflow with live vehicle tracking.

## Driver / vehicle behavior

- The driver app stores the current vehicle plate.
- The plate must be registered by an admin before server-side tracking events are accepted for that vehicle.
- Tracking uses a foreground Android location service and an offline queue.
- A periodic heartbeat supplements movement-triggered positions so the server can distinguish a stationary vehicle from a silent client.
- Small, credible movement resets the stationary cycle. The movement threshold adapts to GPS accuracy:
  - good GPS: about 5 metres,
  - weaker GPS: progressively higher threshold, capped at 15 metres,
  - a credible speed signal also resets the cycle.

## Stationary notifications

One stop cycle can produce at most three notifications to the admin who owns the plate:

- 15 minutes stationary,
- 30 minutes stationary,
- 60 minutes stationary.

Any credible movement starts a new cycle and clears all pending thresholds. Notifications have dedupe keys, so a threshold is not repeated inside the same stop cycle.

If the vehicle is currently inside an active pickup/delivery geofence, the notification also identifies that operational context.

## Automatic pickup / delivery arrival

Approved freight jobs from Document Intelligence can be activated through:

- Document Intelligence: `POST /v1/job/activate`
- Tracking backend: `POST /job_assign.php`

The normalized pickup and delivery addresses are geocoded once and cached. Coordinates already supplied by an upstream system are preferred.

Default arrival behavior:

- 180 m configured geofence, expanded only when reported GPS accuracy requires it,
- vehicle must remain inside for at least 45 seconds,
- fast pass-throughs are not marked as arrival,
- one arrival notification per stop,
- notification goes only to the admin assigned to the registered plate.

## Fuel receipt workflow

Driver app:

1. opens **Tankolási bizonylat küldése**,
2. photographs the receipt,
3. document cleanup + OCR runs,
4. station/date/litres/amount/currency/unit price/receipt number are prefilled when recognized,
5. driver can correct fields,
6. sends the image and metadata to the management backend.

Management side:

- receives a `fuel_receipt` notification,
- lists receipts by the admin's own vehicles,
- receipt images require authenticated admin access.

Uploaded image bytes are validated as JPEG/PNG/WebP and are stored outside the public admin UI path.

## Admin ownership

`admin_users` and `vehicles.admin_user_id` provide the routing boundary. An admin token can only read:

- their registered vehicles,
- their tracking feed,
- their notifications,
- their fuel receipts.

A plate already owned by another admin cannot be silently reassigned.

## Admin UI

- `admin/control.html`: notifications, vehicle registration, fuel receipts.
- `admin/tracking.html`: live vehicle map and trail.

The control page can use the browser Notification API while the management page is loaded. A true OS push to a completely closed native admin app still requires a configured push provider/device token (for example FCM/APNs); the server-side notification records and per-admin routing are already the source events for that delivery layer.

## Required production configuration

Server:

- `AIMS_TRACKING_TOKEN`: driver/app write token
- `AIMS_ADMIN_TRACKING_TOKEN`: master/default admin token
- `AIMS_DEFAULT_ADMIN_NAME` (optional)
- `AIMS_GEOCODER_URL` (optional; defaults to Nominatim)

Document Intelligence:

- `AIMS_TRACKING_JOB_ASSIGN_URL`
- `AIMS_TRACKING_ADMIN_TOKEN`

Android build:

- `AIMS_TRACKING_TOKEN`
- optionally `AIMS_TRACKING_ENDPOINT`
- optionally `AIMS_FUEL_RECEIPT_ENDPOINT`

Do not commit production tokens to GitHub.

## Tests

`tracking_rules_test.php` verifies threshold/movement/geofence rules.

`integration_test.sh` exercises the real HTTP endpoints end-to-end:

- plate registration,
- admin ownership,
- job assignment,
- 15/30/60 stationary notifications,
- movement reset,
- automatic pickup arrival,
- fuel receipt upload and admin visibility.
