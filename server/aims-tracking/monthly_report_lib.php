<?php
declare(strict_types=1);
require_once __DIR__.'/rest_history.php';
require_once __DIR__.'/driver_auth_v2.php';

/**
 * Monthly country-presence and driver-attendance reporting for AIMS FLOW.
 *
 * The report is based on confirmed country stays and locally/server-recorded
 * workdays. It is an operational control report, not a replacement for the
 * tachograph, payroll or legal review.
 */

function aims_monthly_country_names(): array {
    return [
        'HU'=>'Magyarország','AT'=>'Ausztria','BE'=>'Belgium','BG'=>'Bulgária',
        'CH'=>'Svájc','CZ'=>'Csehország','DE'=>'Németország','DK'=>'Dánia',
        'EE'=>'Észtország','ES'=>'Spanyolország','FI'=>'Finnország',
        'FR'=>'Franciaország','GB'=>'Egyesült Királyság','GR'=>'Görögország',
        'HR'=>'Horvátország','IE'=>'Írország','IT'=>'Olaszország',
        'LT'=>'Litvánia','LU'=>'Luxemburg','LV'=>'Lettország',
        'NL'=>'Hollandia','NO'=>'Norvégia','PL'=>'Lengyelország',
        'PT'=>'Portugália','RO'=>'Románia','RS'=>'Szerbia','SE'=>'Svédország',
        'SI'=>'Szlovénia','SK'=>'Szlovákia','UA'=>'Ukrajna',
    ];
}

function aims_monthly_duration_parts(int $seconds): array {
    $seconds = max(0, $seconds);
    $days = intdiv($seconds, 86400);
    $remainder = $seconds % 86400;
    $hours = intdiv($remainder, 3600);
    $minutes = intdiv($remainder % 3600, 60);
    return [
        'seconds'=>$seconds,
        'days'=>$days,
        'hours'=>$hours,
        'minutes'=>$minutes,
        'formatted'=>$days.' nap '.$hours.' óra '.$minutes.' perc',
        'hhmm'=>sprintf('%02d:%02d', intdiv($seconds, 3600), intdiv($seconds % 3600, 60)),
    ];
}

function aims_monthly_period(string $month): array {
    if (!preg_match('/^\d{4}-\d{2}$/', $month)) {
        throw new InvalidArgumentException('A hónap formátuma YYYY-MM legyen.');
    }
    $tz = new DateTimeZone('Europe/Budapest');
    $utc = new DateTimeZone('UTC');
    $start = DateTimeImmutable::createFromFormat('!Y-m', $month, $tz);
    if (!$start || $start->format('Y-m') !== $month) {
        throw new InvalidArgumentException('Érvénytelen hónap.');
    }
    $end = $start->modify('+1 month');
    return [
        'month'=>$month,
        'tz'=>$tz,
        'utc'=>$utc,
        'startLocal'=>$start,
        'endLocal'=>$end,
        'startUtc'=>$start->setTimezone($utc),
        'endUtc'=>$end->setTimezone($utc),
    ];
}

function aims_monthly_easter_sunday(int $year, DateTimeZone $tz): DateTimeImmutable {
    // Meeus/Jones/Butcher Gregorian algorithm, independent of PHP extensions.
    $a = $year % 19;
    $b = intdiv($year, 100);
    $c = $year % 100;
    $d = intdiv($b, 4);
    $e = $b % 4;
    $f = intdiv($b + 8, 25);
    $g = intdiv($b - $f + 1, 3);
    $h = (19 * $a + $b - $d - $g + 15) % 30;
    $i = intdiv($c, 4);
    $k = $c % 4;
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7;
    $m = intdiv($a + 11 * $h + 22 * $l, 451);
    $month = intdiv($h + $l - 7 * $m + 114, 31);
    $day = (($h + $l - 7 * $m + 114) % 31) + 1;
    return new DateTimeImmutable(sprintf('%04d-%02d-%02d 00:00:00', $year, $month, $day), $tz);
}

function aims_monthly_workday_overrides(int $year): array {
    $builtIn = [
        2026 => [
            'rest'=>['2026-01-02','2026-08-21','2026-12-24'],
            'work'=>['2026-01-10','2026-08-08','2026-12-12'],
        ],
    ];
    $result = $builtIn[$year] ?? ['rest'=>[], 'work'=>[]];

    $raw = trim((string)(getenv('AIMS_WORKDAY_OVERRIDES_JSON') ?: ''));
    if ($raw !== '') {
        $decoded = json_decode($raw, true);
        $custom = is_array($decoded) ? ($decoded[(string)$year] ?? null) : null;
        if (is_array($custom)) {
            foreach (['rest','work'] as $kind) {
                if (isset($custom[$kind]) && is_array($custom[$kind])) {
                    foreach ($custom[$kind] as $date) {
                        if (is_string($date) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
                            $result[$kind][] = $date;
                        }
                    }
                }
            }
        }
    }

    $result['rest'] = array_values(array_unique($result['rest']));
    $result['work'] = array_values(array_unique($result['work']));
    return $result;
}

