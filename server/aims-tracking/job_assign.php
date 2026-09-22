<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/smart_rules.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

$plate = aims_normalize_plate((string)($data['plate'] ?? ''));
$job = $data['driverJob'] ?? $data['job'] ?? null;
if ($plate === '' || !is_array($job)) aims_json(['ok' => false, 'error' => 'invalid_payload'], 422);

$vehicleStmt = $pdo->prepare('SELECT * FROM vehicles WHERE plate = :plate AND admin_user_id = :admin AND enabled = 1');
$vehicleStmt->execute([':plate' => $plate, ':admin' => $adminId]);
$vehicle = $vehicleStmt->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok' => false, 'error' => 'vehicle_not_registered'], 404);

$reference = trim((string)($job['reference'] ?? ''));
$partialLoad = (($job['partialLoad'] ?? $job['partial'] ?? false) === true) ? 1 : 0;
$sourceOrderId = trim((string)($job['sourceOrderId'] ?? ''));
$orderData = $job['orderData'] ?? [];
if (!is_array($orderData)) $orderData = [];
if ($reference === '') aims_json(['ok' => false, 'error' => 'missing_reference'], 422);

function aims_http_get_json(string $url, array $headers): ?array {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_CONNECTTIMEOUT => 4,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS => 2,
        ]);
        $body = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if (!is_string($body) || $status < 200 || $status >= 300) return null;
        $decoded = json_decode($body, true);
        return is_array($decoded) ? $decoded : null;
    }

    $context = stream_context_create([
        'http' => [
            'timeout' => 8,
            'header' => implode("\r\n", $headers),
        ],
    ]);
    $body = @file_get_contents($url, false, $context);
    if (!is_string($body)) return null;
    $decoded = json_decode($body, true);
    return is_array($decoded) ? $decoded : null;
}

