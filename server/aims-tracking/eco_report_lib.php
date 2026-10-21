<?php
declare(strict_types=1);

/**
 * AIMS FLOW ECO driving-style analytics.
 *
 * The calculation uses consecutive, quality-filtered GPS speed samples that
 * fall inside a recorded driver workday. It deliberately avoids speed-limit
 * or fuel-consumption claims because the current FLOW point stream does not
 * contain a certified road-speed-limit or CAN-bus fuel feed.
 */

function aims_eco_thresholds(): array {
    return [
        'smooth_abs_mps2' => 0.55,
        'hard_accel_mps2' => 1.25,
        'severe_accel_mps2' => 2.00,
        'hard_brake_mps2' => -1.75,
        'severe_brake_mps2' => -2.75,
        'accel_reset_mps2' => 0.65,
        'brake_reset_mps2' => -0.80,
        'minimum_distance_km' => 50.0,
        'minimum_moving_seconds' => 2700,
        'minimum_segments' => 80,
        'maximum_sample_gap_seconds' => 30,
        'maximum_accuracy_m' => 80.0,
        'maximum_speed_mps' => 55.6,
    ];
}

function aims_eco_period(string $fromRaw, string $toRaw): array {
    $tz = new DateTimeZone('Europe/Budapest');
    $utc = new DateTimeZone('UTC');
    $from = DateTimeImmutable::createFromFormat('!Y-m-d', $fromRaw, $tz);
    $to = DateTimeImmutable::createFromFormat('!Y-m-d', $toRaw, $tz);
    if (!$from || !$to) {
        throw new InvalidArgumentException('Érvénytelen dátumtartomány.');
    }
    $to = $to->modify('+1 day');
    if ($to <= $from) {
        throw new InvalidArgumentException('A záró dátum nem lehet korábbi a kezdő dátumnál.');
    }
    if ($to->getTimestamp() - $from->getTimestamp() > 93 * 86400) {
        throw new InvalidArgumentException('Legfeljebb 93 nap kérhető le egyszerre.');
    }
    return [
        'fromLocal' => $from,
        'toLocal' => $to,
        'fromUtc' => $from->setTimezone($utc),
        'toUtc' => $to->setTimezone($utc),
        'tz' => $tz,
        'utc' => $utc,
    ];
}

function aims_eco_table_exists(PDO $pdo, string $table): bool {
    $stmt = $pdo->prepare('SELECT 1 FROM sqlite_master WHERE type="table" AND name=:name LIMIT 1');
    $stmt->execute([':name' => $table]);
    return $stmt->fetchColumn() !== false;
}

function aims_eco_accounts(PDO $pdo): array {
    $byFlow = [];
    $byVehicle = [];
    if (!aims_eco_table_exists($pdo, 'driver_accounts')) {
        return ['byFlow' => $byFlow, 'byVehicle' => $byVehicle];
    }
    $rows = $pdo->query('SELECT flow_id,driver_name,email,vehicle_id,enabled,updated_at
        FROM driver_accounts ORDER BY updated_at DESC,id DESC')->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as $row) {
        $flowId = trim((string)($row['flow_id'] ?? ''));
        $vehicleId = (int)($row['vehicle_id'] ?? 0);
        if ($flowId !== '' && !isset($byFlow[$flowId])) $byFlow[$flowId] = $row;
        if ($vehicleId > 0 && (int)($row['enabled'] ?? 0) === 1 && !isset($byVehicle[$vehicleId])) {
            $byVehicle[$vehicleId] = $row;
        }
    }
    return ['byFlow' => $byFlow, 'byVehicle' => $byVehicle];
}

function aims_eco_driver_for_workday(array $row, array $accounts): array {
    $flowId = '';
    if (preg_match('/^(\d{6})(?:-|$)/', (string)$row['workday_key'], $match)) {
        $flowId = $match[1];
    }
    $account = null;
    if ($flowId !== '' && isset($accounts['byFlow'][$flowId])) {
        $account = $accounts['byFlow'][$flowId];
    } elseif (isset($accounts['byVehicle'][(int)$row['vehicle_id']])) {
        $account = $accounts['byVehicle'][(int)$row['vehicle_id']];
        $flowId = trim((string)($account['flow_id'] ?? $flowId));
    }
    $driverName = trim((string)($account['driver_name'] ?? ''));
    if ($driverName === '') {
        $driverName = $flowId !== '' ? 'FLOW '.$flowId : 'Nincs hozzárendelt sofőr';
    }
    return [
        'flowId' => $flowId,
        'driverName' => $driverName,
        'email' => trim((string)($account['email'] ?? '')),
    ];
}

