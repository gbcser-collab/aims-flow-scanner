<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $stmt = $pdo->prepare('SELECT id, platform, device_id, app_version, enabled, created_at, updated_at
                           FROM push_devices
                           WHERE admin_user_id = :admin
                           ORDER BY updated_at DESC');
    $stmt->execute([':admin' => $adminId]);
    aims_json([
        'ok' => true,
        'serverPushConfigured' => aims_push_config() !== null,
        'devices' => $stmt->fetchAll(PDO::FETCH_ASSOC),
    ]);
}

if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

    $token = trim((string)($data['fcmToken'] ?? ''));
    $deviceId = trim((string)($data['deviceId'] ?? ''));
    $platform = strtolower(trim((string)($data['platform'] ?? 'android')));
    $appVersion = trim((string)($data['appVersion'] ?? ''));

    if (strlen($token) < 40 || strlen($token) > 4096) {
        aims_json(['ok' => false, 'error' => 'invalid_fcm_token'], 422);
    }
    if ($deviceId === '' || strlen($deviceId) > 200) {
        aims_json(['ok' => false, 'error' => 'invalid_device_id'], 422);
    }
    if (!in_array($platform, ['android', 'ios'], true)) {
        aims_json(['ok' => false, 'error' => 'invalid_platform'], 422);
    }

    $now = gmdate(DateTimeInterface::ATOM);
    $stmt = $pdo->prepare('INSERT INTO push_devices
        (admin_user_id, platform, device_id, fcm_token, app_version, enabled, created_at, updated_at)
        VALUES (:admin, :platform, :device, :token, :version, 1, :created, :updated)
        ON CONFLICT(fcm_token) DO UPDATE SET
            admin_user_id = excluded.admin_user_id,
            platform = excluded.platform,
            device_id = excluded.device_id,
            app_version = excluded.app_version,
            enabled = 1,
            updated_at = excluded.updated_at');
    $stmt->execute([
        ':admin' => $adminId,
        ':platform' => $platform,
        ':device' => mb_substr($deviceId, 0, 200),
        ':token' => $token,
        ':version' => $appVersion === '' ? null : mb_substr($appVersion, 0, 80),
        ':created' => $now,
        ':updated' => $now,
    ]);

    $find = $pdo->prepare('SELECT id FROM push_devices WHERE fcm_token = :token');
    $find->execute([':token' => $token]);
    aims_json([
        'ok' => true,
        'serverPushConfigured' => aims_push_config() !== null,
        'pushDeviceId' => (int)$find->fetchColumn(),
    ]);
}

if ($method === 'DELETE') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) $data = [];
    $token = trim((string)($data['fcmToken'] ?? ''));
    $deviceId = trim((string)($data['deviceId'] ?? ''));

    if ($token === '' && $deviceId === '') {
        aims_json(['ok' => false, 'error' => 'missing_device'], 422);
    }
    if ($token !== '') {
        $stmt = $pdo->prepare('UPDATE push_devices SET enabled = 0, updated_at = :now
                               WHERE admin_user_id = :admin AND fcm_token = :token');
        $stmt->execute([
            ':now' => gmdate(DateTimeInterface::ATOM),
            ':admin' => $adminId,
            ':token' => $token,
        ]);
    } else {
        $stmt = $pdo->prepare('UPDATE push_devices SET enabled = 0, updated_at = :now
                               WHERE admin_user_id = :admin AND device_id = :device');
        $stmt->execute([
            ':now' => gmdate(DateTimeInterface::ATOM),
            ':admin' => $adminId,
            ':device' => $deviceId,
        ]);
    }
    aims_json(['ok' => true, 'updated' => $stmt->rowCount()]);
}

header('Allow: GET, POST, DELETE');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
