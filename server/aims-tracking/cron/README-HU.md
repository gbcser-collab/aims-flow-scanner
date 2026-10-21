# AIMS FLOW havi ország- és jelenléti riport

A `monthly_driver_reports.php` az előző naptári hónapról készít riportot, és elküldi az `office@logistic-aims.hu` címre.

## Javasolt cPanel cron

A script fusson minden nap 06:05-kor. Normál esetben csak a hónap 1. napján küld. Ha a tárhely `mail()` hívása sikertelen, a hónap 2. és 3. napján automatikusan újrapróbálja.

```cron
5 6 * * * /usr/local/bin/php /home/CPANEL_USER/public_html/api/aims-tracking/cron/monthly_driver_reports.php >> /home/CPANEL_USER/aims-flow-monthly-report.log 2>&1
```

A pontos PHP- és home-útvonalat a tárhely szerint kell megadni.

## Kézi próba

```bash
php monthly_driver_reports.php --month=2026-09 --dry-run
```

Kényszerített újraküldés:

```bash
php monthly_driver_reports.php --month=2026-09 --force
```

## Beállítások az `aims-flow-config.php` fájlban

```php
return [
    'AIMS_MONTHLY_REPORT_EMAIL' => 'office@logistic-aims.hu',
    'AIMS_FLOW_FROM_EMAIL' => 'Start@logistic-aims.hu',
    'AIMS_DAILY_CONTRACT_HOURS' => '8',
];
```

Opcionális havi norma felülírás:

```php
'AIMS_MONTHLY_NORM_HOURS_2026_09' => '176',
```

Opcionális sofőrönkénti norma:

```php
'AIMS_DRIVER_MONTHLY_NORM_JSON' => json_encode([
    '123456' => ['default' => 168, '2026-09' => 176],
]),
```

Opcionális munkanap-áthelyezés:

```php
'AIMS_WORKDAY_OVERRIDES_JSON' => json_encode([
    '2027' => [
        'rest' => ['2027-12-24'],
        'work' => ['2027-12-11'],
    ],
]),
```

## Létrejövő fájlok

A riportok az `api/aims-tracking/data/monthly-reports/YYYY-MM/` könyvtárba kerülnek:

- összevont országidő-riport;
- rendszámonként külön országidő-riport;
- napi jelenléti ív;
- sofőrönkénti havi jelenléti összesítő.

Az e-mailhez az összevont országidő, a jelenléti ív és a havi jelenléti összesítő kerül csatolásra.

## Fontos

A jelenléti riport az AIMS FLOW-ban rögzített munkanap-adatokból készül. A tachográf, szabadság, betegállomány, rendelkezésre állási idő, szünetek, kollektív szerződés és tényleges munkaidőkeret végleges ellenőrzése továbbra is az iroda feladata.
