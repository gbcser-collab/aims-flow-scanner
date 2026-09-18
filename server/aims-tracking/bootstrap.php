<?php
declare(strict_types=1);

require_once __DIR__ . '/smart_rules.php';
require_once __DIR__ . '/push_service.php';

function aims_json(array $payload, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function aims_bearer(): string {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/^Bearer\s+(.+)$/i', trim($header), $match)) return '';
    return trim($match[1]);
}

function aims_require_token(string $envName): void {
    $expected = getenv($envName) ?: '';
    if ($expected === '') aims_json(['ok' => false, 'error' => 'server_not_configured'], 503);
    $provided = aims_bearer();
    if ($provided === '' || !hash_equals($expected, $provided)) {
        aims_json(['ok' => false, 'error' => 'unauthorized'], 401);
    }
}

function aims_normalize_plate(string $value): string {
    $value = mb_strtoupper(trim($value), 'UTF-8');
    return preg_replace('/[^A-Z0-9]/u', '', $value) ?: '';
}

function aims_db(): PDO {
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;

    $dataDir = __DIR__ . '/data';
    if (!is_dir($dataDir)) mkdir($dataDir, 0700, true);
    $pdo = new PDO('sqlite:' . $dataDir . '/tracking.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('PRAGMA synchronous=NORMAL');
    $pdo->exec('PRAGMA foreign_keys=ON');

    $pdo->exec('CREATE TABLE IF NOT EXISTS admin_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        token_hash TEXT UNIQUE,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
    )');
    $pdo->exec('CREATE TABLE IF NOT EXISTS vehicles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plate TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL DEFAULT "",
        device_id TEXT UNIQUE,
        admin_user_id INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id)
    )');
    $pdo->exec('CREATE TABLE IF NOT EXISTS points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        vehicle_id INTEGER,
        vehicle_label TEXT NOT NULL DEFAULT "",
        captured_at TEXT NOT NULL,
        received_at TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed_mps REAL,
        heading REAL,
        altitude REAL,
        source TEXT NOT NULL DEFAULT "stream",
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id)
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_device_time ON points(device_id, captured_at DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_vehicle_time ON points(vehicle_id, captured_at DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_received ON points(received_at DESC)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS vehicle_state (
        vehicle_id INTEGER PRIMARY KEY,
        anchor_lat REAL NOT NULL,
        anchor_lng REAL NOT NULL,
        anchor_accuracy REAL,
        stationary_since TEXT NOT NULL,
        last_motion_at TEXT NOT NULL,
        last_point_at TEXT NOT NULL,
        alerts_mask INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
    )');

    $pdo->exec('CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        admin_user_id INTEGER NOT NULL,
        vehicle_id INTEGER,
        type TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT "info",
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        dedupe_key TEXT NOT NULL UNIQUE,
        payload_json TEXT,
        created_at TEXT NOT NULL,
        read_at TEXT,
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id),
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id)
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_notifications_admin_unread ON notifications(admin_user_id, read_at, id DESC)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference TEXT NOT NULL,
        vehicle_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT "active",
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(reference, vehicle_id),
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id)
    )');
    $pdo->exec('CREATE TABLE IF NOT EXISTS job_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id INTEGER NOT NULL,
        stop_type TEXT NOT NULL,
        stop_order INTEGER NOT NULL,
        company TEXT,
        address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_m REAL NOT NULL DEFAULT 180,
        inside_since TEXT,
        arrival_notified_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_job_stops_job ON job_stops(job_id, stop_order)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS geocode_cache (
        address_hash TEXT PRIMARY KEY,
        address TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        status TEXT NOT NULL,
        updated_at TEXT NOT NULL
    )');

    $pdo->exec('CREATE TABLE IF NOT EXISTS fuel_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL,
        admin_user_id INTEGER NOT NULL,
        captured_at TEXT NOT NULL,
        station TEXT,
        total_amount REAL,
        currency TEXT,
        liters REAL,
        price_per_liter REAL,
        receipt_number TEXT,
        ocr_text TEXT,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id),
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id)
    )');

    $pdo->exec('CREATE TABLE IF NOT EXISTS push_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        admin_user_id INTEGER NOT NULL,
        platform TEXT NOT NULL,
        device_id TEXT NOT NULL,
        fcm_token TEXT NOT NULL UNIQUE,
        app_version TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_push_devices_admin_enabled ON push_devices(admin_user_id, enabled)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS push_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id INTEGER NOT NULL,
        admin_user_id INTEGER NOT NULL,
        push_device_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT "pending",
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        last_error TEXT,
        provider_message_id TEXT,
        created_at TEXT NOT NULL,
        sent_at TEXT,
        UNIQUE(notification_id, push_device_id),
        FOREIGN KEY(notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id) ON DELETE CASCADE,
        FOREIGN KEY(push_device_id) REFERENCES push_devices(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_push_queue_due ON push_queue(status, next_attempt_at, id)');

    aims_ensure_default_admin($pdo);
    return $pdo;
}

function aims_ensure_default_admin(PDO $pdo): int {
    $name = getenv('AIMS_DEFAULT_ADMIN_NAME') ?: 'AIMS Admin';
    $stmt = $pdo->query('SELECT id FROM admin_users WHERE id = 1');
    $id = $stmt->fetchColumn();
    if ($id !== false) return (int)$id;
    $insert = $pdo->prepare('INSERT INTO admin_users (id, name, token_hash, enabled, created_at)
                             VALUES (1, :name, NULL, 1, :created_at)');
    $insert->execute([':name' => $name, ':created_at' => gmdate(DateTimeInterface::ATOM)]);
    return 1;
}

function aims_admin_user_id(PDO $pdo): int {
    $token = aims_bearer();
    if ($token === '') aims_json(['ok' => false, 'error' => 'unauthorized'], 401);

    $master = getenv('AIMS_ADMIN_TRACKING_TOKEN') ?: '';
    if ($master !== '' && hash_equals($master, $token)) return aims_ensure_default_admin($pdo);

    $hash = hash('sha256', $token);
    $stmt = $pdo->prepare('SELECT id FROM admin_users WHERE token_hash = :hash AND enabled = 1');
    $stmt->execute([':hash' => $hash]);
    $id = $stmt->fetchColumn();
    if ($id === false) aims_json(['ok' => false, 'error' => 'unauthorized'], 401);
    return (int)$id;
}

function aims_notify(
    PDO $pdo,
    int $adminUserId,
    ?int $vehicleId,
    string $type,
    string $severity,
    string $title,
    string $body,
    string $dedupeKey,
    array $payload = []
): void {
    $stmt = $pdo->prepare('INSERT OR IGNORE INTO notifications
        (admin_user_id, vehicle_id, type, severity, title, body, dedupe_key, payload_json, created_at)
        VALUES (:admin, :vehicle, :type, :severity, :title, :body, :dedupe, :payload, :created)');
    $stmt->execute([
        ':admin' => $adminUserId,
        ':vehicle' => $vehicleId,
        ':type' => $type,
        ':severity' => $severity,
        ':title' => $title,
        ':body' => $body,
        ':dedupe' => $dedupeKey,
        ':payload' => $payload ? json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
        ':created' => gmdate(DateTimeInterface::ATOM),
    ]);
    if ($stmt->rowCount() === 1) {
        $notificationId = (int)$pdo->lastInsertId();
        aims_enqueue_push_for_notification($pdo, $notificationId, $adminUserId);
    }
}

function aims_vehicle_for_point(PDO $pdo, string $deviceId, string $vehicleLabel): ?array {
    $plate = aims_normalize_plate($vehicleLabel);
    $vehicle = null;

    $stmt = $pdo->prepare('SELECT * FROM vehicles WHERE device_id = :device AND enabled = 1 LIMIT 1');
    $stmt->execute([':device' => $deviceId]);
    $vehicle = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;

    if ($vehicle === null && $plate !== '') {
        $stmt = $pdo->prepare('SELECT * FROM vehicles WHERE plate = :plate AND enabled = 1 LIMIT 1');
        $stmt->execute([':plate' => $plate]);
        $vehicle = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
        if ($vehicle !== null && ($vehicle['device_id'] === null || $vehicle['device_id'] === '')) {
            $bind = $pdo->prepare('UPDATE vehicles SET device_id = :device WHERE id = :id');
            $bind->execute([':device' => $deviceId, ':id' => $vehicle['id']]);
            $vehicle['device_id'] = $deviceId;
        }
    }
    return $vehicle;
}
