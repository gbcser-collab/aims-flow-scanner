<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

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
$lat = filter_var($data['latitude'] ?? null, FILTER_VALIDATE_FLOAT);
$lng = filter_var($data['longitude'] ?? null, FILTER_VALIDATE_FLOAT);
$accuracy = isset($data['accuracy']) ? (float)$data['accuracy'] : null;
$speedMps = isset($data['speedMps']) ? max(0.0, (float)$data['speedMps']) : null;

if ($deviceId === '' || strlen($deviceId) > 120 || $capturedAt === '' || $lat === false || $lng === false) {
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
    DateTimeImmutable $captured
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

        $remaining = $pdo->prepare('SELECT COUNT(*) FROM job_stops WHERE job_id = :job AND arrival_notified_at IS NULL');
        $remaining->execute([':job' => $stop['job_id']]);
        if ((int)$remaining->fetchColumn() === 0) {
            $done = $pdo->prepare('UPDATE jobs SET status = "completed", updated_at = :updated WHERE id = :id');
            $done->execute([':updated' => gmdate(DateTimeInterface::ATOM), ':id' => $stop['job_id']]);
        }
    }
    return $events;
}

function aims_process_stationary(
    PDO $pdo,
    array $vehicle,
    float $lat,
    float $lng,
    ?float $accuracy,
    ?float $speedMps,
    DateTimeImmutable $captured
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
    $stmt = $pdo->prepare('INSERT INTO points (
        device_id, vehicle_id, vehicle_label, captured_at, received_at,
        latitude, longitude, accuracy, speed_mps, heading, altitude, source
    ) VALUES (:device_id, :vehicle_id, :vehicle_label, :captured_at, :received_at,
              :latitude, :longitude, :accuracy, :speed_mps, :heading, :altitude, :source)');
    $stmt->execute([
        ':device_id' => $deviceId,
        ':vehicle_id' => $vehicleId,
        ':vehicle_label' => mb_substr($vehicleLabel, 0, 80),
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

    $arrivalEvents = 0;
    $stationaryEvents = 0;
    if ($vehicle !== null) {
        $arrivalEvents = aims_process_arrivals($pdo, $vehicle, (float)$lat, (float)$lng, $accuracy, $speedMps, $captured);
        $stationaryEvents = aims_process_stationary($pdo, $vehicle, (float)$lat, (float)$lng, $accuracy, $speedMps, $captured);
    }

    $cutoff = (new DateTimeImmutable('-60 days', new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);
    $cleanup = $pdo->prepare('DELETE FROM points WHERE received_at < :cutoff');
    $cleanup->execute([':cutoff' => $cutoff]);

    $pdo->commit();
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('AIMS tracking ingest: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}

aims_json([
    'ok' => true,
    'registeredVehicle' => $vehicle !== null,
    'arrivalEvents' => $arrivalEvents,
    'stationaryEvents' => $stationaryEvents,
    'receivedAt' => gmdate(DateTimeInterface::ATOM),
]);