function aims_monthly_calendar_norm_hours(string $month, string $flowId = ''): float {
    $driverMapRaw = trim((string)(getenv('AIMS_DRIVER_MONTHLY_NORM_JSON') ?: ''));
    if ($driverMapRaw !== '' && $flowId !== '') {
        $driverMap = json_decode($driverMapRaw, true);
        if (is_array($driverMap) && isset($driverMap[$flowId])) {
            $value = $driverMap[$flowId];
            if (is_array($value)) $value = $value[$month] ?? $value['default'] ?? null;
            if (is_numeric($value) && (float)$value >= 0) return (float)$value;
        }
    }

    $specificKey = 'AIMS_MONTHLY_NORM_HOURS_'.str_replace('-', '_', $month);
    $specific = getenv($specificKey);
    if ($specific !== false && is_numeric($specific) && (float)$specific >= 0) {
        return (float)$specific;
    }
    $generic = getenv('AIMS_MONTHLY_NORM_HOURS');
    if ($generic !== false && is_numeric($generic) && (float)$generic >= 0) {
        return (float)$generic;
    }

    $period = aims_monthly_period($month);
    /** @var DateTimeImmutable $cursor */
    $cursor = $period['startLocal'];
    /** @var DateTimeImmutable $end */
    $end = $period['endLocal'];
    $year = (int)$cursor->format('Y');
    $tz = $period['tz'];
    $easter = aims_monthly_easter_sunday($year, $tz);

    $holidays = [
        sprintf('%04d-01-01', $year), sprintf('%04d-03-15', $year),
        sprintf('%04d-05-01', $year), sprintf('%04d-08-20', $year),
        sprintf('%04d-10-23', $year), sprintf('%04d-11-01', $year),
        sprintf('%04d-12-25', $year), sprintf('%04d-12-26', $year),
        $easter->modify('-2 days')->format('Y-m-d'),
        $easter->modify('+1 day')->format('Y-m-d'),
        $easter->modify('+50 days')->format('Y-m-d'),
    ];
    $overrides = aims_monthly_workday_overrides($year);
    $workdays = 0;

    while ($cursor < $end) {
        $date = $cursor->format('Y-m-d');
        $weekday = (int)$cursor->format('N');
        $isWork = $weekday <= 5 && !in_array($date, $holidays, true);
        if (in_array($date, $overrides['rest'], true)) $isWork = false;
        if (in_array($date, $overrides['work'], true)) $isWork = true;
        if ($isWork) $workdays++;
        $cursor = $cursor->modify('+1 day');
    }

    $daily = getenv('AIMS_DAILY_CONTRACT_HOURS');
    $dailyHours = $daily !== false && is_numeric($daily) && (float)$daily > 0
        ? (float)$daily
        : 8.0;
    return $workdays * $dailyHours;
}

function aims_monthly_country_rows(PDO $pdo, array $period): array {
    $start = $period['startUtc'];
    $end = $period['endUtc'];
    $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
    $rangeEnd = $end < $now ? $end : $now;

    $stmt = $pdo->prepare('SELECT s.*,v.plate,v.label
        FROM country_stays s
        JOIN vehicles v ON v.id=s.vehicle_id
        WHERE julianday(s.entered_at) < julianday(:end) AND julianday(COALESCE(s.exited_at,:end)) > julianday(:start)
        ORDER BY v.plate,s.entered_at,s.id');
    $stmt->execute([
        ':start'=>$start->format(DateTimeInterface::ATOM),
        ':end'=>$end->format(DateTimeInterface::ATOM),
    ]);

    $totals = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        try {
            $entered = new DateTimeImmutable((string)$row['entered_at']);
        } catch (Throwable) {
            continue;
        }
        $exited = null;
        if (trim((string)($row['exited_at'] ?? '')) !== '') {
            try { $exited = new DateTimeImmutable((string)$row['exited_at']); } catch (Throwable) {}
        }
        $segmentStart = $entered > $start ? $entered : $start;
        $segmentEnd = $exited ?? $rangeEnd;
        if ($segmentEnd > $rangeEnd) $segmentEnd = $rangeEnd;
        if ($segmentEnd <= $segmentStart) continue;

        $plate = aims_normalize_plate((string)$row['plate']);
        $country = strtoupper(trim((string)$row['country_code']));
        if ($plate === '' || !preg_match('/^[A-Z]{2}$/', $country)) continue;
        $key = $plate.'|'.$country;
        if (!isset($totals[$key])) {
            $totals[$key] = [
                'vehicleId'=>(int)$row['vehicle_id'],
                'plate'=>$plate,
                'label'=>trim((string)$row['label']) ?: $plate,
                'countryCode'=>$country,
                'seconds'=>0,
            ];
        }
        $totals[$key]['seconds'] += $segmentEnd->getTimestamp() - $segmentStart->getTimestamp();
    }

    $names = aims_monthly_country_names();
    $rows = [];
    foreach ($totals as $row) {
        $duration = aims_monthly_duration_parts((int)$row['seconds']);
        $row['countryName'] = $names[$row['countryCode']] ?? $row['countryCode'];
        $row['duration'] = $duration;
        $rows[] = $row;
    }
    usort($rows, static fn(array $a, array $b): int =>
        [$a['plate'], -$a['seconds'], $a['countryCode']] <=>
        [$b['plate'], -$b['seconds'], $b['countryCode']]
    );
    return $rows;
}