function aims_eco_workday_intervals(
    PDO $pdo,
    array $period,
    string $plateFilter = '',
    string $driverFilter = ''
): array {
    $accounts = aims_eco_accounts($pdo);
    $sql = 'SELECT w.id,w.workday_key,w.vehicle_id,w.started_at,w.finished_at,
                   v.plate,v.label
            FROM driver_workdays w
            JOIN vehicles v ON v.id=w.vehicle_id
            WHERE w.started_at < :end
              AND COALESCE(w.finished_at,:end) > :start';
    $params = [
        ':start' => $period['fromUtc']->format(DateTimeInterface::ATOM),
        ':end' => $period['toUtc']->format(DateTimeInterface::ATOM),
    ];
    $plateFilter = aims_normalize_plate($plateFilter);
    if ($plateFilter !== '') {
        $sql .= ' AND v.plate=:plate';
        $params[':plate'] = $plateFilter;
    }
    $sql .= ' ORDER BY w.vehicle_id,w.started_at,w.id';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    $now = new DateTimeImmutable('now', $period['utc']);
    $rangeEnd = $period['toUtc'] < $now ? $period['toUtc'] : $now;
    $byVehicle = [];
    $drivers = [];
    $plates = [];

    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        try {
            $start = new DateTimeImmutable((string)$row['started_at']);
        } catch (Throwable) {
            continue;
        }
        $end = null;
        if (trim((string)($row['finished_at'] ?? '')) !== '') {
            try { $end = new DateTimeImmutable((string)$row['finished_at']); } catch (Throwable) {}
        }
        if ($start < $period['fromUtc']) $start = $period['fromUtc'];
        $end ??= $rangeEnd;
        if ($end > $rangeEnd) $end = $rangeEnd;
        if ($end <= $start) continue;

        $driver = aims_eco_driver_for_workday($row, $accounts);
        if ($driverFilter !== '' && $driver['flowId'] !== $driverFilter) continue;

        $plate = aims_normalize_plate((string)$row['plate']);
        $interval = [
            'workdayId' => (int)$row['id'],
            'vehicleId' => (int)$row['vehicle_id'],
            'workdayKey' => (string)$row['workday_key'],
            'start' => $start,
            'end' => $end,
            'plate' => $plate,
            'label' => trim((string)$row['label']) ?: $plate,
            'flowId' => $driver['flowId'],
            'driverName' => $driver['driverName'],
            'email' => $driver['email'],
        ];
        $byVehicle[$interval['vehicleId']][] = $interval;
        $driverKey = $interval['flowId'] !== '' ? $interval['flowId'] : 'vehicle-'.$interval['vehicleId'];
        $drivers[$driverKey] = [
            'flowId' => $interval['flowId'],
            'driverName' => $interval['driverName'],
        ];
        $plates[$plate] = $interval['label'];
    }
    return ['byVehicle' => $byVehicle, 'drivers' => $drivers, 'plates' => $plates];
}

function aims_eco_empty_group(array $interval): array {
    return [
        'flowId' => $interval['flowId'],
        'driverName' => $interval['driverName'],
        'email' => $interval['email'],
        'vehicleId' => $interval['vehicleId'],
        'plate' => $interval['plate'],
        'label' => $interval['label'],
        'distanceM' => 0.0,
        'movingSeconds' => 0,
        'validSegments' => 0,
        'smoothSegments' => 0,
        'hardAccel' => 0,
        'severeAccel' => 0,
        'hardBrake' => 0,
        'severeBrake' => 0,
        'maxAccel' => 0.0,
        'maxBrake' => 0.0,
        'pointCount' => 0,
    ];
}

