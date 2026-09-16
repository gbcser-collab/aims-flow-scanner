<?php
declare(strict_types=1);

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');

const DEFAULT_MAIL_TO = 'office@logistic-aims.hu';
const RETENTION_DAYS = 15;

function envv(string $name, string $default = ''): string {
    $v = getenv($name);
    return $v === false ? $default : trim((string)$v);
}

function json_response(array $payload, int $status = 200): never {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function body_json(): array {
    $raw = file_get_contents('php://input') ?: '';
    if ($raw === '') return [];
    try {
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    } catch (Throwable $e) {
        json_response(['error' => 'invalid_json'], 400);
    }
    return is_array($decoded) ? $decoded : [];
}

function request_path(): string {
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
    $script = $_SERVER['SCRIPT_NAME'] ?? '';
    if ($script !== '' && str_starts_with($path, $script)) {
        $path = substr($path, strlen($script));
    } elseif (preg_match('#/api(?:/index\.php)?(?<rest>/.*)?$#', $path, $m)) {
        $path = $m['rest'] ?? '/';
    }
    $path = '/' . ltrim($path, '/');
    return rtrim($path, '/') ?: '/';
}

function bearer_token(): string {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/^Bearer\s+(.+)$/i', $header, $m)) return trim($m[1]);
    return '';
}

function require_device_auth(): void {
    $expected = envv('AIMS_DEVICE_TOKEN');
    if ($expected === '') json_response(['error' => 'device_auth_not_configured'], 503);
    $got = bearer_token();
    if ($got === '' || !hash_equals($expected, $got)) json_response(['error' => 'unauthorized_device'], 401);
}

function start_admin_session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
    session_name('AIMSADMIN');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => $secure,
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();
}

function require_admin(): void {
    start_admin_session();
    if (!empty($_SESSION['aims_admin']) && $_SESSION['aims_admin'] === true) return;
    $token = envv('AIMS_ADMIN_TOKEN');
    if ($token !== '' && bearer_token() !== '' && hash_equals($token, bearer_token())) return;
    json_response(['error' => 'admin_auth_required'], 401);
}

function storage_dir(): string {
    $custom = envv('AIMS_STORAGE_DIR');
    $dir = $custom !== '' ? $custom : dirname(__DIR__) . '/storage';
    if (!is_dir($dir) && !mkdir($dir, 0700, true) && !is_dir($dir)) json_response(['error' => 'storage_unavailable'], 500);
    return rtrim($dir, '/');
}

