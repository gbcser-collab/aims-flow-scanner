<?php
declare(strict_types=1);

require_once __DIR__ . '/../inc/analytics.php';
aims_require_admin();
aims_start_session();
require_once __DIR__ . '/../inc/portal.php';
require_once __DIR__ . '/../api/aims-tracking/bootstrap.php';

$pdo = aims_db();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $plate = aims_normalize_plate((string)($_GET['plate'] ?? ''));
    $after = max(0, (int)($_GET['after'] ?? 0));

    $sql = 'SELECT m.id, m.sender, m.body, m.created_at, m.read_at,
                   v.plate, v.label
            FROM driver_messages m
            JOIN vehicles v ON v.id = m.vehicle_id
            WHERE m.id > :after';
    $params = [':after' => $after];

    if ($plate !== '') {
        $sql .= ' AND v.plate = :plate';
        $params[':plate'] = $plate;
    }
    $sql .= ' ORDER BY m.id ASC LIMIT 200';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    $messages = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $messages[] = [
            'id' => (int)$row['id'],
            'sender' => (string)$row['sender'],
            'body' => (string)$row['body'],
            'plate' => (string)$row['plate'],
            'label' => trim((string)$row['label']) !== '' ? (string)$row['label'] : (string)$row['plate'],
            'createdAt' => (string)$row['created_at'],
            'readAt' => $row['read_at'] === null ? null : (string)$row['read_at'],
        ];
    }

    if ($messages) {
        $ids = array_column($messages, 'id');
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $mark = $pdo->prepare("UPDATE driver_messages
                               SET read_at = ?
                               WHERE sender = 'driver'
                                 AND read_at IS NULL
                                 AND id IN ($placeholders)");
        $mark->execute(array_merge([gmdate(DateTimeInterface::ATOM)], $ids));
    }

    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(['ok' => true, 'messages' => $messages], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($method === 'POST') {
    $expected = aims_admin_csrf();
    $provided = trim((string)($_SERVER['HTTP_X_AIMS_CSRF'] ?? ''));
    if ($provided === '' || !hash_equals($expected, $provided)) {
        http_response_code(403);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'csrf_failed']);
        exit;
    }

    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) {
        http_response_code(400);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'invalid_json']);
        exit;
    }

    $plate = aims_normalize_plate((string)($data['plate'] ?? ''));
    $message = trim((string)($data['message'] ?? ''));
    if ($plate === '' || $message === '') {
        http_response_code(422);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'invalid_payload']);
        exit;
    }
    if (mb_strlen($message) > 1000) {
        http_response_code(422);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'message_too_long']);
        exit;
    }

    $stmt = $pdo->prepare('SELECT * FROM vehicles WHERE plate = :plate AND enabled = 1 LIMIT 1');
    $stmt->execute([':plate' => $plate]);
    $vehicle = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$vehicle) {
        http_response_code(404);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'vehicle_not_registered']);
        exit;
    }

    $now = gmdate(DateTimeInterface::ATOM);
    $insert = $pdo->prepare('INSERT INTO driver_messages
        (vehicle_id, admin_user_id, sender, body, created_at)
        VALUES (:vehicle, :admin, "admin", :body, :created)');
    $insert->execute([
        ':vehicle' => (int)$vehicle['id'],
        ':admin' => (int)$vehicle['admin_user_id'],
        ':body' => $message,
        ':created' => $now,
    ]);
    $id = (int)$pdo->lastInsertId();

    $push = aims_send_driver_direct_push(
        $pdo,
        (int)$vehicle['id'],
        'Főnökség · új üzenet',
        $message,
        [
            'type' => 'admin_message',
            'messageId' => $id,
            'plate' => $plate,
            'message' => $message,
        ]
    );

    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode([
        'ok' => true,
        'message' => [
            'id' => $id,
            'sender' => 'admin',
            'body' => $message,
            'plate' => $plate,
            'createdAt' => $now,
            'readAt' => null,
        ],
        'push' => $push,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

header('Allow: GET, POST');
http_response_code(405);
header('Content-Type: application/json; charset=utf-8');
echo json_encode(['ok' => false, 'error' => 'method_not_allowed']);
