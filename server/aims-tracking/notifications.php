<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $unreadOnly = ($_GET['unread'] ?? '0') === '1';
    $after = max(0, (int)($_GET['after'] ?? 0));
    $sql = 'SELECT n.*, v.plate, v.label
            FROM notifications n
            LEFT JOIN vehicles v ON v.id = n.vehicle_id
            WHERE n.admin_user_id = :admin AND n.id > :after';
    if ($unreadOnly) $sql .= ' AND n.read_at IS NULL';
    $sql .= ' ORDER BY n.id DESC LIMIT 100';
    $stmt = $pdo->prepare($sql);
    $stmt->execute([':admin' => $adminId, ':after' => $after]);

    $items = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $items[] = [
            'id' => (int)$row['id'],
            'type' => $row['type'],
            'severity' => $row['severity'],
            'title' => $row['title'],
            'body' => $row['body'],
            'plate' => $row['label'] !== '' ? $row['label'] : $row['plate'],
            'createdAt' => $row['created_at'],
            'readAt' => $row['read_at'],
            'payload' => $row['payload_json'] ? json_decode($row['payload_json'], true) : null,
        ];
    }
    aims_json(['ok' => true, 'notifications' => $items]);
}

if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

    if (($data['readAll'] ?? false) === true) {
        $stmt = $pdo->prepare('UPDATE notifications SET read_at = :now WHERE admin_user_id = :admin AND read_at IS NULL');
        $stmt->execute([':now' => gmdate(DateTimeInterface::ATOM), ':admin' => $adminId]);
        aims_json(['ok' => true, 'updated' => $stmt->rowCount()]);
    }

    $ids = array_values(array_filter(array_map('intval', (array)($data['readIds'] ?? [])), fn($id) => $id > 0));
    if (!$ids) aims_json(['ok' => false, 'error' => 'no_notification_ids'], 422);
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $stmt = $pdo->prepare("UPDATE notifications SET read_at = ? WHERE admin_user_id = ? AND id IN ($placeholders)");
    $stmt->execute(array_merge([gmdate(DateTimeInterface::ATOM), $adminId], $ids));
    aims_json(['ok' => true, 'updated' => $stmt->rowCount()]);
}

header('Allow: GET, POST');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