function aims_eco_append_event(
    array &$events,
    array $interval,
    array $point,
    string $type,
    string $severity,
    float $acceleration,
    float $beforeSpeed,
    float $afterSpeed
): void {
    if (count($events) >= 3000) return;
    $events[] = [
        'capturedAt' => $point['_captured'],
        'flowId' => $interval['flowId'],
        'driverName' => $interval['driverName'],
        'plate' => $interval['plate'],
        'type' => $type,
        'severity' => $severity,
        'accelerationMps2' => $acceleration,
        'beforeKmh' => $beforeSpeed * 3.6,
        'afterKmh' => $afterSpeed * 3.6,
        'latitude' => (float)$point['latitude'],
        'longitude' => (float)$point['longitude'],
    ];
}

function aims_eco_grade(array $group, array $thresholds): array {
    $distanceKm = $group['distanceM'] / 1000.0;
    $enough = $distanceKm >= $thresholds['minimum_distance_km']
        && $group['movingSeconds'] >= $thresholds['minimum_moving_seconds']
        && $group['validSegments'] >= $thresholds['minimum_segments'];

    $baseDistance = max(1.0, $distanceKm);
    $hardAccelRate = $group['hardAccel'] / $baseDistance * 100.0;
    $severeAccelRate = $group['severeAccel'] / $baseDistance * 100.0;
    $hardBrakeRate = $group['hardBrake'] / $baseDistance * 100.0;
    $severeBrakeRate = $group['severeBrake'] / $baseDistance * 100.0;
    $smoothRatio = $group['validSegments'] > 0
        ? $group['smoothSegments'] / $group['validSegments']
        : 0.0;

    $penalty = $hardAccelRate * 1.8
        + $hardBrakeRate * 2.2
        + $severeAccelRate * 4.0
        + $severeBrakeRate * 5.0
        + max(0.0, (0.75 - $smoothRatio) * 40.0);
    $score = max(0.0, min(100.0, 100.0 - $penalty));
    $combinedHard = $hardAccelRate + $hardBrakeRate;
    $combinedSevere = $severeAccelRate + $severeBrakeRate;

    if (!$enough) {
        $grade = '—';
        $label = 'Nincs elég adat';
    } elseif ($score >= 90.0 && $combinedHard <= 4.0 && $combinedSevere <= 0.5) {
        $grade = 'A';
        $label = 'Kímélő és egyenletes';
    } elseif ($score >= 75.0 && $combinedHard <= 10.0 && $combinedSevere <= 2.0) {
        $grade = 'B';
        $label = 'Jó, kisebb kilengésekkel';
    } elseif ($score >= 55.0 && $combinedHard <= 20.0 && $combinedSevere <= 5.0) {
        $grade = 'C';
        $label = 'Fejlesztendő vezetési minta';
    } else {
        $grade = 'D';
        $label = 'Erősen egyenetlen vezetési minta';
    }

    return [
        'enoughData' => $enough,
        'grade' => $grade,
        'label' => $label,
        'score' => $score,
        'distanceKm' => $distanceKm,
        'movingHours' => $group['movingSeconds'] / 3600.0,
        'smoothRatio' => $smoothRatio,
        'hardAccelRate' => $hardAccelRate,
        'severeAccelRate' => $severeAccelRate,
        'hardBrakeRate' => $hardBrakeRate,
        'severeBrakeRate' => $severeBrakeRate,
    ];
}

