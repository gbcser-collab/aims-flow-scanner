<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

aims_require_token('AIMS_ADMIN_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$pdo = aims_db();
$device = trim((string)($_GET['device'] ?? ''));
$minutes = max(10, min(1440, (int)($_GET['minutes'] ?? 180)));
$cutoff = (new DateTimeImmutable("-$minutes minutes", new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);

$latestSql = 'SELECT p.* FROM points p
              INNER JOIN (
                SELECT device_id, MAX(id) max_id FROM points GROUP BY device_id
              ) x ON x.max_id = p.id
              ORDER BY p.received_at DESC';
$latest = $pdo->query($latestSql)->fetchAll(PDO::FETCH_ASSOC);

$trail = [];
if ($device !== '') {
    $stmt = $pdo->prepare('SELECT * FROM points
                           WHERE device_id = :device AND captured_at >= :cutoff
                           ORDER BY captured_at ASC LIMIT 5000');
    $stmt->execute([':device' => $device, ':cutoff' => $cutoff]);
    $trail = $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function normalize_point(array $row): array {
    return [
        'deviceId' => $row['device_id'],
        'vehicleLabel' => $row['vehicle_label'],
        'capturedAt' => $row['captured_at'],
        'receivedAt' => $row['received_at'],
        'latitude' => (float)$row['latitude'],
        'longitude' => (float)$row['longitude'],
        'accuracy' => $row['accuracy'] === null ? null : (float)$row['accuracy'],
        'speedKmh' => $row['speed_mps'] === null ? null : max(0, (float)$row['speed_mps'] * 3.6),
        'heading' => $row['heading'] === null ? null : (float)$row['heading'],
        'altitude' => $row['altitude'] === null ? null : (float)$row['altitude'],
    ];
}

aims_json([
    'ok' => true,
    'serverTime' => gmdate(DateTimeInterface::ATOM),
    'vehicles' => array_map('normalize_point', $latest),
    'trail' => array_map('normalize_point', $trail),
]);
