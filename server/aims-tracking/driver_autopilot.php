<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/smart_rules.php';

aims_require_token('AIMS_TRACKING_TOKEN');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$plate = aims_normalize_plate((string)($_GET['plate'] ?? ''));
if ($plate === '') {
    aims_json(['ok' => false, 'error' => 'invalid_plate'], 422);
}

$pdo = aims_db();
$now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

$minutesAgo = static function (?string $value) use ($now): ?int {
    if (!$value) return null;
    try {
        $dt = (new DateTimeImmutable($value))->setTimezone(new DateTimeZone('UTC'));
        return max(0, (int)floor(($now->getTimestamp() - $dt->getTimestamp()) / 60));
    } catch (Throwable) {
        return null;
    }
};

$clamp = static fn (int $value, int $min, int $max): int => max($min, min($max, $value));

$q = $pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$q->execute([':plate' => $plate]);
$vehicle = $q->fetch(PDO::FETCH_ASSOC);

$idlePayload = static function (array $extra = []) use ($now): array {
    return array_merge([
        'version' => 'R96',
        'mode' => 'idle',
        'actionCode' => 'wait_job',
        'secondaryActionCode' => 'message_office',
        'severity' => 'info',
        'riskScore' => 0,
        'confidence' => 100,
        'reasonCodes' => [],
        'refreshAfterSeconds' => 60,
        'jobId' => null,
        'reference' => '',
        'seen' => false,
        'accepted' => false,
        'totalStops' => 0,
        'completedStops' => 0,
        'progressPct' => 0,
        'nextStop' => null,
        'gpsAgeMinutes' => null,
        'gpsAccuracyMeters' => null,
        'currentSpeedKmh' => null,
        'stationaryMinutes' => null,
        'stopDwellMinutes' => null,
        'distanceKm' => null,
        'etaMinutes' => null,
        'plannedAt' => null,
        'timeBufferMinutes' => null,
        'isLate' => false,
        'sequenceAnomaly' => false,
        'documentsRequired' => false,
        'gpsFresh' => false,
        'dataQuality' => [
            'gps' => 'unknown',
            'nextStop' => 'none',
            'schedule' => 'unknown',
        ],
        'alertFingerprint' => sha1('idle'),
        'updatedAt' => $now->format(DateTimeInterface::ATOM),
    ], $extra);
};

if (!$vehicle) {
    aims_json([
        'ok' => true,
        'plate' => $plate,
        'autopilot' => $idlePayload([
            'confidence' => 45,
            'reasonCodes' => ['vehicle_not_registered'],
        ]),
    ]);
}

$j = $pdo->prepare('SELECT * FROM jobs WHERE vehicle_id=:v AND status="active" ORDER BY id DESC LIMIT 1');
$j->execute([':v' => $vehicle['id']]);
$job = $j->fetch(PDO::FETCH_ASSOC);

$p = $pdo->prepare('SELECT * FROM points WHERE vehicle_id=:v ORDER BY captured_at DESC,id DESC LIMIT 1');
$p->execute([':v' => $vehicle['id']]);
$point = $p->fetch(PDO::FETCH_ASSOC) ?: null;

$vs = $pdo->prepare('SELECT * FROM vehicle_state WHERE vehicle_id=:v LIMIT 1');
$vs->execute([':v' => $vehicle['id']]);
$state = $vs->fetch(PDO::FETCH_ASSOC) ?: null;

$gpsAge = $minutesAgo($point['captured_at'] ?? null);
$stationaryMin = $minutesAgo($state['stationary_since'] ?? null);
$gpsAccuracy = isset($point['accuracy']) && is_numeric($point['accuracy'])
    ? round((float)$point['accuracy'], 1)
    : null;
$currentSpeedKmh = isset($point['speed_mps']) && is_numeric($point['speed_mps'])
    ? round(max(0.0, (float)$point['speed_mps'] * 3.6), 1)
    : null;
$gpsFresh = $gpsAge !== null && $gpsAge < 20;

if (!$job) {
    $reasons = [];
    $confidence = 100;
    if (!$point) {
        $reasons[] = 'gps_missing';
        $confidence -= 25;
    } elseif (!$gpsFresh) {
        $reasons[] = 'gps_stale';
        $confidence -= 20;
    }

    aims_json([
        'ok' => true,
        'plate' => $plate,
        'autopilot' => $idlePayload([
            'gpsAgeMinutes' => $gpsAge,
            'gpsAccuracyMeters' => $gpsAccuracy,
            'currentSpeedKmh' => $currentSpeedKmh,
            'stationaryMinutes' => $stationaryMin,
            'gpsFresh' => $gpsFresh,
            'confidence' => $clamp($confidence, 0, 100),
            'reasonCodes' => $reasons,
            'dataQuality' => [
                'gps' => !$point ? 'missing' : ($gpsFresh ? 'fresh' : 'stale'),
                'nextStop' => 'none',
                'schedule' => 'none',
            ],
            'alertFingerprint' => sha1('idle|' . implode('|', $reasons)),
        ]),
    ]);
}

