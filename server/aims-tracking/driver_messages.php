<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

aims_require_token('AIMS_TRACKING_TOKEN');

$pdo = aims_db();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$plate = aims_normalize_plate((string)($_GET['plate'] ?? ''));

if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);
    $plate = aims_normalize_plate((string)($data['plate'] ?? ''));
}

if ($plate === '') aims_json(['ok' => false, 'error' => 'invalid_plate'], 422);

$stmt = $pdo->prepare('SELECT * FROM vehicles WHERE plate = :plate AND enabled = 1 LIMIT 1');
$stmt->execute([':plate' => $plate]);
$vehicle = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok' => false, 'error' => 'vehicle_not_registered'], 404);

$vehicleId = (int)$vehicle['id'];
$adminId = (int)$vehicle['admin_user_id'];

if ($method === 'GET') {
    $after = max(0, (int)($_GET['after'] ?? 0));
    $stmt = $pdo->prepare('SELECT id, sender, body, created_at, read_at
                           FROM driver_messages
                           WHERE vehicle_id = :vehicle AND id > :after
                           ORDER BY id ASC
                           LIMIT 100');
    $stmt->execute([
        ':vehicle' => $vehicleId,
        ':after' => $after,
    ]);

    $messages = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $messages[] = [
            'id' => (int)$row['id'],
            'sender' => (string)$row['sender'],
            'body' => (string)$row['body'],
            'createdAt' => (string)$row['created_at'],
            'readAt' => $row['read_at'] === null ? null : (string)$row['read_at'],
        ];
    }

    if ($messages) {
        $lastId = (int)$messages[count($messages) - 1]['id'];
        $mark = $pdo->prepare('UPDATE driver_messages
                              SET read_at = :now
                              WHERE vehicle_id = :vehicle
                                AND sender = "admin"
                                AND read_at IS NULL
                                AND id <= :last');
        $mark->execute([
            ':now' => gmdate(DateTimeInterface::ATOM),
            ':vehicle' => $vehicleId,
            ':last' => $lastId,
        ]);
    }

    aims_json([
        'ok' => true,
        'plate' => $plate,
        'messages' => $messages,
    ]);
}

if ($method === 'POST') {
    $message = trim((string)($data['message'] ?? ''));
    $clientMessageId = trim((string)($data['clientMessageId'] ?? ''));
    if ($message === '') aims_json(['ok' => false, 'error' => 'message_required'], 422);
    if (mb_strlen($message) > 1000) {
        aims_json(['ok' => false, 'error' => 'message_too_long'], 422);
    }
    if ($clientMessageId !== '' && preg_match('/^[A-Za-z0-9._:-]{1,180}$/', $clientMessageId) !== 1) {
        aims_json(['ok' => false, 'error' => 'invalid_client_message_id'], 422);
    }

    $now = gmdate(DateTimeInterface::ATOM);
    $created = false;
    $id = 0;
    $createdAt = $now;
    $storedBody = $message;

    if ($clientMessageId !== '') {
        $insert = $pdo->prepare('INSERT OR IGNORE INTO driver_messages
            (vehicle_id, admin_user_id, sender, body, created_at, client_message_id)
            VALUES (:vehicle, :admin, "driver", :body, :created, :client)');
        $insert->execute([
            ':vehicle' => $vehicleId,
            ':admin' => $adminId,
            ':body' => $message,
            ':created' => $now,
            ':client' => $clientMessageId,
        ]);
        $created = $insert->rowCount() === 1;
        if ($created) {
            $id = (int)$pdo->lastInsertId();
        } else {
            $existing = $pdo->prepare('SELECT id, body, created_at
                FROM driver_messages
                WHERE vehicle_id = :vehicle AND client_message_id = :client
                LIMIT 1');
            $existing->execute([
                ':vehicle' => $vehicleId,
                ':client' => $clientMessageId,
            ]);
            $row = $existing->fetch(PDO::FETCH_ASSOC);
            if (!$row) aims_json(['ok' => false, 'error' => 'message_dedupe_lookup_failed'], 500);
            if (!hash_equals((string)$row['body'], $message)) {
                aims_json(['ok' => false, 'error' => 'client_message_id_conflict'], 409);
            }
            $id = (int)$row['id'];
            $storedBody = (string)$row['body'];
            $createdAt = (string)$row['created_at'];
        }
    } else {
        $insert = $pdo->prepare('INSERT INTO driver_messages
            (vehicle_id, admin_user_id, sender, body, created_at)
            VALUES (:vehicle, :admin, "driver", :body, :created)');
        $insert->execute([
            ':vehicle' => $vehicleId,
            ':admin' => $adminId,
            ':body' => $message,
            ':created' => $now,
        ]);
        $id = (int)$pdo->lastInsertId();
        $created = true;
    }

    if ($created) {
        $label = trim((string)$vehicle['label']) !== ''
            ? trim((string)$vehicle['label'])
            : $plate;

        aims_notify(
            $pdo,
            $adminId,
            $vehicleId,
            'driver_message',
            'info',
            $label . ' · üzenet',
            $storedBody,
            'driver_message:' . $vehicleId . ':' . $id,
            [
                'messageId' => $id,
                'clientMessageId' => $clientMessageId !== '' ? $clientMessageId : null,
                'plate' => $plate,
                'message' => $storedBody,
                'type' => 'driver_message',
            ]
        );
        aims_try_push($pdo, 12);
    }

    aims_json([
        'ok' => true,
        'deduplicated' => !$created,
        'message' => [
            'id' => $id,
            'sender' => 'driver',
            'body' => $storedBody,
            'createdAt' => $createdAt,
            'readAt' => null,
        ],
    ]);
}

header('Allow: GET, POST');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
