<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

header('Cache-Control: no-store, private, max-age=0');
header('Pragma: no-cache');
header('Referrer-Policy: no-referrer');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$token = strtolower(trim((string)($_GET['t'] ?? '')));
if (preg_match('/^[a-f0-9]{64}$/', $token) !== 1) {
    aims_json(['ok' => false, 'error' => 'link_unavailable'], 404);
}

$pdo = aims_db();
$hash = hash('sha256', $token);
$stmt = $pdo->prepare('SELECT j.*, v.id AS vehicle_id, v.plate, v.label
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.customer_tracking_token_hash = :hash
      AND COALESCE(j.status, "") <> "deleted"
    LIMIT 1');
$stmt->execute([':hash' => $hash]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$job) aims_json(['ok' => false, 'error' => 'link_unavailable'], 404);

$expires = strtotime((string)($job['customer_tracking_expires_at'] ?? ''));
if (!$expires || $expires <= time()) {
    aims_json(['ok' => false, 'error' => 'link_expired'], 410);
}

$now = gmdate(DateTimeInterface::ATOM);
$lastView = strtotime((string)($job['customer_tracking_last_view_at'] ?? ''));
if (!$lastView || time() - $lastView >= 60) {
    $touch = $pdo->prepare('UPDATE jobs SET customer_tracking_last_view_at = :viewed WHERE id = :job');
    $touch->execute([':viewed' => $now, ':job' => $job['id']]);
}

$stopsStmt = $pdo->prepare('SELECT *
    FROM job_stops
    WHERE job_id = :job
    ORDER BY stop_order ASC, id ASC');
$stopsStmt->execute([':job' => $job['id']]);
$stopRows = $stopsStmt->fetchAll(PDO::FETCH_ASSOC);

$pointStmt = $pdo->prepare('SELECT *
    FROM points
    WHERE vehicle_id = :vehicle
    ORDER BY id DESC
    LIMIT 1');
$pointStmt->execute([':vehicle' => $job['vehicle_id']]);
$point = $pointStmt->fetch(PDO::FETCH_ASSOC) ?: null;

function aims_customer_haversine_km(float $lat1, float $lon1, float $lat2, float $lon2): float {
    $earth = 6371.0088;
    $phi1 = deg2rad($lat1);
    $phi2 = deg2rad($lat2);
    $dPhi = deg2rad($lat2 - $lat1);
    $dLambda = deg2rad($lon2 - $lon1);
    $a = sin($dPhi / 2) ** 2 + cos($phi1) * cos($phi2) * sin($dLambda / 2) ** 2;
    return $earth * 2 * atan2(sqrt($a), sqrt(max(0.0, 1.0 - $a)));
}

$stops = [];
$nextStop = null;
foreach ($stopRows as $row) {
    $completed = !empty($row['completed_at']);
    $arrived = !empty($row['arrival_notified_at']);
    $item = [
        'id' => (int)$row['id'],
        'type' => (string)$row['stop_type'],
        'order' => (int)$row['stop_order'],
        'company' => (string)($row['company'] ?? ''),
        'address' => (string)$row['address'],
        'latitude' => $row['latitude'] === null ? null : (float)$row['latitude'],
        'longitude' => $row['longitude'] === null ? null : (float)$row['longitude'],
        'arrived' => $arrived,
        'arrivedAt' => $row['arrival_notified_at'] ?: null,
        'completed' => $completed,
        'completedAt' => $row['completed_at'] ?: null,
    ];
    if ($nextStop === null && !$completed) $nextStop = $item;
    $stops[] = $item;
}

$gps = null;
$eta = null;
if ($point) {
    $capturedTs = strtotime((string)$point['captured_at']);
    $ageSeconds = $capturedTs ? max(0, time() - $capturedTs) : null;
    $speedKmh = $point['speed_mps'] === null ? null : max(0.0, (float)$point['speed_mps'] * 3.6);
    $gps = [
        'latitude' => (float)$point['latitude'],
        'longitude' => (float)$point['longitude'],
        'capturedAt' => (string)$point['captured_at'],
        'ageSeconds' => $ageSeconds,
        'fresh' => $ageSeconds !== null && $ageSeconds <= 600,
        'speedKmh' => $speedKmh,
        'heading' => $point['heading'] === null ? null : (float)$point['heading'],
    ];

    if ($nextStop !== null && $nextStop['latitude'] !== null && $nextStop['longitude'] !== null && $gps['fresh']) {
        $airKm = aims_customer_haversine_km(
            (float)$point['latitude'],
            (float)$point['longitude'],
            (float)$nextStop['latitude'],
            (float)$nextStop['longitude']
        );
        $routeEstimateKm = $airKm * 1.22;
        $cruiseKmh = ($speedKmh !== null && $speedKmh >= 15.0)
            ? max(35.0, min(90.0, $speedKmh))
            : 65.0;
        $minutes = $airKm < 0.2 ? 0 : (int)ceil(($routeEstimateKm / $cruiseKmh) * 60);
        $eta = [
            'minutes' => $minutes,
            'distanceKm' => round($routeEstimateKm, 1),
            'source' => 'live_gps_distance_estimate',
            'trafficAware' => false,
            'nextStopOrder' => $nextStop['order'],
        ];
    }
}

$orderData = [];
if (!empty($job['order_payload_json'])) {
    $decoded = json_decode((string)$job['order_payload_json'], true);
    if (is_array($decoded)) $orderData = $decoded;
}
$publicOrder = [];
foreach ([
    'customer','pickup_company','pickup_address','pickup_time',
    'delivery_company','delivery_address','delivery_time',
    'cargo','package_count','weight_kg','dimensions','special_requirements'
] as $key) {
    if (isset($orderData[$key]) && trim((string)$orderData[$key]) !== '') {
        $publicOrder[$key] = is_scalar($orderData[$key]) ? (string)$orderData[$key] : '';
    }
}

$timeline = [];
$addTimeline = static function(array &$timeline, ?string $at, string $type, string $label): void {
    if (!$at) return;
    $timeline[] = ['at' => $at, 'type' => $type, 'label' => $label];
};
$addTimeline($timeline, $job['created_at'] ?? null, 'created', 'Fuvar létrehozva');
$addTimeline($timeline, $job['driver_seen_at'] ?? null, 'driver_seen', 'Sofőr megnyitotta a fuvarfeladatot');
$addTimeline($timeline, $job['driver_accepted_at'] ?? null, 'driver_accepted', 'Sofőr elfogadta a fuvarfeladatot');
foreach ($stops as $stop) {
    $kind = $stop['type'] === 'pickup' ? 'felrakó' : 'lerakó';
    $addTimeline($timeline, $stop['arrivedAt'], 'arrival', ucfirst($kind) . ' érkezés · ' . ($stop['company'] ?: $stop['address']));
    $addTimeline($timeline, $stop['completedAt'], 'completed_stop', ucfirst($kind) . ' kész · ' . ($stop['company'] ?: $stop['address']));
}
$addTimeline($timeline, $job['document_received_at'] ?? null, 'document', 'CMR / fuvarokmány rögzítve');
if (($job['status'] ?? '') === 'completed') {
    $addTimeline($timeline, $job['updated_at'] ?? null, 'completed', 'Fuvar teljesítve');
}
usort($timeline, static function(array $a, array $b): int {
    return strcmp((string)$a['at'], (string)$b['at']);
});

$completedStops = count(array_filter($stops, static fn(array $s): bool => $s['completed']));
$stage = 'assigned';
if (!empty($job['driver_accepted_at'])) $stage = 'accepted';
if ($completedStops > 0) $stage = 'in_transit';
if ($nextStop === null && count($stops) > 0) $stage = 'delivered';
if (($job['status'] ?? '') === 'completed') $stage = 'completed';

aims_json([
    'ok' => true,
    'serverTime' => $now,
    'expiresAt' => $job['customer_tracking_expires_at'],
    'shipment' => [
        'jobId' => (int)$job['id'],
        'reference' => (string)$job['reference'],
        'status' => (string)$job['status'],
        'stage' => $stage,
        'partialLoad' => (int)($job['partial_load'] ?? 0) === 1,
        'vehicle' => trim((string)$job['label']) !== '' ? (string)$job['label'] : (string)$job['plate'],
        'createdAt' => (string)$job['created_at'],
        'updatedAt' => (string)$job['updated_at'],
        'order' => $publicOrder,
        'stops' => $stops,
        'nextStop' => $nextStop,
        'gps' => $gps,
        'eta' => $eta,
        'document' => [
            'received' => !empty($job['document_received_at']),
            'receivedAt' => $job['document_received_at'] ?: null,
            'syncState' => $job['document_sync_state'] ?: null,
        ],
        'timeline' => $timeline,
    ],
]);