$st = $pdo->prepare('SELECT * FROM job_stops WHERE job_id=:j ORDER BY stop_order ASC,id ASC');
$st->execute([':j' => $job['id']]);
$stops = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];

$completed = 0;
$next = null;
$seenIncomplete = false;
$sequenceAnomaly = false;

foreach ($stops as $row) {
    $done = !empty($row['completed_at']);
    if ($done) $completed++;

    if (!$done && $next === null) {
        $next = $row;
        $seenIncomplete = true;
        continue;
    }

    if (
        $seenIncomplete &&
        (!empty($row['inside_since']) || !empty($row['arrival_notified_at']) || !empty($row['completed_at']))
    ) {
        $sequenceAnomaly = true;
    }
}

$totalStops = count($stops);
$allDone = $totalStops > 0 && $completed === $totalStops;
$progressPct = $totalStops > 0 ? (int)round(($completed / $totalStops) * 100) : 0;
$seen = !empty($job['driver_seen_at']);
$accepted = !empty($job['driver_accepted_at']);

$mode = 'enroute';
$action = 'navigate_next';
$secondaryAction = 'quick_signal';

if (!$seen) {
    $mode = 'new_job';
    $action = 'open_job';
    $secondaryAction = 'message_office';
} elseif (!$accepted) {
    $mode = 'awaiting_acceptance';
    $action = 'accept_job';
    $secondaryAction = 'message_office';
} elseif ($allDone) {
    $mode = 'documents';
    $action = 'scan_documents';
    $secondaryAction = 'message_office';
} elseif ($next && !empty($next['inside_since'])) {
    $mode = 'at_stop';
    $action = $next['stop_type'] === 'delivery' ? 'finish_delivery' : 'finish_pickup';
    $secondaryAction = 'signal_waiting';
} elseif ($next) {
    $mode = 'enroute';
    $action = 'navigate_next';
    $secondaryAction = 'quick_signal';
} else {
    $mode = 'attention';
    $action = 'refresh_job';
    $secondaryAction = 'message_office';
}

$dwell = $next ? $minutesAgo($next['inside_since'] ?? null) : null;

$distanceKm = null;
$etaMin = null;
$nextHasCoordinates = false;

if ($next && $point && is_numeric($point['latitude'] ?? null) && is_numeric($point['longitude'] ?? null)) {
    $stopLat = (float)($next['latitude'] ?? 0);
    $stopLng = (float)($next['longitude'] ?? 0);
    $nextHasCoordinates = abs($stopLat) > 0.000001 && abs($stopLng) > 0.000001;

    if ($nextHasCoordinates) {
        $distanceKm = aims_distance_m(
            (float)$point['latitude'],
            (float)$point['longitude'],
            $stopLat,
            $stopLng
        ) / 1000 * 1.18;

        $speedKmh = (float)($point['speed_mps'] ?? 0) * 3.6;
        $cruise = ($speedKmh >= 35 && $speedKmh <= 110)
            ? max(55, min(90, $speedKmh * 0.4 + 68 * 0.6))
            : 68;

        $etaMin = (int)ceil($distanceKm / max(25, $cruise) * 60);
    }
}

$order = [];
if (!empty($job['order_payload_json'])) {
    $decoded = json_decode((string)$job['order_payload_json'], true);
    if (is_array($decoded)) $order = $decoded;
}

$planned = null;
if ($next) {
    $planned = (string)(
        $next['stop_type'] === 'delivery'
            ? ($order['delivery_time'] ?? '')
            : ($order['pickup_time'] ?? '')
    );
}
$planned = $planned !== '' ? $planned : null;

$buffer = null;
if ($planned && $etaMin !== null) {
    try {
        $plannedTime = new DateTimeImmutable($planned);
        $buffer = (int)floor(($plannedTime->getTimestamp() - $now->getTimestamp()) / 60) - $etaMin;
    } catch (Throwable) {
        $planned = null;
    }
}

$isLate = $buffer !== null && $buffer < 0;
$reasons = [];
$risk = 0;
$confidence = 100;

