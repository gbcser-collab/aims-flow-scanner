<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $stmt = $pdo->prepare('SELECT id, plate, label, device_id, enabled, created_at
                           FROM vehicles WHERE admin_user_id = :admin ORDER BY plate');
    $stmt->execute([':admin' => $adminId]);
    aims_json(['ok' => true, 'vehicles' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

    $plateDisplay = trim((string)($data['plate'] ?? ''));
    $plate = aims_normalize_plate($plateDisplay);
    $label = trim((string)($data['label'] ?? $plateDisplay));
    $deviceId = trim((string)($data['deviceId'] ?? ''));
    if (strlen($plate) < 4 || strlen($plate) > 12) aims_json(['ok' => false, 'error' => 'invalid_plate'], 422);

    $existing = $pdo->prepare('SELECT * FROM vehicles WHERE plate = :plate');
    $existing->execute([':plate' => $plate]);
    $row = $existing->fetch(PDO::FETCH_ASSOC);
    if ($row && (int)$row['admin_user_id'] !== $adminId) {
        aims_json(['ok' => false, 'error' => 'plate_owned_by_another_admin'], 409);
    }

    $stmt = $pdo->prepare('INSERT INTO vehicles (plate, label, device_id, admin_user_id, enabled, created_at)
        VALUES (:plate, :label, :device, :admin, 1, :created)
        ON CONFLICT(plate) DO UPDATE SET
            label = excluded.label,
            device_id = CASE WHEN excluded.device_id = "" THEN vehicles.device_id ELSE excluded.device_id END,
            enabled = 1');
    $stmt->execute([
        ':plate' => $plate,
        ':label' => mb_substr($label, 0, 80),
        ':device' => $deviceId === '' ? null : $deviceId,
        ':admin' => $adminId,
        ':created' => gmdate(DateTimeInterface::ATOM),
    ]);
    aims_json(['ok' => true, 'plate' => $plate, 'label' => $label]);
}

header('Allow: GET, POST');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