function aims_monthly_workday_source_rows(PDO $pdo, DateTimeImmutable $start, DateTimeImmutable $end): array {
    $stmt = $pdo->prepare('SELECT w.*,v.plate,v.label,
        a.flow_id,a.driver_name,a.email
        FROM driver_workdays w
        JOIN vehicles v ON v.id=w.vehicle_id
        LEFT JOIN driver_accounts a ON a.flow_id=substr(w.workday_key,1,6)
          AND (length(w.workday_key)=6 OR substr(w.workday_key,7,1)="-")
        WHERE julianday(w.started_at) < julianday(:end) AND julianday(COALESCE(w.finished_at,:end)) > julianday(:start)
        ORDER BY w.started_at,w.id');
    $stmt->execute([
        ':start'=>$start->format(DateTimeInterface::ATOM),
        ':end'=>$end->format(DateTimeInterface::ATOM),
    ]);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function aims_monthly_attendance_daily(PDO $pdo, array $period): array {
    $startUtc = $period['startUtc'];
    $endUtc = $period['endUtc'];
    $tz = $period['tz'];
    $now = new DateTimeImmutable('now', $period['utc']);
    $rangeEnd = $endUtc < $now ? $endUtc : $now;
    $coverage = $pdo->query('SELECT started_at FROM report_capture_metadata WHERE name="rest_history"')->fetchColumn();
    $coverageAt = $coverage ? (new DateTimeImmutable((string)$coverage))->getTimestamp() : PHP_INT_MAX;
    $rests = [];
    $stmt = $pdo->prepare('SELECT * FROM driver_rest_periods
        WHERE julianday(started_at) < julianday(:end)
          AND julianday(COALESCE(ended_at,planned_until)) > julianday(:start)');
    $stmt->execute([':start'=>$startUtc->format(DateTimeInterface::ATOM), ':end'=>$rangeEnd->format(DateTimeInterface::ATOM)]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $rest) {
        $rests[(int)$rest['vehicle_id']][] = $rest;
    }
    $groups = [];
    foreach (aims_monthly_workday_source_rows($pdo, $startUtc, $endUtc) as $row) {
        try { $started = new DateTimeImmutable((string)$row['started_at']); } catch (Throwable) { continue; }
        $finished = null;
        if (trim((string)($row['finished_at'] ?? '')) !== '') {
            try { $finished = new DateTimeImmutable((string)$row['finished_at']); } catch (Throwable) {}
        }
        $segmentStart = $started > $startUtc ? $started : $startUtc;
        $segmentEnd = $finished ?? $rangeEnd;
        if ($segmentEnd > $rangeEnd) $segmentEnd = $rangeEnd;
        if ($segmentEnd <= $segmentStart) continue;
        $flowId = trim((string)($row['flow_id'] ?? ''));
        if ($flowId === '' && preg_match('/^(\d{6})(?:-|$)/', (string)$row['workday_key'], $match)) $flowId = $match[1];
        $plate = aims_normalize_plate((string)$row['plate']);
        $driverKey = $flowId !== '' ? $flowId : 'UNKNOWN-'.$plate;
        $cursor = $segmentStart->setTimezone($tz);
        $localEnd = $segmentEnd->setTimezone($tz);
        while ($cursor < $localEnd) {
            $nextMidnight = $cursor->modify('tomorrow')->setTime(0, 0, 0);
            $partEnd = $nextMidnight < $localEnd ? $nextMidnight : $localEnd;
            $date = $cursor->format('Y-m-d');
            $key = $driverKey.'|'.$date.'|'.$plate;
            if (!isset($groups[$key])) {
                $groups[$key] = [
                    'flowId'=>$flowId, 'driverName'=>trim((string)($row['driver_name'] ?? '')) ?: 'Ismeretlen sofőr',
                    'email'=>trim((string)($row['email'] ?? '')), 'plate'=>$plate, 'date'=>$date,
                    'firstStart'=>$cursor, 'lastEnd'=>$partEnd,
                    'workIntervals'=>[], 'restIntervals'=>[], 'incompleteRest'=>false, 'openWorkday'=>false,
                ];
            }
            $g = &$groups[$key];
            $cs = $cursor->getTimestamp(); $ce = $partEnd->getTimestamp();
            $g['workIntervals'][] = [$cs,$ce];
            $g['incompleteRest'] = $g['incompleteRest'] || $cs < $coverageAt || $flowId === '';
            $g['openWorkday'] = $g['openWorkday'] || $finished === null;
            foreach ($rests[(int)$row['vehicle_id']] ?? [] as $rest) {
                try {
                    $rs = (new DateTimeImmutable($rest['started_at']))->getTimestamp();
                    $re = (new DateTimeImmutable($rest['ended_at'] ?? $rest['planned_until']))->getTimestamp();
                } catch (Throwable) { continue; }
                $rs = max($cs,$rs); $re = min($ce,$re);
                if ($re <= $rs) continue;
                if ($flowId !== '' && $rest['flow_id'] === $flowId) {
                    $g['restIntervals'][] = [$rs,$re];
                } elseif ($rest['flow_id'] === '') {
                    $g['incompleteRest'] = true;
                }
            }
            if ($cursor < $g['firstStart']) $g['firstStart'] = $cursor;
            if ($partEnd > $g['lastEnd']) $g['lastEnd'] = $partEnd;
            unset($g);
            $cursor = $partEnd;
        }
    }
    $rows = [];
    foreach ($groups as $row) {
        $row['workIntervals'] = aims_time_union($row['workIntervals']);
        $row['netIntervals'] = aims_time_subtract($row['workIntervals'],$row['restIntervals']);
        $row['grossSeconds'] = aims_time_seconds($row['workIntervals']);
        $row['seconds'] = aims_time_seconds($row['netIntervals']);
        $row['restSeconds'] = $row['grossSeconds']-$row['seconds'];
        $row['duration'] = aims_monthly_duration_parts($row['seconds']);
        $row['grossDuration'] = aims_monthly_duration_parts($row['grossSeconds']);
        $row['restDuration'] = aims_monthly_duration_parts($row['restSeconds']);
        $flags = [];
        if ($row['incompleteRest']) $flags[] = 'PIHENŐADAT NEM TELJES';
        if ($row['openWorkday']) $flags[] = 'NYITOTT MUNKANAP – IDEIGLENES';
        if ($row['seconds'] > 15*3600) $flags[] = 'HOSSZÚ NAP – IRODAI ELLENŐRZÉS';
        elseif ($row['seconds'] > 10*3600) $flags[] = '10 ÓRA FELETT – IRODAI ELLENŐRZÉS';
        $row['dailyStatus'] = $flags ? implode(' | ',$flags) : 'RÖGZÍTETT ADATOK ALAPJÁN';
        $rows[] = $row;
    }
    usort($rows, static fn(array $a,array $b): int =>
        [$a['flowId'],$a['driverName'],$a['date'],$a['plate']] <=> [$b['flowId'],$b['driverName'],$b['date'],$b['plate']]);
    return $rows;
}

function aims_monthly_reference_average(PDO $pdo, string $flowId, array $period): ?float {
    if (!preg_match('/^\d{6}$/',$flowId)) return null;
    $reference = $period;
    $reference['startUtc'] = $period['startLocal']->modify('-3 months')->setTimezone($period['utc']);
    $now = new DateTimeImmutable('now',$period['utc']);
    if ($reference['endUtc'] > $now) $reference['endUtc'] = $now;
    $weeks = ($reference['endUtc']->getTimestamp()-$reference['startUtc']->getTimestamp())/604800.0;
    if ($weeks <= 0) return null;
    $intervals = [];
    foreach (aims_monthly_attendance_daily($pdo,$reference) as $row) {
        if ($row['flowId'] !== $flowId) continue;
        // Do not present an average as verified if historical rests are missing.
        if ($row['incompleteRest'] || $row['openWorkday']) return null;
        $intervals = array_merge($intervals,$row['netIntervals']);
    }
    return aims_time_seconds($intervals)/3600.0/$weeks;
}

function aims_monthly_attendance_summary(PDO $pdo, array $period, array $dailyRows): array {
    $summary = [];
    foreach ($dailyRows as $row) {
        $key = $row['flowId'] !== '' ? $row['flowId'] : 'UNKNOWN-'.$row['plate'];
        if (!isset($summary[$key])) {
            $summary[$key] = [
                'flowId'=>$row['flowId'],'driverName'=>$row['driverName'],'email'=>$row['email'],
                'plates'=>[],'dates'=>[],'workIntervals'=>[],'netIntervals'=>[],
                'incompleteRest'=>false,'openWorkday'=>false,
            ];
        }
        $g = &$summary[$key];
        $g['plates'][$row['plate']] = true;
        $g['dates'][$row['date']] = true;
        $g['workIntervals'] = array_merge($g['workIntervals'],$row['workIntervals']);
        $g['netIntervals'] = array_merge($g['netIntervals'],$row['netIntervals']);
        $g['incompleteRest'] = $g['incompleteRest'] || $row['incompleteRest'];
        $g['openWorkday'] = $g['openWorkday'] || $row['openWorkday'];
        unset($g);
    }
    // Include complete ISO weeks crossing either edge of the selected month.
    $weekPeriod = $period;
    $weekPeriod['startUtc'] = $period['startLocal']->modify('monday this week')->setTimezone($period['utc']);
    $weekPeriod['endUtc'] = $period['endLocal']->modify('-1 day')->modify('monday next week')->setTimezone($period['utc']);
    $weekly = [];
    foreach (aims_monthly_attendance_daily($pdo,$weekPeriod) as $day) {
        $key = $day['flowId'] !== '' ? $day['flowId'] : 'UNKNOWN-'.$day['plate'];
        $week = (new DateTimeImmutable($day['date'],$period['tz']))->format('o-W');
        $weekly[$key][$week] = array_merge($weekly[$key][$week] ?? [],$day['netIntervals']);
    }
    $rows = [];
    foreach ($summary as $driverKey=>$row) {
        $row['days'] = count($row['dates']);
        $row['grossSeconds'] = aims_time_seconds($row['workIntervals']);
        $row['seconds'] = aims_time_seconds($row['netIntervals']);
        $row['restSeconds'] = $row['grossSeconds']-$row['seconds'];
        $normHours = !empty($period['customRange']) ? null : aims_monthly_calendar_norm_hours($period['month'],$row['flowId']);
        $actualHours = $row['seconds']/3600.0;
        $maxWeeklyHours = 0.0;
        foreach ($weekly[$driverKey] ?? [] as $intervals) $maxWeeklyHours = max($maxWeeklyHours,aims_time_seconds($intervals)/3600.0);
        $average4m = !empty($period['customRange']) ? null : aims_monthly_reference_average($pdo,$row['flowId'],$period);
        $flags = [];
        if ($row['incompleteRest']) $flags[] = 'PIHENŐADAT NEM TELJES';
        if ($row['openWorkday']) $flags[] = 'NYITOTT MUNKANAP – IDEIGLENES';
        if ($normHours !== null && $actualHours > $normHours+0.01) $flags[] = 'HAVI NORMA FELETT – IRODAI ELLENŐRZÉS';
        if ($maxWeeklyHours > 60.0+0.01) $flags[] = '60 ÓRA/HÉT FELETT – IRODAI ELLENŐRZÉS';
        if ($average4m !== null && $average4m > 48.0+0.01) $flags[] = '4 HÓNAPOS ÁTLAG 48 ÓRA/HÉT FELETT – IRODAI ELLENŐRZÉS';
        $row['plates'] = implode(', ',array_keys($row['plates']));
        $row['duration'] = aims_monthly_duration_parts($row['seconds']);
        $row['grossDuration'] = aims_monthly_duration_parts($row['grossSeconds']);
        $row['restDuration'] = aims_monthly_duration_parts($row['restSeconds']);
        $row['normHours'] = $normHours;
        $row['differenceHours'] = $normHours === null ? null : $actualHours-$normHours;
        $row['maxWeeklyHours'] = $maxWeeklyHours;
        $row['average4MonthWeeklyHours'] = $average4m;
        $row['status'] = $flags ? implode(' | ',$flags) : 'RÖGZÍTETT ADATOK ALAPJÁN';
        $rows[] = $row;
    }
    usort($rows, static fn(array $a,array $b): int => [$a['driverName'],$a['flowId']] <=> [$b['driverName'],$b['flowId']]);
    return $rows;
}

function aims_monthly_build_report(PDO $pdo, string $month): array {
    aims_driver_auth_schema($pdo);
    $period = aims_monthly_period($month);
    $country = aims_monthly_country_rows($pdo, $period);
    $daily = aims_monthly_attendance_daily($pdo, $period);
    $summary = aims_monthly_attendance_summary($pdo, $period, $daily);
    return [
        'month'=>$month,
        'period'=>$period,
        'generatedAt'=>new DateTimeImmutable('now', new DateTimeZone('UTC')),
        'countryRows'=>$country,
        'attendanceRows'=>$daily,
        'attendanceSummary'=>$summary,
    ];
}

function aims_monthly_build_range_report(PDO $pdo,string $from,string $to,string $plate='',string $driver=''): array {
    require_once __DIR__.'/mileage_report_lib.php';
    aims_driver_auth_schema($pdo);$period=aims_report_period($from,$to);
    $country=aims_monthly_country_rows($pdo,$period);
    if($plate!=='')$country=array_values(array_filter($country,static fn($r)=>$r['plate']===$plate));
    $daily=array_values(array_filter(aims_monthly_attendance_daily($pdo,$period),
      static fn($r)=>($plate===''||$r['plate']===$plate)&&($driver===''||$r['flowId']===$driver)));
    return ['month'=>$from.'_'.$to,'period'=>$period,'generatedAt'=>new DateTimeImmutable('now',new DateTimeZone('UTC')),
      'countryRows'=>$country,'attendanceRows'=>$daily,'attendanceSummary'=>aims_monthly_attendance_summary($pdo,$period,$daily)];
}

function aims_monthly_csv(array $headers, array $rows): string {
    $stream = fopen('php://temp', 'w+');
    if ($stream === false) throw new RuntimeException('CSV stream nem nyitható.');
    fwrite($stream, "\xEF\xBB\xBF");
    fputcsv($stream, $headers, ';', '"', '\\', "\r\n");
    foreach ($rows as $row) {
        foreach ($row as &$cell) { if (is_string($cell) && preg_match('/^[\s]*[=+@-]/u',$cell)) $cell="'".$cell; } unset($cell);
        fputcsv($stream, $row, ';', '"', '\\', "\r\n");
    }
    rewind($stream);
    $content = stream_get_contents($stream);
    fclose($stream);
    if ($content === false) throw new RuntimeException('CSV nem olvasható.');
    return $content;
}

function aims_monthly_country_csv(array $report, ?string $onlyPlate = null): string {
    $rows = [];
    foreach ($report['countryRows'] as $row) {
        if ($onlyPlate !== null && $row['plate'] !== $onlyPlate) continue;
        $duration = $row['duration'];
        $rows[] = [
            $report['month'], $row['plate'], $row['label'],
            $row['countryCode'], $row['countryName'],
            $duration['days'], $duration['hours'], $duration['minutes'],
            $duration['formatted'], $duration['seconds'],
        ];
    }
    return aims_monthly_csv([
        'Hónap','Rendszám','Jármű megnevezése','Országkód','Ország',
        'Nap','Óra','Perc','Időtartam','Másodperc',
    ], $rows);
}

function aims_monthly_attendance_csv(array $report): string {
    $rows = [];
    foreach ($report['attendanceRows'] as $row) {
        $rows[] = [
            $report['month'], $row['date'], $row['flowId'], $row['driverName'],
            $row['email'], $row['plate'],
            $row['firstStart']->format('Y-m-d H:i:s'),
            $row['lastEnd']->format('Y-m-d H:i:s'),
            $row['grossDuration']['hhmm'], $row['restDuration']['hhmm'],
            $row['duration']['hhmm'], $row['duration']['seconds'],
            $row['dailyStatus'],
        ];
    }
    return aims_monthly_csv([
        'Hónap','Dátum','FLOW ID','Sofőr','E-mail','Rendszám',
        'Első munkakezdés','Utolsó munkavégzés vége','Bruttó FLOW-idő HH:MM','Rögzített pihenő HH:MM','Nettó FLOW-idő HH:MM',
        'Nettó FLOW-idő másodperc','Napi ellenőrzési állapot',
    ], $rows);
}

function aims_monthly_attendance_summary_csv(array $report): string {
    $rows = [];
    foreach ($report['attendanceSummary'] as $row) {
        $rows[] = [
            $report['month'], $row['flowId'], $row['driverName'], $row['email'],
            $row['plates'], $row['days'], $row['grossDuration']['hhmm'], $row['restDuration']['hhmm'], $row['duration']['hhmm'],
            $row['normHours'] === null ? '' : number_format((float)$row['normHours'], 2, ',', ''),
            $row['differenceHours'] === null ? '' : number_format((float)$row['differenceHours'], 2, ',', ''),
            number_format((float)$row['maxWeeklyHours'], 2, ',', ''),
            $row['average4MonthWeeklyHours'] === null
                ? ''
                : number_format((float)$row['average4MonthWeeklyHours'], 2, ',', ''),
            $row['status'],
        ];
    }
    return aims_monthly_csv([
        'Hónap','FLOW ID','Sofőr','E-mail','Rendszámok','Munkanapok száma',
        'Bruttó FLOW-idő HH:MM','Rögzített pihenő HH:MM','Nettó FLOW-idő HH:MM','Havi általános norma óra','Eltérés óra',
        'Legmagasabb heti óra','4 havi átlag óra/hét','Állapot',
    ], $rows);
}

class AimsMonthlyReportBusy extends RuntimeException {}

/** The resource must stay open through generation, mail submission and logging. */
function aims_monthly_acquire_lock(string $month) {
    aims_monthly_period($month);
    $path = aims_monthly_report_directory().'/'.$month.'.lock';
    $handle = fopen($path,'c');
    if ($handle === false) throw new RuntimeException('A riport zárolása nem hozható létre.');
    @chmod($path,0600);
    if (!flock($handle,LOCK_EX|LOCK_NB)) {
        fclose($handle);
        throw new AimsMonthlyReportBusy('Ehhez a hónaphoz már folyamatban van egy riportművelet.');
    }
    return $handle;
}

function aims_monthly_report_directory(): string {
    $dir = trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: ''));
    if ($dir === '') $dir = __DIR__.'/data';
    $dir .= '/monthly-reports';
    if (!is_dir($dir) && !mkdir($dir, 0700, true) && !is_dir($dir)) {
        throw new RuntimeException('A havi riport könyvtár nem hozható létre.');
    }
    $deny = $dir.'/.htaccess';
    if (!is_file($deny) && file_put_contents($deny,"Require all denied\n",LOCK_EX) === false) {
        throw new RuntimeException('A riportkönyvtár HTTP-védelme nem írható.');
    }
    return $dir;
}

function aims_monthly_store_report(array $report): array {
    $monthDir = aims_monthly_report_directory().'/'.$report['month'];
    if (!is_dir($monthDir) && !mkdir($monthDir, 0700, true) && !is_dir($monthDir)) {
        throw new RuntimeException('A havi riport mappája nem hozható létre.');
    }

    $files = [
        'AIMS-FLOW-orszagido-'.$report['month'].'.csv'=>aims_monthly_country_csv($report),
        'AIMS-FLOW-jelenleti-iv-'.$report['month'].'.csv'=>aims_monthly_attendance_csv($report),
        'AIMS-FLOW-jelenleti-osszesito-'.$report['month'].'.csv'=>aims_monthly_attendance_summary_csv($report),
    ];
    foreach ($report['countryRows'] as $row) {
        $plate = $row['plate'];
        $name = 'AIMS-FLOW-orszagido-'.$plate.'-'.$report['month'].'.csv';
        if (!isset($files[$name])) $files[$name] = aims_monthly_country_csv($report, $plate);
    }

    $paths = [];
    foreach ($files as $name=>$content) {
        $path = $monthDir.'/'.$name;
        if (file_put_contents($path, $content, LOCK_EX) === false) {
            throw new RuntimeException('A riportfájl nem írható: '.$name);
        }
        @chmod($path, 0600);
        $paths[$name] = $path;
    }
    return $paths;
}

function aims_monthly_email_text(array $report): string {
    return "Tisztelt Iroda!\n\n"
        ."Az AIMS FLOW elkészítette a {$report['month']} havi ország- és jelenléti összesítést.\n\n"
        ."A csatolmányok tartalmazzák:\n"
        ."- rendszámonként az egyes országokban töltött időt nap / óra / perc bontásban;\n"
        ."- sofőrönként és naponként a FLOW-ban rögzített munkakezdést, munkavégzés-véget, bruttó időt, rögzített pihenőt és nettó FLOW-időt;\n"
        ."- a havi általános munkaidőnormához, a heti 60 órás felső ellenőrzési küszöbhöz és a négyhavi 48 órás heti átlaghoz viszonyított figyelmeztetéseket.\n\n"
        ."Fontos: a jelentés az AIMS FLOW GPS- és munkanap-adataiból készült. Nem helyettesíti a tachográf-adatok, a szabadságok, betegállományok, rendelkezésre állási idők, munkaközi szünetek, bérszámfejtési adatok és a munkaidőkeret irodai ellenőrzését.\n\n"
        ."A határátlépés csak akkor kerül a riportba, ha az új országban legalább 5 km hiteles mozgás megerősítette az országváltást.\n\n"
        ."Üdvözlettel:\nAIMS FLOW\nAutomatikus havi riport\n";
}

function aims_monthly_send_mail(array $report, array $paths, string $recipient): bool {
    if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        throw new InvalidArgumentException('Érvénytelen havi riport e-mail-cím.');
    }
    $from = trim((string)(getenv('AIMS_FLOW_FROM_EMAIL') ?: 'Start@logistic-aims.hu'));
    if (!filter_var($from,FILTER_VALIDATE_EMAIL)) throw new InvalidArgumentException('Érvénytelen feladó e-mail-cím.');
    $subject = 'AIMS FLOW havi ország- és jelenléti riport – '.$report['month'];
    $boundary = 'aims-flow-'.bin2hex(random_bytes(12));
    $body = "--{$boundary}\r\n"
        ."Content-Type: text/plain; charset=UTF-8\r\n"
        ."Content-Transfer-Encoding: 8bit\r\n\r\n"
        .aims_monthly_email_text($report)."\r\n";

    foreach (['orszagido','jelenleti-iv','jelenleti-osszesito'] as $kind) {
        $required = 'AIMS-FLOW-'.$kind.'-'.$report['month'].'.csv';
        if (!isset($paths[$required]) || !is_readable($paths[$required])) {
            throw new RuntimeException('Hiányzó riportcsatolmány: '.$required);
        }
    }
    foreach ($paths as $name=>$path) {
        // The combined three reports are attached. Per-plate files remain in
        // the secure monthly report directory for audit and manual download.
        if (!str_starts_with($name, 'AIMS-FLOW-orszagido-'.$report['month']) &&
            !str_starts_with($name, 'AIMS-FLOW-jelenleti-iv-') &&
            !str_starts_with($name, 'AIMS-FLOW-jelenleti-osszesito-')) {
            continue;
        }
        $content = file_get_contents($path);
        if ($content === false) throw new RuntimeException('Nem olvasható riportcsatolmány: '.$name);
        $body .= "--{$boundary}\r\n"
            ."Content-Type: text/csv; name=\"{$name}\"\r\n"
            ."Content-Disposition: attachment; filename=\"{$name}\"\r\n"
            ."Content-Transfer-Encoding: base64\r\n\r\n"
            .chunk_split(base64_encode($content))."\r\n";
    }
    $body .= "--{$boundary}--\r\n";

    $headers = [
        'MIME-Version: 1.0',
        'From: AIMS FLOW <'.$from.'>',
        'Reply-To: '.$from,
        'Content-Type: multipart/mixed; boundary="'.$boundary.'"',
    ];
    return @mail(
        $recipient,
        '=?UTF-8?B?'.base64_encode($subject).'?=',
        $body,
        implode("\r\n", $headers)
    );
}

