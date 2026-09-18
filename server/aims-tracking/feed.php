<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$device = trim((string)($_GET['device'] ?? ''));
$minutes = max(10, min(1440, (int)($_GET['minutes'] ?? 180)));
$cutoff = (new DateTimeImmutable("-$minutes minutes", new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);

$latestStmt = $pdo->prepare('SELECT p.*, v.plate, v.label,
        s.stationary_since, s.last_motion_at, s.alerts_mask
    FROM points p
    JOIN vehicles v ON v.id = p.vehicle_id
    LEFT JOIN vehicle_state s ON s.vehicle_id = v.id
    INNER JOIN (
        SELECT p2.vehicle_id, MAX(p2.id) max_id
        FROM points p2
        JOIN vehicles v2 ON v2.id = p2.vehicle_id
        WHERE v2.admin_user_id = :admin
        GROUP BY p2.vehicle_id
    ) x ON x.max_id = p.id
    WHERE v.admin_user_id = :admin2
    ORDER BY p.received_at DESC');
$latestStmt->execute([':admin' => $adminId, ':admin2' => $adminId]);
$latest = $latestStmt->fetchAll(PDO::FETCH_ASSOC);

$trail = [];
if ($device !== '') {
    $stmt = $pdo->prepare('SELECT p.*, v.plate, v.label
        FROM points p JOIN vehicles v ON v.id = p.vehicle_id
        WHERE p.device_id = :device AND v.admin_user_id = :admin AND p.captured_at >= :cutoff
        ORDER BY p.captured_at ASC LIMIT 5000');
    $stmt->execute([':device' => $device, ':admin' => $adminId, ':cutoff' => $cutoff]);
    $trail = $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function normalize_point(array $row): array {
    return [
        'deviceId' => $row['device_id'],
        'plate' => $row['label'] !== '' ? $row['label'] : $row['plate'],
        'capturedAt' => $row['captured_at'],
        'receivedAt' => $row['received_at'],
        'latitude' => (float)$row['latitude'],
        'longitude' => (float)$row['longitude'],
        'accuracy' => $row['accuracy'] === null ? null : (float)$row['accuracy'],
        'speedKmh' => $row['speed_mps'] === null ? null : max(0, (float)$row['speed_mps'] * 3.6),
        'heading' => $row['heading'] === null ? null : (float)$row['heading'],
        'altitude' => $row['altitude'] === null ? null : (float)$row['altitude'],
        'stationarySince' => $row['stationary_since'] ?? null,
        'lastMotionAt' => $row['last_motion_at'] ?? null,
    ];
}

aims_json([
    'ok' => true,
    'serverTime' => gmdate(DateTimeInterface::ATOM),
    'vehicles' => array_map('normalize_point', $latest),
    'trail' => array_map('normalize_point', $trail),
]);
