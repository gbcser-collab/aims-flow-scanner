<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

aims_require_token('AIMS_TRACKING_TOKEN');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if (!in_array($method, ['GET', 'POST'], true)) {
    header('Allow: GET, POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = [];
if ($method === 'POST') {
    $decoded = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($decoded)) {
        aims_json(['ok' => false, 'error' => 'invalid_json'], 400);
    }
    $data = $decoded;
}

$plate = aims_normalize_plate((string)(
    $method === 'POST'
        ? ($data['plate'] ?? '')
        : ($_GET['plate'] ?? '')
));
if ($plate === '') {
    aims_json(['ok' => false, 'error' => 'invalid_plate'], 422);
}

$pdo = aims_db();
$stmt = $pdo->prepare('SELECT * FROM vehicles
    WHERE plate = :plate AND enabled = 1 LIMIT 1');
$stmt->execute([':plate' => $plate]);
$vehicle = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) {
    aims_json(['ok' => false, 'error' => 'vehicle_not_registered'], 404);
}

$vehicleId = (int)$vehicle['id'];
$now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

if ($method === 'GET') {
    $state = aims_rest_mode_state($pdo, $vehicleId, $now);
    aims_json(['ok' => true, 'restMode' => $state]);
}

$enabled = ($data['enabled'] ?? false) === true;

$pdo->beginTransaction();
try {
    $state = aims_rest_mode_state($pdo, $vehicleId, $now);

    if ($enabled) {
        $minutes = (int)($data['durationMinutes'] ?? 540);
        $minutes = max(15, min(720, $minutes));
        $until = $now->modify('+' . $minutes . ' minutes');

        if (($state['active'] ?? false) !== true) {
            $pause = $pdo->prepare('UPDATE job_stops
                SET waiting_pause_started_at = :started
                WHERE id IN (
                    SELECT s.id
                    FROM job_stops s
                    JOIN jobs j ON j.id = s.job_id
                    WHERE j.vehicle_id = :vehicle
                      AND j.status = "active"
                      AND s.arrival_notified_at IS NOT NULL
                      AND s.completed_at IS NULL
                      AND s.waiting_pause_started_at IS NULL
                )');
            $pause->execute([
                ':started' => $now->format(DateTimeInterface::ATOM),
                ':vehicle' => $vehicleId,
            ]);
        }

        $update = $pdo->prepare('UPDATE vehicles
            SET rest_mode_started_at = COALESCE(rest_mode_started_at, :started),
                rest_mode_until = :until
            WHERE id = :vehicle');
        $update->execute([
            ':started' => $now->format(DateTimeInterface::ATOM),
            ':until' => $until->format(DateTimeInterface::ATOM),
            ':vehicle' => $vehicleId,
        ]);

        $pdo->commit();
        aims_json([
            'ok' => true,
            'restMode' => [
                'active' => true,
                'startedAt' => ($state['active'] ?? false)
                    ? $state['startedAt']
                    : $now->format(DateTimeInterface::ATOM),
                'until' => $until->format(DateTimeInterface::ATOM),
            ],
        ]);
    }

    if (($state['active'] ?? false) === true) {
        aims_finalize_rest_pause($pdo, $vehicleId, $now);
    }

    $clear = $pdo->prepare('UPDATE vehicles
        SET rest_mode_started_at = NULL, rest_mode_until = NULL
        WHERE id = :vehicle');
    $clear->execute([':vehicle' => $vehicleId]);

    $pdo->commit();
    aims_json([
        'ok' => true,
        'restMode' => [
            'active' => false,
            'startedAt' => null,
            'until' => null,
        ],
    ]);
} catch (Throwable $error) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('AIMS rest mode: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}