function aims_monthly_runs_schema(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS monthly_report_runs (
        month TEXT PRIMARY KEY,
        recipient TEXT NOT NULL,
        generated_at TEXT NOT NULL,
        sent_at TEXT,
        status TEXT NOT NULL,
        detail TEXT,
        files_json TEXT
    )');
}

function aims_monthly_run_state(PDO $pdo, string $month): ?array {
    aims_monthly_runs_schema($pdo);
    $stmt = $pdo->prepare('SELECT * FROM monthly_report_runs WHERE month=:month LIMIT 1');
    $stmt->execute([':month'=>$month]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function aims_monthly_record_run(
    PDO $pdo,
    string $month,
    string $recipient,
    string $status,
    string $detail,
    array $paths,
    ?string $sentAt = null
): void {
    aims_monthly_runs_schema($pdo);
    $stmt = $pdo->prepare('INSERT INTO monthly_report_runs
        (month,recipient,generated_at,sent_at,status,detail,files_json)
        VALUES (:month,:recipient,:generated,:sent,:status,:detail,:files)
        ON CONFLICT(month) DO UPDATE SET
          recipient=excluded.recipient,
          generated_at=excluded.generated_at,
          sent_at=excluded.sent_at,
          status=excluded.status,
          detail=excluded.detail,
          files_json=excluded.files_json');
    $stmt->execute([
        ':month'=>$month,
        ':recipient'=>$recipient,
        ':generated'=>gmdate(DateTimeInterface::ATOM),
        ':sent'=>$sentAt,
        ':status'=>$status,
        ':detail'=>$detail,
        ':files'=>json_encode($paths, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    ]);
}