if (!$seen) {
    $risk += 18;
    $reasons[] = 'job_unseen';
}
if ($seen && !$accepted) {
    $risk += 16;
    $reasons[] = 'job_unaccepted';
}
if (!$point) {
    $risk += 35;
    $confidence -= 30;
    $reasons[] = 'gps_missing';
} elseif (!$gpsFresh) {
    $risk += 30;
    $confidence -= 20;
    $reasons[] = 'gps_stale';
}
if ($gpsAccuracy !== null && $gpsAccuracy > 80) {
    $risk += 8;
    $confidence -= 10;
    $reasons[] = 'gps_low_accuracy';
}
if ($dwell !== null && $dwell >= 60) {
    $risk += 32;
    $reasons[] = 'dwell_60';
} elseif ($dwell !== null && $dwell >= 30) {
    $risk += 20;
    $reasons[] = 'dwell_30';
} elseif ($dwell !== null && $dwell >= 15) {
    $risk += 10;
    $reasons[] = 'dwell_15';
}
if ($isLate) {
    $risk += min(35, 20 + (int)floor(abs($buffer) / 15) * 5);
    $reasons[] = 'late';
    $secondaryAction = 'signal_delay';
} elseif ($buffer !== null && $buffer < 15) {
    $risk += 14;
    $reasons[] = 'time_buffer_low';
}
if ($sequenceAnomaly) {
    $risk += 35;
    $confidence -= 15;
    $reasons[] = 'stop_sequence_anomaly';
}
if ($next && !$nextHasCoordinates) {
    $confidence -= 20;
    $reasons[] = 'next_stop_no_coordinates';
}
if ($next && !$planned) {
    $confidence -= 8;
    $reasons[] = 'schedule_missing';
}
if ($allDone) {
    $reasons[] = 'documents_pending';
}
if ($accepted && $stationaryMin !== null && $stationaryMin >= 120 && !$allDone) {
    $risk += 12;
    $reasons[] = 'long_stationary';
}

$risk = $clamp($risk, 0, 100);
$confidence = $clamp($confidence, 0, 100);

$severity = $risk >= 60 ? 'high' : ($risk >= 28 ? 'warn' : 'ok');
if ($mode === 'documents' && $severity === 'ok') $severity = 'warn';

$refreshAfterSeconds = $severity === 'high'
    ? 10
    : ($severity === 'warn' ? 15 : ($mode === 'idle' ? 60 : 25));

$dataQuality = [
    'gps' => !$point ? 'missing' : ($gpsFresh ? 'fresh' : 'stale'),
    'nextStop' => !$next ? 'none' : ($nextHasCoordinates ? 'complete' : 'partial'),
    'schedule' => $planned ? 'known' : 'missing',
];

$fingerprintSource = implode('|', [
    'R96',
    (string)$job['id'],
    $mode,
    $action,
    $secondaryAction,
    $severity,
    (string)$risk,
    (string)($next['id'] ?? 0),
    (string)($dwell ?? -1),
    (string)($buffer ?? 999999),
    implode(',', $reasons),
]);

$out = [
    'version' => 'R96',
    'mode' => $mode,
    'actionCode' => $action,
    'secondaryActionCode' => $secondaryAction,
    'severity' => $severity,
    'riskScore' => $risk,
    'confidence' => $confidence,
    'reasonCodes' => array_values(array_unique($reasons)),
    'refreshAfterSeconds' => $refreshAfterSeconds,
    'jobId' => (int)$job['id'],
    'reference' => (string)$job['reference'],
    'seen' => $seen,
    'accepted' => $accepted,
    'totalStops' => $totalStops,
    'completedStops' => $completed,
    'progressPct' => $progressPct,
    'nextStop' => $next ? [
        'id' => (int)$next['id'],
        'type' => (string)$next['stop_type'],
        'order' => (int)$next['stop_order'],
        'company' => (string)($next['company'] ?? ''),
        'address' => (string)$next['address'],
        'arrived' => !empty($next['inside_since']) || !empty($next['arrival_notified_at']),
    ] : null,
    'gpsAgeMinutes' => $gpsAge,
    'gpsAccuracyMeters' => $gpsAccuracy,
    'currentSpeedKmh' => $currentSpeedKmh,
    'stationaryMinutes' => $stationaryMin,
    'stopDwellMinutes' => $dwell,
    'distanceKm' => $distanceKm,
    'etaMinutes' => $etaMin,
    'plannedAt' => $planned,
    'timeBufferMinutes' => $buffer,
    'isLate' => $isLate,
    'sequenceAnomaly' => $sequenceAnomaly,
    'documentsRequired' => $allDone,
    'gpsFresh' => $gpsFresh,
    'dataQuality' => $dataQuality,
    'alertFingerprint' => sha1($fingerprintSource),
    'updatedAt' => $now->format(DateTimeInterface::ATOM),
];

aims_json([
    'ok' => true,
    'plate' => $plate,
    'autopilot' => $out,
]);