function aims_geocode(PDO $pdo, string $address): ?array {
    $address = trim($address);
    if ($address === '') return null;
    $hash = hash('sha256', mb_strtolower($address, 'UTF-8'));

    $cache = $pdo->prepare('SELECT * FROM geocode_cache WHERE address_hash = :hash');
    $cache->execute([':hash' => $hash]);
    $row = $cache->fetch(PDO::FETCH_ASSOC);
    if ($row && $row['status'] === 'ok') {
        return ['latitude' => (float)$row['latitude'], 'longitude' => (float)$row['longitude']];
    }

    $base = rtrim(getenv('AIMS_GEOCODER_URL') ?: 'https://nominatim.openstreetmap.org/search', '?');
    $lat = null;
    $lng = null;

    foreach (aims_geocode_address_candidates($address) as $candidate) {
        $url = $base . '?' . http_build_query([
            'q' => $candidate,
            'format' => 'jsonv2',
            'limit' => 1,
            'addressdetails' => 0,
        ]);
        $result = aims_http_get_json($url, [
            'Accept: application/json',
            'User-Agent: AIMS-Flow/1.3 (logistic-aims.hu)',
        ]);

        if (is_array($result) && isset($result[0]['lat'], $result[0]['lon'])) {
            $lat = (float)$result[0]['lat'];
            $lng = (float)$result[0]['lon'];
            break;
        }
    }

    $save = $pdo->prepare('INSERT INTO geocode_cache
        (address_hash, address, latitude, longitude, status, updated_at)
        VALUES (:hash, :address, :lat, :lng, :status, :updated)
        ON CONFLICT(address_hash) DO UPDATE SET
            latitude = excluded.latitude,
            longitude = excluded.longitude,
            status = excluded.status,
            updated_at = excluded.updated_at');
    $save->execute([
        ':hash' => $hash,
        ':address' => $address,
        ':lat' => $lat,
        ':lng' => $lng,
        ':status' => $lat === null ? 'not_found' : 'ok',
        ':updated' => gmdate(DateTimeInterface::ATOM),
    ]);

    return $lat === null ? null : ['latitude' => $lat, 'longitude' => $lng];
}

$rawStops = [];
foreach (['pickups' => 'pickup', 'deliveries' => 'delivery'] as $key => $type) {
    foreach ((array)($job[$key] ?? []) as $index => $stop) {
        if (!is_array($stop)) continue;
        $address = trim((string)($stop['address'] ?? ''));
        if ($address === '') continue;
        $rawStops[] = [
            'type' => $type,
            'order' => count($rawStops) + 1,
            'company' => trim((string)($stop['company'] ?? '')),
            'address' => $address,
            'phone' => trim((string)($stop['phone'] ?? $stop['contactPhone'] ?? '')),
            'latitude' => isset($stop['latitude']) ? (float)$stop['latitude'] : null,
            'longitude' => isset($stop['longitude']) ? (float)$stop['longitude'] : null,
            'radius' => isset($stop['radiusMeters']) ? max(80.0, min(500.0, (float)$stop['radiusMeters'])) : 180.0,
        ];
    }
}
if (!$rawStops) aims_json(['ok' => false, 'error' => 'no_stops'], 422);

$resolved = [];
$geocodeWarnings = [];
foreach ($rawStops as $stop) {
    $lat = $stop['latitude'];
    $lng = $stop['longitude'];
    $validProvided = $lat !== null && $lng !== null
        && $lat >= -90 && $lat <= 90
        && $lng >= -180 && $lng <= 180;

    if (!$validProvided) {
        $geo = aims_geocode($pdo, $stop['address']);
        if ($geo !== null) {
            $lat = $geo['latitude'];
            $lng = $geo['longitude'];
        } else {
            $lat = null;
            $lng = null;
            $geocodeWarnings[] = [
                'address' => $stop['address'],
                'warning' => 'geocode_unavailable_address_navigation_only',
            ];
        }
    }

    $stop['latitude'] = $lat;
    $stop['longitude'] = $lng;
    $resolved[] = $stop;
}

$now = gmdate(DateTimeInterface::ATOM);
$createdNew = false;
$duplicateAssignment = false;
$pdo->beginTransaction();
try {
    if ($sourceOrderId !== '') {
        $existing = $pdo->prepare('SELECT id FROM jobs WHERE source_order_id = :sourceOrder AND vehicle_id = :vehicle ORDER BY id DESC LIMIT 1');
        $existing->execute([':sourceOrder' => $sourceOrderId, ':vehicle' => $vehicle['id']]);
    } else {
        $existing = $pdo->prepare('SELECT id FROM jobs WHERE reference = :reference AND vehicle_id = :vehicle ORDER BY id DESC LIMIT 1');
        $existing->execute([':reference' => $reference, ':vehicle' => $vehicle['id']]);
    }
    $jobId = $existing->fetchColumn();
    $orderJson = $orderData ? json_encode($orderData, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null;

    if ($jobId === false) {
        $insert = $pdo->prepare('INSERT INTO jobs (reference, vehicle_id, status, created_at, updated_at, partial_load, source_order_id, order_payload_json)
                                 VALUES (:reference, :vehicle, "active", :created, :updated, :partial, :sourceOrder, :orderJson)');
        $insert->execute([
            ':reference' => $reference,
            ':vehicle' => $vehicle['id'],
            ':created' => $now,
            ':updated' => $now,
            ':partial' => $partialLoad,
            ':sourceOrder' => $sourceOrderId !== '' ? $sourceOrderId : null,
            ':orderJson' => $orderJson,
        ]);
        $jobId = (int)$pdo->lastInsertId();
        $createdNew = true;

        $insertStop = $pdo->prepare('INSERT INTO job_stops
            (job_id, stop_type, stop_order, company, address, contact_phone, latitude, longitude, radius_m, created_at)
            VALUES (:job, :type, :ord, :company, :address, :phone, :lat, :lng, :radius, :created)');
        foreach ($resolved as $stop) {
            $insertStop->execute([
                ':job' => $jobId,
                ':type' => $stop['type'],
                ':ord' => $stop['order'],
                ':company' => $stop['company'],
                ':address' => $stop['address'],
                ':phone' => $stop['phone'],
                ':lat' => $stop['latitude'],
                ':lng' => $stop['longitude'],
                ':radius' => $stop['radius'],
                ':created' => $now,
            ]);
        }

        aims_notify(
            $pdo,
            $adminId,
            (int)$vehicle['id'],
            'job_registered',
            'info',
            ($vehicle['label'] !== '' ? $vehicle['label'] : $vehicle['plate']) . ' új fuvar',
            "$reference • " . count($resolved) . ' megálló figyelése aktív',
            "job_registered:$jobId",
            ['jobId' => $jobId, 'reference' => $reference, 'stopCount' => count($resolved)]
        );
    } else {
        // Idempotency is intentional: a repeated click/send for the same
        // source order or reference must never reset SEEN/ACCEPTED state,
        // recreate stops, or erase driver progress.
        $jobId = (int)$jobId;
        $duplicateAssignment = true;
    }

    $pdo->commit();
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('AIMS job assign: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}

aims_try_push($pdo, 8);
$driverPush = $createdNew
    ? aims_send_driver_job_push($pdo, (int)$jobId)
    : ['configured' => true, 'sent' => 0, 'failed' => 0, 'skipped' => 'duplicate_assignment'];

aims_json([
    'ok' => true,
    'jobId' => $jobId,
    'reference' => $reference,
    'plate' => $plate,
    'stops' => $resolved,
    'geocodeWarnings' => $geocodeWarnings,
    'created' => $createdNew,
    'duplicate' => $duplicateAssignment,
    'driverPush' => $driverPush,
]);
