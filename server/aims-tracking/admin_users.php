<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$master = getenv('AIMS_ADMIN_TRACKING_TOKEN') ?: '';
$provided = aims_bearer();
if ($master === '' || $provided === '' || !hash_equals($master, $provided)) {
    aims_json(['ok' => false, 'error' => 'master_admin_required'], 401);
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'GET') {
    $rows = $pdo->query('SELECT id, name, enabled, created_at FROM admin_users ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    aims_json(['ok' => true, 'admins' => $rows]);
}

if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);
    $name = trim((string)($data['name'] ?? ''));
    $token = trim((string)($data['token'] ?? ''));
    if ($name === '' || strlen($token) < 20) aims_json(['ok' => false, 'error' => 'invalid_admin'], 422);

    $stmt = $pdo->prepare('INSERT INTO admin_users (name, token_hash, enabled, created_at)
                           VALUES (:name, :hash, 1, :created)');
    try {
        $stmt->execute([
            ':name' => mb_substr($name, 0, 120),
            ':hash' => hash('sha256', $token),
            ':created' => gmdate(DateTimeInterface::ATOM),
        ]);
    } catch (PDOException $error) {
        if (str_contains(strtolower($error->getMessage()), 'unique')) {
            aims_json(['ok' => false, 'error' => 'admin_token_exists'], 409);
        }
        throw $error;
    }
    aims_json(['ok' => true, 'adminId' => (int)$pdo->lastInsertId(), 'name' => $name]);
}

header('Allow: GET, POST');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