function db(): PDO {
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;
    $pdo = new PDO('sqlite:' . storage_dir() . '/aims.sqlite', null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('PRAGMA foreign_keys=ON');
    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS cmr_documents (
  id TEXT PRIMARY KEY,
  local_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  state TEXT NOT NULL,
  image_path TEXT NOT NULL,
  cmr_json TEXT NOT NULL,
  quality_score INTEGER,
  emailed_at TEXT,
  email_error TEXT,
  approved_at TEXT,
  delete_after TEXT,
  approved_by TEXT,
  UNIQUE(local_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_cmr_state ON cmr_documents(state, received_at DESC);
CREATE TABLE IF NOT EXISTS audit_log (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  at TEXT NOT NULL,
  action TEXT NOT NULL,
  document_id TEXT,
  actor TEXT,
  meta_json TEXT
);
SQL);
    return $pdo;
}

function now_iso(): string { return gmdate('c'); }
function random_id(): string { return 'cmr_' . bin2hex(random_bytes(12)); }

function audit(string $action, ?string $documentId = null, ?string $actor = null, array $meta = []): void {
    $stmt = db()->prepare('INSERT INTO audit_log(at,action,document_id,actor,meta_json) VALUES(?,?,?,?,?)');
    $stmt->execute([now_iso(), $action, $documentId, $actor, json_encode($meta, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)]);
}

function cmr_row(string $serverId = '', string $localId = ''): ?array {
    if ($serverId !== '') {
        $stmt = db()->prepare('SELECT * FROM cmr_documents WHERE id=? LIMIT 1');
        $stmt->execute([$serverId]);
    } else {
        $stmt = db()->prepare('SELECT * FROM cmr_documents WHERE local_id=? ORDER BY received_at DESC LIMIT 1');
        $stmt->execute([$localId]);
    }
    $row = $stmt->fetch();
    return $row ?: null;
}

function public_state(array $row): array {
    return [
        'serverDocumentId' => $row['id'],
        'localId' => $row['local_id'],
        'state' => $row['state'],
        'uploadedAt' => $row['received_at'],
        'emailedAt' => $row['emailed_at'],
        'approvedAt' => $row['approved_at'],
        'deleteAfter' => $row['delete_after'],
    ];
}

function save_image(array $image, string $id): string {
    $base64 = (string)($image['base64'] ?? '');
    if ($base64 === '') json_response(['error' => 'image_missing'], 422);
    $bytes = base64_decode($base64, true);
    if ($bytes === false || strlen($bytes) < 128) json_response(['error' => 'invalid_image'], 422);
    if (strlen($bytes) > 15 * 1024 * 1024) json_response(['error' => 'image_too_large'], 413);
    if (substr($bytes, 0, 2) !== "\xFF\xD8") json_response(['error' => 'image_not_jpeg'], 422);

    $dir = storage_dir() . '/cmr';
    if (!is_dir($dir)) mkdir($dir, 0700, true);
    $path = $dir . '/' . $id . '.jpg';
    if (file_put_contents($path, $bytes, LOCK_EX) === false) json_response(['error' => 'image_write_failed'], 500);
    @chmod($path, 0600);
    return $path;
}

function cmr_summary(array $cmr): string {
    $pairs = [
        'CMR' => $cmr['cmrNumber'] ?? null,
        'Feladó' => $cmr['shipper'] ?? null,
        'Címzett' => $cmr['consignee'] ?? null,
        'Felrakóhely' => $cmr['loadingPlace'] ?? null,
        'Lerakóhely' => $cmr['deliveryPlace'] ?? null,
        'Dátum' => $cmr['date'] ?? null,
        'Rendszám' => $cmr['plate'] ?? null,
        'Darabszám' => $cmr['packageCount'] ?? null,
        'Bruttó tömeg' => isset($cmr['grossWeightKg']) ? ($cmr['grossWeightKg'] . ' kg') : null,
        'Áru' => $cmr['goodsDescription'] ?? null,
    ];
    $lines = [];
    foreach ($pairs as $k => $v) $lines[] = $k . ': ' . (($v === null || $v === '') ? '—' : (string)$v);
    return implode("\r\n", $lines);
}

function send_cmr_mail(array $row, array $payload): array {
    $to = envv('AIMS_MAIL_TO', DEFAULT_MAIL_TO);
    $from = envv('AIMS_MAIL_FROM', DEFAULT_MAIL_TO);
    $cmr = is_array($payload['cmr'] ?? null) ? $payload['cmr'] : [];
    $plate = trim((string)($cmr['plate'] ?? ''));
    $cmrNo = trim((string)($cmr['cmrNumber'] ?? ''));
    $subject = 'AIMS Flow CMR' . ($cmrNo !== '' ? ' #' . $cmrNo : '') . ($plate !== '' ? ' • ' . $plate : '');

    $location = is_array($payload['location'] ?? null) ? $payload['location'] : [];
    $locText = '—';
    if (isset($location['latitude'], $location['longitude'])) {
        $lat = (float)$location['latitude'];
        $lng = (float)$location['longitude'];
        $locText = sprintf('%.6f, %.6f | https://www.google.com/maps?q=%.6f,%.6f', $lat, $lng, $lat, $lng);
    }

    $text = "AIMS Flow automatikus CMR\r\n\r\n" .
        cmr_summary($cmr) . "\r\n\r\n" .
        'Készítés ideje: ' . ((string)($payload['createdAt'] ?? '—')) . "\r\n" .
        'Szerver fogadás: ' . $row['received_at'] . "\r\n" .
        'Készülék: ' . $row['device_id'] . "\r\n" .
        'Hely: ' . $locText . "\r\n" .
        'Minőség: ' . ((string)($payload['qualityScore'] ?? '—')) . "/100\r\n" .
        'Szerver CMR ID: ' . $row['id'] . "\r\n";

    $boundary = '=_AIMS_' . bin2hex(random_bytes(12));
    $filename = 'CMR-' . ($cmrNo !== '' ? preg_replace('/[^A-Za-z0-9_-]/', '_', $cmrNo) : $row['id']) . '.jpg';
    $bytes = file_get_contents($row['image_path']);
    if ($bytes === false) return [false, 'attachment_read_failed'];

    $headers = [
        'From: Logistic-A.I.M.S. <' . $from . '>',
        'Reply-To: ' . $from,
        'MIME-Version: 1.0',
        'Content-Type: multipart/mixed; boundary="' . $boundary . '"',
        'X-AIMS-Source: AIMS-Flow',
    ];
    $body = '--' . $boundary . "\r\n" .
        "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n" .
        $text . "\r\n" .
        '--' . $boundary . "\r\n" .
        'Content-Type: image/jpeg; name="' . $filename . '"' . "\r\n" .
        'Content-Disposition: attachment; filename="' . $filename . '"' . "\r\n" .
        "Content-Transfer-Encoding: base64\r\n\r\n" .
        chunk_split(base64_encode($bytes)) . "\r\n" .
        '--' . $boundary . "--\r\n";

    $ok = @mail($to, '=?UTF-8?B?' . base64_encode($subject) . '?=', $body, implode("\r\n", $headers));
    return [$ok, $ok ? null : 'php_mail_failed'];
}

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$path = request_path();

try {
    if ($method === 'GET' && $path === '/health') {
        db();
        json_response(['ok' => true, 'service' => 'aims-flow-cmr', 'time' => now_iso()]);
    }

    if ($method === 'POST' && $path === '/cmr/sync') {
        require_device_auth();
        $payload = body_json();
        $localId = trim((string)($payload['localId'] ?? ''));
        $deviceId = trim((string)($payload['deviceId'] ?? ''));
        if ($localId === '' || $deviceId === '') json_response(['error' => 'localId_and_deviceId_required'], 422);

        $stmt = db()->prepare('SELECT * FROM cmr_documents WHERE local_id=? AND device_id=? LIMIT 1');
        $stmt->execute([$localId, $deviceId]);
        $existing = $stmt->fetch();
        if ($existing) json_response(public_state($existing));

        $id = random_id();
        $received = now_iso();
        $pathSaved = save_image(is_array($payload['image'] ?? null) ? $payload['image'] : [], $id);
        $cmrJson = json_encode($payload['cmr'] ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $createdAt = trim((string)($payload['createdAt'] ?? '')) ?: $received;
        $quality = isset($payload['qualityScore']) ? (int)$payload['qualityScore'] : null;

        $insert = db()->prepare('INSERT INTO cmr_documents(id,local_id,device_id,created_at,received_at,updated_at,state,image_path,cmr_json,quality_score) VALUES(?,?,?,?,?,?,?,?,?,?)');
        $insert->execute([$id, $localId, $deviceId, $createdAt, $received, $received, 'uploaded', $pathSaved, $cmrJson, $quality]);
        audit('cmr_uploaded', $id, $deviceId, ['localId' => $localId]);

        $row = cmr_row($id, '') ?? throw new RuntimeException('insert_readback_failed');
        [$mailOk, $mailError] = send_cmr_mail($row, $payload);
        if ($mailOk) {
            $emailed = now_iso();
            $up = db()->prepare('UPDATE cmr_documents SET state=?, emailed_at=?, email_error=NULL, updated_at=? WHERE id=?');
            $up->execute(['emailed', $emailed, $emailed, $id]);
            audit('cmr_emailed', $id, 'system', ['to' => envv('AIMS_MAIL_TO', DEFAULT_MAIL_TO)]);
        } else {
            $up = db()->prepare('UPDATE cmr_documents SET email_error=?, updated_at=? WHERE id=?');
            $up->execute([$mailError, now_iso(), $id]);
            audit('cmr_email_failed', $id, 'system', ['error' => $mailError]);
        }
        $final = cmr_row($id, '') ?? $row;
        json_response(public_state($final), 201);
    }

    if ($method === 'GET' && $path === '/cmr/status') {
        require_device_auth();
        $serverId = trim((string)($_GET['serverDocumentId'] ?? ''));
        $localId = trim((string)($_GET['localId'] ?? ''));
        $row = cmr_row($serverId, $localId);
        if (!$row) json_response(['error' => 'not_found'], 404);
        json_response(public_state($row));
    }

    if ($method === 'POST' && $path === '/admin/login') {
        start_admin_session();
        $payload = body_json();
        $password = (string)($payload['password'] ?? '');
        $hash = envv('AIMS_ADMIN_PASSWORD_HASH');
        if ($hash === '') json_response(['error' => 'admin_login_not_configured'], 503);
        if (!password_verify($password, $hash)) {
            usleep(350000);
            audit('admin_login_failed', null, $_SERVER['REMOTE_ADDR'] ?? 'unknown');
            json_response(['error' => 'invalid_credentials'], 401);
        }
        session_regenerate_id(true);
        $_SESSION['aims_admin'] = true;
        $_SESSION['aims_admin_at'] = time();
        audit('admin_login', null, $_SERVER['REMOTE_ADDR'] ?? 'unknown');
        json_response(['ok' => true]);
    }

    if ($method === 'POST' && $path === '/admin/logout') {
        start_admin_session();
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $p = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'] ?? '', (bool)$p['secure'], (bool)$p['httponly']);
        }
        session_destroy();
        json_response(['ok' => true]);
    }

    if ($method === 'GET' && $path === '/admin/cmr') {
        require_admin();
        $limit = max(1, min(200, (int)($_GET['limit'] ?? 100)));
        $stmt = db()->prepare('SELECT id,local_id,device_id,created_at,received_at,updated_at,state,cmr_json,quality_score,emailed_at,email_error,approved_at,delete_after,approved_by FROM cmr_documents ORDER BY received_at DESC LIMIT ?');
        $stmt->bindValue(1, $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = [];
        foreach ($stmt->fetchAll() as $row) {
            $row['cmr'] = json_decode($row['cmr_json'] ?: '{}', true) ?: [];
            unset($row['cmr_json']);
            $rows[] = $row;
        }
        json_response(['documents' => $rows]);
    }

    if ($method === 'POST' && preg_match('#^/admin/cmr/([^/]+)/approve$#', $path, $m)) {
        require_admin();
        $id = rawurldecode($m[1]);
        $row = cmr_row($id, '');
        if (!$row) json_response(['error' => 'not_found'], 404);
        if (empty($row['emailed_at'])) json_response(['error' => 'cannot_approve_before_email'], 409);
        if (!empty($row['approved_at'])) json_response(public_state($row));

        $approved = new DateTimeImmutable('now', new DateTimeZone('UTC'));
        $deleteAfter = $approved->modify('+' . RETENTION_DAYS . ' days');
        $actor = 'admin';
        $stmt = db()->prepare('UPDATE cmr_documents SET state=?, approved_at=?, delete_after=?, approved_by=?, updated_at=? WHERE id=?');
        $stmt->execute(['approved', $approved->format(DATE_ATOM), $deleteAfter->format(DATE_ATOM), $actor, now_iso(), $id]);
        audit('cmr_approved', $id, $actor, ['deleteAfter' => $deleteAfter->format(DATE_ATOM)]);
        $updated = cmr_row($id, '') ?? throw new RuntimeException('approve_readback_failed');
        json_response(public_state($updated));
    }

    if ($method === 'POST' && preg_match('#^/admin/cmr/([^/]+)/retry-email$#', $path, $m)) {
        require_admin();
        $id = rawurldecode($m[1]);
        $row = cmr_row($id, '');
        if (!$row) json_response(['error' => 'not_found'], 404);
        $cmr = json_decode($row['cmr_json'] ?: '{}', true) ?: [];
        $payload = ['cmr' => $cmr, 'createdAt' => $row['created_at'], 'qualityScore' => $row['quality_score']];
        [$mailOk, $mailError] = send_cmr_mail($row, $payload);
        if (!$mailOk) {
            db()->prepare('UPDATE cmr_documents SET email_error=?, updated_at=? WHERE id=?')->execute([$mailError, now_iso(), $id]);
            json_response(['error' => 'mail_failed', 'detail' => $mailError], 502);
        }
        $emailed = now_iso();
        db()->prepare('UPDATE cmr_documents SET state=?, emailed_at=?, email_error=NULL, updated_at=? WHERE id=?')->execute(['emailed', $emailed, $emailed, $id]);
        audit('cmr_emailed_retry', $id, 'admin');
        $updated = cmr_row($id, '') ?? $row;
        json_response(public_state($updated));
    }

    json_response(['error' => 'route_not_found', 'path' => $path], 404);
} catch (Throwable $e) {
    error_log('[AIMS API] ' . $e->getMessage());
    json_response(['error' => 'server_error'], 500);
}
