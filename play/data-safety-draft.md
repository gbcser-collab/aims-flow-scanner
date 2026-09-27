# Google Play Data safety – AIMS Flow draft

This document is a declaration worksheet for Play Console. Final answers must match the production configuration at submission time.

## Data collected / processed by the app

### Location
- Approximate location: collected
- Precise location: collected
- Purpose: app functionality, transport execution, arrival detection, navigation context, operational safety
- Shared externally for advertising: no
- Sold: no

### Personal info
- Name: collected when the driver provides it
- User IDs / vehicle identifier: collected (driver account, plate, internal identifiers)
- Email / phone: may be processed in registration/support/admin workflows
- Purpose: account management, app functionality, support, operations

### Messages
- In-app driver-dispatch messages: collected
- Purpose: app functionality and business communication
- Sold / advertising use: no

### Photos and documents
- CMR and transport-document images: collected when the user captures/uploads them
- OCR/extracted document text: processed where document scanning is used
- Purpose: transport documentation and contract performance

### App activity / diagnostics
- Operational events, sync state, job status and technical error data: processed
- Purpose: app functionality, security, fraud prevention, diagnostics

### Device or other identifiers
- Push token / device identifier / app version: processed
- Purpose: notifications, account/device association, security and diagnostics

## Security / handling
- Data in transit uses HTTPS.
- Authentication is required for operational functions.
- Production Android builds use a persistent release signing identity.
- Offline queues are used for selected driver actions and are retried after connectivity returns.
- Data is not sold and is not used for targeted advertising.

## Deletion / retention
Requests can be sent to office@logistic-aims.hu. Operational records may be retained where required for contract performance, accounting, legal claims, security or transport-documentation obligations.

Privacy policy:
https://logistic-aims.hu/legal/aims-flow-privacy.html
