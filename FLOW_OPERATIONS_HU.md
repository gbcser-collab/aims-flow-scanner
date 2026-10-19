# AIMS FLOW operatív bekötés

## Hol fut?

A FLOW sofőralkalmazás napi operatív adatai ugyanabba a tracking backendbe kerülnek, mint a jelenlegi GPS, fuvar, üzenet és dokumentumadatok.

Éles célútvonalak:

- Sofőr operatív API: `/api/aims-tracking/driver_ops_v2.php`
- Sofőr járműhiba/jelzés: `/api/aims-tracking/driver_event.php`
- Irodai nézet: `/admin/aims-flow.php#flow-operations`
- Safety Check fotó megnyitása: `/admin/aims-flow-safety-photo.php?id=<ID>`
- Irodai műveletek: `/admin/aims-flow-operations.php`

A repositoryban a tracking backend forrása a `server/aims-tracking/` mappában van. Szervertelepítéskor ennek tartalma a webroot `api/aims-tracking/` mappájába kerül.

## Mit lát az iroda?

Az **AIMS Flow Live Control** oldalon:

1. aktív és lezárt sofőr-munkanapok;
2. kezdő/záró kilométer és napi megtett km;
3. Safety Check eredmények;
4. olaj-, hűtőfolyadék-, kerék- és kilométeróra-fotók;
5. Service Guard tételek és esedékesség;
6. nyitott járműhibák;
7. kritikus jármű HOLD állapot;
8. hibajegy lezárás és HOLD feloldás.

Ez **FLOW Office**, nem AIMS CONTROL. Az AIMS CONTROL később a felhasználó-, licence-, jogosultság- és policy-kezelést végzi.

## Adatfolyam

```text
AIMS FLOW sofőr APK
        |
        +-- GPS / fuvar / üzenet / CMR --> meglévő aims-tracking API
        |
        +-- munkanap / km / Safety / Service
                    |
                    v
       driver_ops_v2.php / driver_event.php
                    |
                    v
         tracking.sqlite FLOW adatbázis
                    |
                    v
       admin/aims-flow.php#flow-operations
```

## Új táblák

- `driver_workdays`
- `vehicle_odometer_log`
- `vehicle_safety_checks`
- `vehicle_safety_photos`
- `vehicle_service_items`
- `vehicle_operational_state`
- `vehicle_issues`

## HOLD logika

- kritikus sofőr-járműhiba automatikusan HOLD-ra teszi a járművet;
- HOLD mellett a sofőrapp új fuvar elfogadását/indítását blokkolja;
- az iroda a FLOW Office felületen oldhatja fel;
- nyitott másik kritikus hiba esetén a hibajegy lezárása nem oldja fel automatikusan a HOLD-ot.

## Offline

A munkanap és Safety Check helyben megmarad, ha nincs kapcsolat. A kész munkanap záró szinkronja a kezdő snapshotot is elküldi, így egy teljesen offline kezdett és lezárt nap is visszaállítható a szerveren.
