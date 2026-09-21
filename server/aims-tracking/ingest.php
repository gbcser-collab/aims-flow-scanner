<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/country_stay.php';

aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$raw = file_get_contents('php://input') ?: '';
$data = json_decode($raw, true);
if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

$deviceId = trim((string)($data['deviceId'] ?? ''));
$vehicleLabel = trim((string)($data['vehicleLabel'] ?? ''));
$capturedAt = trim((string)($data['timestamp'] ?? ''));
$source = trim((string)($data['source'] ?? 'stream'));
$pointKey = trim((string)($data['pointId'] ?? ''));
$countryCode = strtoupper(trim((string)($data['countryCode'] ?? '')));
if (!preg_match('/^[A-Z]{2}$/', $countryCode)) $countryCode = '';
$lat = filter_var($data['latitude'] ?? null, FILTER_VALIDATE_FLOAT);
$lng = filter_var($data['longitude'] ?? null, FILTER_VALIDATE_FLOAT);
$accuracy = isset($data['accuracy']) ? (float)$data['accuracy'] : null;
$speedMps = isset($data['speedMps']) ? max(0.0, (float)$data['speedMps']) : null;
$delayedReplay = ($data['delayed'] ?? false) === true;

if ($deviceId === '' || strlen($deviceId) > 120 || strlen($pointKey) > 120 || $capturedAt === '' || $lat === false || $lng === false) {
    aims_json(['ok' => false, 'error' => 'invalid_payload'], 422);
}
if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
    aims_json(['ok' => false, 'error' => 'invalid_coordinates'], 422);
}

try {
    $captured = new DateTimeImmutable($capturedAt);
    $captured = $captured->setTimezone(new DateTimeZone('UTC'));
} catch (Throwable) {
    aims_json(['ok' => false, 'error' => 'invalid_timestamp'], 422);
}

function aims_active_stop_context(PDO $pdo, int $vehicleId, float $lat, float $lng, ?float $accuracy): ?array {
    $stmt = $pdo->prepare('SELECT s.*, j.reference
        FROM job_stops s
        JOIN jobs j ON j.id = s.job_id
        WHERE j.vehicle_id = :vehicle AND j.status = "active"
        ORDER BY s.stop_order ASC');
    $stmt->execute([':vehicle' => $vehicleId]);
    $nearest = null;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $stop) {
        $distance = aims_distance_m($lat, $lng, (float)$stop['latitude'], (float)$stop['longitude']);
        $radius = aims_geofence_radius_m((float)$stop['radius_m'], $accuracy);
        if ($distance <= $radius && ($nearest === null || $distance < $nearest['distance'])) {
            $stop['distance'] = $distance;
            $nearest = $stop;
        }
    }
    return $nearest;
}