function aims_eco_build_report(
    PDO $pdo,
    string $fromRaw,
    string $toRaw,
    string $plateFilter = '',
    string $driverFilter = ''
): array {
    $period = aims_eco_period($fromRaw, $toRaw);
    $thresholds = aims_eco_thresholds();
    $intervalData = aims_eco_workday_intervals($pdo, $period, $plateFilter, $driverFilter);
    $intervalsByVehicle = $intervalData['byVehicle'];
    $groups = [];
    $events = [];
    $states = [];
    $intervalIndex = [];

    if ($intervalsByVehicle) {
        $vehicleIds = array_map('intval', array_keys($intervalsByVehicle));
        $placeholders = implode(',', array_fill(0, count($vehicleIds), '?'));
        $sql = 'SELECT id,vehicle_id,captured_at,latitude,longitude,accuracy,speed_mps,source
                FROM points
                WHERE vehicle_id IN ('.$placeholders.')
                  AND captured_at>=? AND captured_at<?
                  AND speed_mps IS NOT NULL
                ORDER BY vehicle_id,captured_at,id';
        $params = $vehicleIds;
        $params[] = $period['fromUtc']->format(DateTimeInterface::ATOM);
        $params[] = $period['toUtc']->format(DateTimeInterface::ATOM);
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $point) {
            $vehicleId = (int)$point['vehicle_id'];
            if (!isset($intervalsByVehicle[$vehicleId])) continue;
            try {
                $captured = new DateTimeImmutable((string)$point['captured_at']);
            } catch (Throwable) {
                continue;
            }
            $captured = $captured->setTimezone($period['utc']);
            $point['_captured'] = $captured;
            $intervals = $intervalsByVehicle[$vehicleId];
            $index = $intervalIndex[$vehicleId] ?? 0;
            while ($index < count($intervals) && $captured >= $intervals[$index]['end']) $index++;
            $intervalIndex[$vehicleId] = $index;
            if ($index >= count($intervals)) continue;
            $interval = $intervals[$index];
            if ($captured < $interval['start'] || $captured >= $interval['end']) continue;

            $workdayId = $interval['workdayId'];
            $groupKey = ($interval['flowId'] !== '' ? $interval['flowId'] : 'unknown').':'.$vehicleId;
            if (!isset($groups[$groupKey])) $groups[$groupKey] = aims_eco_empty_group($interval);
            $groups[$groupKey]['pointCount']++;

            $speed = max(0.0, (float)$point['speed_mps']);
            $accuracy = $point['accuracy'] === null ? 20.0 : max(0.0, (float)$point['accuracy']);
            if ($speed > $thresholds['maximum_speed_mps'] || $accuracy > $thresholds['maximum_accuracy_m']) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }

            if (!isset($states[$workdayId])) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }
            $state = $states[$workdayId];
            $previousPoint = $state['point'];
            $previousSpeed = (float)$state['speed'];
            $dt = $captured->getTimestamp() - $previousPoint['_captured']->getTimestamp();
            if ($dt < 2 || $dt > $thresholds['maximum_sample_gap_seconds']) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }
            $previousAccuracy = $previousPoint['accuracy'] === null ? 20.0 : max(0.0, (float)$previousPoint['accuracy']);
            if ($previousAccuracy > $thresholds['maximum_accuracy_m']) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }

            $averageSpeed = ($previousSpeed + $speed) / 2.0;
            if ($averageSpeed < 2.0) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }

            $acceleration = ($speed - $previousSpeed) / $dt;
            if (!is_finite($acceleration) || abs($acceleration) > 6.0) {
                $states[$workdayId] = ['point'=>$point,'speed'=>$speed,'inAccel'=>false,'severeAccel'=>false,'inBrake'=>false,'severeBrake'=>false];
                continue;
            }

            $distanceM = $averageSpeed * $dt;
            $groups[$groupKey]['distanceM'] += $distanceM;
            $groups[$groupKey]['movingSeconds'] += $dt;
            $groups[$groupKey]['validSegments']++;
            if (abs($acceleration) <= $thresholds['smooth_abs_mps2']) {
                $groups[$groupKey]['smoothSegments']++;
            }
            $groups[$groupKey]['maxAccel'] = max($groups[$groupKey]['maxAccel'], $acceleration);
            $groups[$groupKey]['maxBrake'] = max($groups[$groupKey]['maxBrake'], -$acceleration);

            $inAccel = (bool)$state['inAccel'];
            $severeAccelSeen = (bool)$state['severeAccel'];
            $inBrake = (bool)$state['inBrake'];
            $severeBrakeSeen = (bool)$state['severeBrake'];

            if ($acceleration >= $thresholds['hard_accel_mps2']) {
                if (!$inAccel) {
                    $groups[$groupKey]['hardAccel']++;
                    aims_eco_append_event($events, $interval, $point, 'Hirtelen gyorsítás', 'warning', $acceleration, $previousSpeed, $speed);
                    $inAccel = true;
                }
                if ($acceleration >= $thresholds['severe_accel_mps2'] && !$severeAccelSeen) {
                    $groups[$groupKey]['severeAccel']++;
                    aims_eco_append_event($events, $interval, $point, 'Súlyos gyorsítás', 'critical', $acceleration, $previousSpeed, $speed);
                    $severeAccelSeen = true;
                }
            } elseif ($acceleration < $thresholds['accel_reset_mps2']) {
                $inAccel = false;
                $severeAccelSeen = false;
            }

            if ($acceleration <= $thresholds['hard_brake_mps2']) {
                if (!$inBrake) {
                    $groups[$groupKey]['hardBrake']++;
                    aims_eco_append_event($events, $interval, $point, 'Erős fékezés', 'warning', $acceleration, $previousSpeed, $speed);
                    $inBrake = true;
                }
                if ($acceleration <= $thresholds['severe_brake_mps2'] && !$severeBrakeSeen) {
                    $groups[$groupKey]['severeBrake']++;
                    aims_eco_append_event($events, $interval, $point, 'Súlyos fékezés', 'critical', $acceleration, $previousSpeed, $speed);
                    $severeBrakeSeen = true;
                }
            } elseif ($acceleration > $thresholds['brake_reset_mps2']) {
                $inBrake = false;
                $severeBrakeSeen = false;
            }

            $states[$workdayId] = [
                'point'=>$point,'speed'=>$speed,
                'inAccel'=>$inAccel,'severeAccel'=>$severeAccelSeen,
                'inBrake'=>$inBrake,'severeBrake'=>$severeBrakeSeen,
            ];
        }
    }

    $rows = [];
    foreach ($groups as $group) {
        $metrics = aims_eco_grade($group, $thresholds);
        $rows[] = array_merge($group, $metrics);
    }
    usort($rows, static function(array $a, array $b): int {
        $gradeRank = ['A'=>0,'B'=>1,'C'=>2,'D'=>3,'—'=>4];
        $rank = ($gradeRank[$a['grade']] ?? 5) <=> ($gradeRank[$b['grade']] ?? 5);
        if ($rank !== 0) return $rank;
        $score = $b['score'] <=> $a['score'];
        if ($score !== 0) return $score;
        return [$a['driverName'],$a['plate']] <=> [$b['driverName'],$b['plate']];
    });
    usort($events, static fn(array $a, array $b): int => $b['capturedAt'] <=> $a['capturedAt']);

    return [
        'period' => $period,
        'thresholds' => $thresholds,
        'rows' => $rows,
        'events' => $events,
        'drivers' => $intervalData['drivers'],
        'plates' => $intervalData['plates'],
        'generatedAt' => new DateTimeImmutable('now', $period['utc']),
    ];
}

