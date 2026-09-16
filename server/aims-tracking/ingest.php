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
$lat = filter_var($data['latitude'] ?? null, FILTER_VALIDATE_FLOAT);
$lng = filter_var($data['longitude'] ?? null, FILTER_VALIDATE_FLOAT);

if ($deviceId === '' || strlen($deviceId) > 120 || $capturedAt === '' || $lat === false || $lng === false) {
    aims_json(['ok' => false, 'error' => 'invalid_payload'], 422);
}
if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
    aims_json(['ok' => false, 'error' => 'invalid_coordinates'], 422);
}

try {
    $captured = new DateTimeImmutable($capturedAt);
} catch (Throwable) {
    aims_json(['ok' => false, 'error' => 'invalid_timestamp'], 422);
}

$pdo = aims_db();
$stmt = $pdo->prepare('INSERT INTO points (
    device_id, vehicle_label, captured_at, received_at,
    latitude, longitude, accuracy, speed_mps, heading, altitude
) VALUES (:device_id, :vehicle_label, :captured_at, :received_at,
          :latitude, :longitude, :accuracy, :speed_mps, :heading, :altitude)');
$stmt->execute([
    ':device_id' => $deviceId,
    ':vehicle_label' => mb_substr($vehicleLabel, 0, 80),
    ':captured_at' => $captured->setTimezone(new DateTimeZone('UTC'))->format(DateTimeInterface::ATOM),
    ':received_at' => gmdate(DateTimeInterface::ATOM),
    ':latitude' => (float)$lat,
    ':longitude' => (float)$lng,
    ':accuracy' => isset($data['accuracy']) ? (float)$data['accuracy'] : null,
    ':speed_mps' => isset($data['speedMps']) ? (float)$data['speedMps'] : null,
    ':heading' => isset($data['heading']) ? (float)$data['heading'] : null,
    ':altitude' => isset($data['altitude']) ? (float)$data['altitude'] : null,
]);

// Lightweight retention: keep at most 60 days of raw points.
$cutoff = (new DateTimeImmutable('-60 days', new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);
$cleanup = $pdo->prepare('DELETE FROM points WHERE received_at < :cutoff');
$cleanup->execute([':cutoff' => $cutoff]);

aims_json(['ok' => true, 'receivedAt' => gmdate(DateTimeInterface::ATOM)]);