function aims_process_arrivals(
    PDO $pdo,
    array $vehicle,
    float $lat,
    float $lng,
    ?float $accuracy,
    ?float $speedMps,
    DateTimeImmutable $captured,
    bool $emitNotifications = true
): int {
    $stmt = $pdo->prepare('SELECT s.*, j.reference
        FROM job_stops s
        JOIN jobs j ON j.id = s.job_id
        WHERE j.vehicle_id = :vehicle AND j.status = "active" AND s.arrival_notified_at IS NULL
        ORDER BY s.stop_order ASC');
    $stmt->execute([':vehicle' => $vehicle['id']]);
    $events = 0;

    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $stop) {
        $distance = aims_distance_m($lat, $lng, (float)$stop['latitude'], (float)$stop['longitude']);
        $radius = aims_geofence_radius_m((float)$stop['radius_m'], $accuracy);
        $inside = $distance <= $radius;

        if (!$inside) {
            if ($stop['inside_since'] !== null && $distance > $radius + 75.0) {
                $reset = $pdo->prepare('UPDATE job_stops SET inside_since = NULL WHERE id = :id AND arrival_notified_at IS NULL');
                $reset->execute([':id' => $stop['id']]);
            }
            continue;
        }

        if ($stop['inside_since'] === null) {
            $mark = $pdo->prepare('UPDATE job_stops SET inside_since = :since WHERE id = :id AND arrival_notified_at IS NULL');
            $mark->execute([':since' => $captured->format(DateTimeInterface::ATOM), ':id' => $stop['id']]);
            continue;
        }

        $insideSince = new DateTimeImmutable($stop['inside_since']);
        $dwell = $captured->getTimestamp() - $insideSince->getTimestamp();
        $slowEnough = $speedMps === null || $speedMps < 4.5;
        if ($dwell < 45 || !$slowEnough) continue;

        $update = $pdo->prepare('UPDATE job_stops
            SET arrival_notified_at = :arrived
            WHERE id = :id AND arrival_notified_at IS NULL');
        $update->execute([
            ':arrived' => $captured->format(DateTimeInterface::ATOM),
            ':id' => $stop['id'],
        ]);
        if ($update->rowCount() !== 1) continue;

        if (!$emitNotifications) continue;

        $kindHu = $stop['stop_type'] === 'pickup' ? 'felrakóra' : 'lerakóra';
        $plate = $vehicle['label'] !== '' ? $vehicle['label'] : $vehicle['plate'];
        $where = trim((string)($stop['company'] ?? ''));
        $address = trim((string)$stop['address']);
        $place = $where !== '' ? "$where • $address" : $address;
        $title = "$plate megérkezett a $kindHu";
        $body = "$place • Fuvar: {$stop['reference']}";
        aims_notify(
            $pdo,
            (int)$vehicle['admin_user_id'],
            (int)$vehicle['id'],
            'job_arrival',
            'success',
            $title,
            $body,
            "arrival:{$stop['id']}",
            [
                'jobReference' => $stop['reference'],
                'stopId' => (int)$stop['id'],
                'stopType' => $stop['stop_type'],
                'address' => $address,
                'latitude' => $lat,
                'longitude' => $lng,
                'distanceMeters' => round($distance, 1),
            ]
        );
        $events++;

    }
    return $events;
}


function aims_process_job_waiting(
    PDO $pdo,
    array $vehicle,
    float $lat,
    float $lng,
    ?float $accuracy,
    DateTimeImmutable $captured,
    bool $emitNotifications = true
): int {
    if (!$emitNotifications) return 0;

    $stmt = $pdo->prepare('SELECT s.*, j.reference, j.order_payload_json
        FROM job_stops s
        JOIN jobs j ON j.id = s.job_id
        WHERE j.vehicle_id = :vehicle
          AND j.status = "active"
          AND s.arrival_notified_at IS NOT NULL
          AND s.completed_at IS NULL
        ORDER BY j.id ASC, s.stop_order ASC');
    $stmt->execute([':vehicle' => $vehicle['id']]);

    $candidate = null;
    $candidateDistance = null;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $stop) {
        $distance = aims_distance_m(
            $lat,
            $lng,
            (float)$stop['latitude'],
            (float)$stop['longitude']
        );
        $radius = max(
            500.0,
            aims_geofence_radius_m((float)$stop['radius_m'], $accuracy) + 250.0
        );
        if ($distance > $radius) continue;
        if ($candidate === null || $distance < $candidateDistance) {
            $candidate = $stop;
            $candidateDistance = $distance;
        }
    }

    if ($candidate === null) return 0;

    try {
        $arrivedAt = new DateTimeImmutable((string)$candidate['arrival_notified_at']);
    } catch (Throwable) {
        return 0;
    }

    $pausedSeconds = max(0, (int)($candidate['waiting_paused_seconds'] ?? 0));
    $waitingSeconds = aims_effective_waiting_seconds(
        $captured->getTimestamp() - $arrivedAt->getTimestamp(),
        $pausedSeconds
    );
    $lastSlot = (int)($candidate['waiting_alert_slot'] ?? 0);
    $due = aims_due_job_waiting_slot($waitingSeconds, $lastSlot);
    if ($due === null) return 0;

    $orderData = [];
    if (!empty($candidate['order_payload_json'])) {
        $decoded = json_decode((string)$candidate['order_payload_json'], true);
        if (is_array($decoded)) $orderData = $decoded;
    }

    $referenceKeys = $candidate['stop_type'] === 'pickup'
        ? ['pickup_reference', 'customer_reference']
        : ['delivery_reference', 'customer_reference'];
    $displayReference = '';
    foreach ($referenceKeys as $key) {
        $value = trim((string)($orderData[$key] ?? ''));
        if ($value !== '') {
            $displayReference = $value;
            break;
        }
    }
    if ($displayReference === '') {
        $displayReference = trim((string)$candidate['reference']);
    }

    $minutes = (int)$due['minutes'];
    $slot = (int)$due['slot'];
    $plate = trim((string)($vehicle['label'] ?? '')) !== ''
        ? (string)$vehicle['label']
        : (string)$vehicle['plate'];
    $company = trim((string)($candidate['company'] ?? ''));
    $address = trim((string)($candidate['address'] ?? ''));
    $kind = $candidate['stop_type'] === 'pickup' ? 'felrakón' : 'lerakón';

    $title = "$plate még várakozik a $kind";
    $bodyParts = [];
    if ($company !== '') $bodyParts[] = $company;
    if ($address !== '') $bodyParts[] = $address;
    $bodyParts[] = 'Referencia: ' . $displayReference;
    $bodyParts[] = 'Várakozás: ' . $minutes . ' perc';
    $body = implode(' • ', $bodyParts);

    aims_notify(
        $pdo,
        (int)$vehicle['admin_user_id'],
        (int)$vehicle['id'],
        'job_waiting',
        $minutes >= 60 ? 'warning' : 'info',
        $title,
        $body,
        'job_waiting:' . (int)$candidate['id'] . ':' . $slot,
        [
            'jobId' => (int)$candidate['job_id'],
            'jobReference' => (string)$candidate['reference'],
            'displayReference' => $displayReference,
            'stopId' => (int)$candidate['id'],
            'stopType' => (string)$candidate['stop_type'],
            'company' => $company,
            'address' => $address,
            'arrivedAt' => $arrivedAt->format(DateTimeInterface::ATOM),
            'waitingMinutes' => $minutes,
            'latitude' => $lat,
            'longitude' => $lng,
            'accuracy' => $accuracy,
            'distanceMeters' => $candidateDistance === null
                ? null
                : round((float)$candidateDistance, 1),
        ]
    );

    $update = $pdo->prepare('UPDATE job_stops
        SET waiting_alert_slot = :slot, waiting_alert_last_at = :at
        WHERE id = :id AND waiting_alert_slot < :slot2');
    $update->execute([
        ':slot' => $slot,
        ':at' => $captured->format(DateTimeInterface::ATOM),
        ':id' => $candidate['id'],
        ':slot2' => $slot,
    ]);

    return 1;
}

function aims_process_stationary(
    PDO $pdo,
    array $vehicle,
    float $lat,
    float $lng,
    ?float $accuracy,
    ?float $speedMps,
    DateTimeImmutable $captured,
    bool $emitNotifications = true
): int {
    $stateStmt = $pdo->prepare('SELECT * FROM vehicle_state WHERE vehicle_id = :vehicle');
    $stateStmt->execute([':vehicle' => $vehicle['id']]);
    $state = $stateStmt->fetch(PDO::FETCH_ASSOC);

    if ($state === false) {
        $insert = $pdo->prepare('INSERT INTO vehicle_state
            (vehicle_id, anchor_lat, anchor_lng, anchor_accuracy, stationary_since, last_motion_at, last_point_at, alerts_mask)
            VALUES (:vehicle, :lat, :lng, :accuracy, :now, :now, :now, 0)');
        $insert->execute([
            ':vehicle' => $vehicle['id'],
            ':lat' => $lat,
            ':lng' => $lng,
            ':accuracy' => $accuracy,
            ':now' => $captured->format(DateTimeInterface::ATOM),
        ]);
        return 0;
    }

    $lastPoint = new DateTimeImmutable($state['last_point_at']);
    if ($captured <= $lastPoint) return 0;

    $moved = aims_motion_detected(
        (float)$state['anchor_lat'],
        (float)$state['anchor_lng'],
        $lat,
        $lng,
        $accuracy,
        $speedMps
    );

    if ($moved) {
        $update = $pdo->prepare('UPDATE vehicle_state
            SET anchor_lat = :lat, anchor_lng = :lng, anchor_accuracy = :accuracy,
                stationary_since = :now, last_motion_at = :now, last_point_at = :now, alerts_mask = 0
            WHERE vehicle_id = :vehicle');
        $update->execute([
            ':lat' => $lat,
            ':lng' => $lng,
            ':accuracy' => $accuracy,
            ':now' => $captured->format(DateTimeInterface::ATOM),
            ':vehicle' => $vehicle['id'],
        ]);
        return 0;
    }

    $stationarySince = new DateTimeImmutable($state['stationary_since']);
    $seconds = max(0, $captured->getTimestamp() - $stationarySince->getTimestamp());
    $mask = (int)$state['alerts_mask'];
    $due = aims_due_stop_alerts($seconds, $mask);
    $context = aims_active_stop_context($pdo, (int)$vehicle['id'], $lat, $lng, $accuracy);
    $events = 0;

    foreach ($due as $threshold) {
        if (!$emitNotifications) continue;
        $minutes = $threshold['minutes'];
        $plate = $vehicle['label'] !== '' ? $vehicle['label'] : $vehicle['plate'];
        if ($context !== null) {
            $kind = $context['stop_type'] === 'pickup' ? 'felrakón' : 'lerakón';
            $title = "$plate {$minutes} perce áll a $kind";
            $body = trim((string)($context['company'] ?? ''));
            if ($body !== '') $body .= ' • ';
            $body .= (string)$context['address'];
        } else {
            $title = "$plate {$minutes} perce nem mozdult";
            $body = 'A járműnél a rendszer nem érzékelt hiteles mozgást.';
        }

        $cycle = $stationarySince->format('Ymd\THis');
        aims_notify(
            $pdo,
            (int)$vehicle['admin_user_id'],
            (int)$vehicle['id'],
            'stationary',
            $minutes >= 60 ? 'warning' : 'info',
            $title,
            $body,
            "stationary:{$vehicle['id']}:$cycle:$minutes",
            [
                'stationaryMinutes' => $minutes,
                'stationarySince' => $stationarySince->format(DateTimeInterface::ATOM),
                'latitude' => $lat,
                'longitude' => $lng,
                'jobReference' => $context['reference'] ?? null,
                'stopType' => $context['stop_type'] ?? null,
            ]
        );
        $mask |= (int)$threshold['bit'];
        $events++;
    }

    $update = $pdo->prepare('UPDATE vehicle_state
        SET last_point_at = :now, alerts_mask = :mask
        WHERE vehicle_id = :vehicle');
    $update->execute([
        ':now' => $captured->format(DateTimeInterface::ATOM),
        ':mask' => $mask,
        ':vehicle' => $vehicle['id'],
    ]);
    return $events;
}

$pdo = aims_db();
$vehicle = aims_vehicle_for_point($pdo, $deviceId, $vehicleLabel);
$vehicleId = $vehicle === null ? null : (int)$vehicle['id'];

$pdo->beginTransaction();
try {
    $stmt = $pdo->prepare('INSERT OR IGNORE INTO points (
        point_key, device_id, vehicle_id, vehicle_label, country_code,
        captured_at, received_at, latitude, longitude, accuracy,
        speed_mps, heading, altitude, source
    ) VALUES (:point_key, :device_id, :vehicle_id, :vehicle_label, :country_code,
              :captured_at, :received_at, :latitude, :longitude, :accuracy,
              :speed_mps, :heading, :altitude, :source)');
    $stmt->execute([
        ':point_key' => $pointKey !== '' ? $pointKey : null,
        ':device_id' => $deviceId,
        ':vehicle_id' => $vehicleId,
        ':vehicle_label' => mb_substr($vehicleLabel, 0, 80),
        ':country_code' => $countryCode !== '' ? $countryCode : null,
        ':captured_at' => $captured->format(DateTimeInterface::ATOM),
        ':received_at' => gmdate(DateTimeInterface::ATOM),
        ':latitude' => (float)$lat,
        ':longitude' => (float)$lng,
        ':accuracy' => $accuracy,
        ':speed_mps' => $speedMps,
        ':heading' => isset($data['heading']) ? (float)$data['heading'] : null,
        ':altitude' => isset($data['altitude']) ? (float)$data['altitude'] : null,
        ':source' => in_array($source, ['stream', 'heartbeat'], true) ? $source : 'stream',
    ]);

    $duplicatePoint = $pointKey !== '' && $stmt->rowCount() === 0;
    $arrivalEvents = 0;
    $waitingEvents = 0;
    $stationaryEvents = 0;
    $borderEvents = 0;
    if ($vehicle !== null && !$duplicatePoint) {
        $restMode = aims_rest_mode_state(
            $pdo,
            (int)$vehicle['id'],
            $captured
        );
        $arrivalEvents = aims_process_arrivals(
            $pdo, $vehicle, (float)$lat, (float)$lng, $accuracy, $speedMps, $captured, !$delayedReplay
        );
        if (($restMode['active'] ?? false) !== true) {
            $waitingEvents = aims_process_job_waiting(
                $pdo, $vehicle, (float)$lat, (float)$lng, $accuracy, $captured, !$delayedReplay
            );
            $stationaryEvents = aims_process_stationary(
                $pdo, $vehicle, (float)$lat, (float)$lng, $accuracy, $speedMps, $captured, !$delayedReplay
            );
        }
        $borderEvents = aims_process_country_stay(
            $pdo, $vehicle, $countryCode, (float)$lat, (float)$lng, $captured, !$delayedReplay
        );
    }

    $maintenanceNow = new DateTimeImmutable('now', new DateTimeZone('UTC'));
    $maintenance = $pdo->prepare(
        'SELECT last_run FROM maintenance_state WHERE name = :name'
    );
    $maintenance->execute([':name' => 'points_cleanup']);
    $lastCleanupRaw = $maintenance->fetchColumn();
    $cleanupDue = $lastCleanupRaw === false;

    if (!$cleanupDue) {
        try {
            $lastCleanup = new DateTimeImmutable((string)$lastCleanupRaw);
            $cleanupDue =
                $maintenanceNow->getTimestamp() - $lastCleanup->getTimestamp() >= 21600;
        } catch (Throwable) {
            $cleanupDue = true;
        }
    }

    if ($cleanupDue) {
        $cutoff = $maintenanceNow
            ->modify('-60 days')
            ->format(DateTimeInterface::ATOM);
        $cleanup = $pdo->prepare(
            'DELETE FROM points WHERE received_at < :cutoff'
        );
        $cleanup->execute([':cutoff' => $cutoff]);

        $markMaintenance = $pdo->prepare(
            'INSERT INTO maintenance_state (name, last_run)
             VALUES (:name, :last_run)
             ON CONFLICT(name) DO UPDATE SET last_run = excluded.last_run'
        );
        $markMaintenance->execute([
            ':name' => 'points_cleanup',
            ':last_run' => $maintenanceNow->format(DateTimeInterface::ATOM),
        ]);
    }

    $pdo->commit();
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('AIMS tracking ingest: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}

aims_try_push($pdo, 8);

aims_json([
    'ok' => true,
    'registeredVehicle' => $vehicle !== null,
    'duplicatePoint' => $duplicatePoint,
    'arrivalEvents' => $arrivalEvents,
    'waitingEvents' => $waitingEvents,
    'stationaryEvents' => $stationaryEvents,
    'borderEvents' => $borderEvents,
    'countryCode' => $countryCode !== '' ? $countryCode : null,
    'receivedAt' => gmdate(DateTimeInterface::ATOM),
]);