function aims_eco_csv(array $report): string {
    $stream = fopen('php://temp', 'w+');
    if ($stream === false) throw new RuntimeException('CSV stream nem nyitható.');
    fwrite($stream, "\xEF\xBB\xBF");
    fputcsv($stream, [
        'FLOW ID','Sofőr','Rendszám','Minősítés','Pontszám','Távolság km',
        'Mozgási idő óra','Egyenletes szakasz %','Hirtelen gyorsítás / 100 km',
        'Súlyos gyorsítás / 100 km','Erős fékezés / 100 km',
        'Súlyos fékezés / 100 km','Max gyorsulás m/s²','Max lassulás m/s²',
        'Érvényes szakasz','Értékelhető',
    ], ';', '"', '\\', "\r\n");
    foreach ($report['rows'] as $row) {
        fputcsv($stream, [
            $row['flowId'],$row['driverName'],$row['plate'],$row['grade'],
            number_format((float)$row['score'],1,',',''),
            number_format((float)$row['distanceKm'],1,',',''),
            number_format((float)$row['movingHours'],1,',',''),
            number_format((float)$row['smoothRatio']*100,1,',',''),
            number_format((float)$row['hardAccelRate'],2,',',''),
            number_format((float)$row['severeAccelRate'],2,',',''),
            number_format((float)$row['hardBrakeRate'],2,',',''),
            number_format((float)$row['severeBrakeRate'],2,',',''),
            number_format((float)$row['maxAccel'],2,',',''),
            number_format((float)$row['maxBrake'],2,',',''),
            $row['validSegments'],$row['enoughData']?'igen':'nem',
        ], ';', '"', '\\', "\r\n");
    }
    rewind($stream);
    $content = stream_get_contents($stream);
    fclose($stream);
    if ($content === false) throw new RuntimeException('CSV nem olvasható.');
    return $content;
}
