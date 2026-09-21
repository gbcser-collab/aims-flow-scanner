<?php
declare(strict_types=1);

// cPanel shared-hosting secrets: outside public_html.
$aimsSharedConfig=dirname(__DIR__,3).'/aims-flow-config.php';
if(is_file($aimsSharedConfig)){
  $cfg=require $aimsSharedConfig;
  if(is_array($cfg)){
    foreach($cfg as $k=>$v){
      if(!is_string($k)||!is_scalar($v))continue;
      $cur=getenv($k);
      if($cur===false||$cur==='')putenv($k.'='.(string)$v);
    }
  }
}

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

    $dataDir = trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: ''));
    if ($dataDir === '') $dataDir = __DIR__ . '/data';
    if (!is_dir($dataDir)) mkdir($dataDir, 0700, true);
    $pdo = new PDO('sqlite:' . $dataDir . '/tracking.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('PRAGMA synchronous=NORMAL');
    $pdo->exec('PRAGMA foreign_keys=ON');
    $pdo->exec('PRAGMA busy_timeout=5000');

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
    $vehicleColumns = [];
    foreach ($pdo->query('PRAGMA table_info(vehicles)')->fetchAll(PDO::FETCH_ASSOC) as $column) {
        $vehicleColumns[(string)$column['name']] = true;
    }
    if (!isset($vehicleColumns['rest_mode_started_at'])) {
        $pdo->exec('ALTER TABLE vehicles ADD COLUMN rest_mode_started_at TEXT');
    }
    if (!isset($vehicleColumns['rest_mode_until'])) {
        $pdo->exec('ALTER TABLE vehicles ADD COLUMN rest_mode_until TEXT');
    }

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

    $pointColumns = [];
    foreach ($pdo->query('PRAGMA table_info(points)')->fetchAll(PDO::FETCH_ASSOC) as $column) {
        $pointColumns[(string)$column['name']] = true;
    }
    if (!isset($pointColumns['point_key'])) {
        $pdo->exec('ALTER TABLE points ADD COLUMN point_key TEXT');
    }
    if (!isset($pointColumns['country_code'])) {
        $pdo->exec('ALTER TABLE points ADD COLUMN country_code TEXT');
    }
    $pdo->exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_points_point_key_unique
        ON points(point_key) WHERE point_key IS NOT NULL AND point_key <> ""');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_country_time
        ON points(country_code, captured_at DESC)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS vehicle_country_state (
        vehicle_id INTEGER PRIMARY KEY,
        confirmed_country_code TEXT,
        candidate_country_code TEXT,
        candidate_since TEXT,
        candidate_hits INTEGER NOT NULL DEFAULT 0,
        last_observed_at TEXT,
        last_latitude REAL,
        last_longitude REAL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
    )');

    $pdo->exec('CREATE TABLE IF NOT EXISTS country_stays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL,
        country_code TEXT NOT NULL,
        entered_at TEXT NOT NULL,
        exited_at TEXT,
        entry_latitude REAL,
        entry_longitude REAL,
        exit_latitude REAL,
        exit_longitude REAL,
        transition_from TEXT,
        confirmed_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_country_stays_vehicle_time
        ON country_stays(vehicle_id, entered_at DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_country_stays_open
        ON country_stays(vehicle_id, exited_at)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS maintenance_state (
        name TEXT PRIMARY KEY,
        last_run TEXT NOT NULL
    )');

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

    $pdo->exec('CREATE TABLE IF NOT EXISTS registration_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_key TEXT NOT NULL,
        company_name TEXT NOT NULL DEFAULT "",
        address_key TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT "",
        stop_type TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        confirmations INTEGER NOT NULL DEFAULT 1,
        last_vehicle_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_key, address_key, stop_type),
        FOREIGN KEY(last_vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_registration_points_lookup
        ON registration_points(company_key, address_key, stop_type)');

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

    $jobColumns = [];
    foreach ($pdo->query('PRAGMA table_info(jobs)')->fetchAll(PDO::FETCH_ASSOC) as $column) {
        $jobColumns[(string)$column['name']] = true;
    }
    if (!isset($jobColumns['driver_seen_at'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN driver_seen_at TEXT');
    }
    if (!isset($jobColumns['driver_accepted_at'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN driver_accepted_at TEXT');
    }
    if (!isset($jobColumns['driver_push_last_at'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN driver_push_last_at TEXT');
    }
    if (!isset($jobColumns['partial_load'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN partial_load INTEGER NOT NULL DEFAULT 0');
    }
    if (!isset($jobColumns['source_order_id'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN source_order_id TEXT');
    }
    if (!isset($jobColumns['order_payload_json'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN order_payload_json TEXT');
    }
    if (!isset($jobColumns['deleted_at'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN deleted_at TEXT');
    }
    if (!isset($jobColumns['delete_reason'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN delete_reason TEXT');
    }
    if (!isset($jobColumns['document_received_at'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN document_received_at TEXT');
    }
    if (!isset($jobColumns['document_local_id'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN document_local_id TEXT');
    }
    if (!isset($jobColumns['document_sync_state'])) {
        $pdo->exec('ALTER TABLE jobs ADD COLUMN document_sync_state TEXT');
    }

    $stopColumns = [];
    foreach ($pdo->query('PRAGMA table_info(job_stops)')->fetchAll(PDO::FETCH_ASSOC) as $column) {
        $stopColumns[(string)$column['name']] = true;
    }
    if (!isset($stopColumns['contact_phone'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN contact_phone TEXT');
    }
    if (!isset($stopColumns['arrival_source'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN arrival_source TEXT');
    }
    if (!isset($stopColumns['completed_at'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN completed_at TEXT');
    }
    if (!isset($stopColumns['completion_source'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN completion_source TEXT');
    }
    if (!isset($stopColumns['registration_checked_at'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN registration_checked_at TEXT');
    }
    if (!isset($stopColumns['registration_point_id'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN registration_point_id INTEGER');
    }
    if (!isset($stopColumns['waiting_alert_slot'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN waiting_alert_slot INTEGER NOT NULL DEFAULT 0');
    }
    if (!isset($stopColumns['waiting_alert_last_at'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN waiting_alert_last_at TEXT');
    }
    if (!isset($stopColumns['waiting_pause_started_at'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN waiting_pause_started_at TEXT');
    }
    if (!isset($stopColumns['waiting_paused_seconds'])) {
        $pdo->exec('ALTER TABLE job_stops ADD COLUMN waiting_paused_seconds INTEGER NOT NULL DEFAULT 0');
    }

    $pdo->exec('CREATE TABLE IF NOT EXISTS driver_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL,
        admin_user_id INTEGER NOT NULL,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        read_at TEXT,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE,
        FOREIGN KEY(admin_user_id) REFERENCES admin_users(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_messages_vehicle_id
        ON driver_messages(vehicle_id, id DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_messages_admin_id
        ON driver_messages(admin_user_id, id DESC)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS driver_push_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL,
        platform TEXT NOT NULL DEFAULT "android",
        device_id TEXT NOT NULL,
        fcm_token TEXT NOT NULL UNIQUE,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_push_vehicle_enabled ON driver_push_devices(vehicle_id, enabled)');

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

function aims_finalize_rest_pause(
    PDO $pdo,
    int $vehicleId,
    DateTimeImmutable $endedAt
): void {
    $stmt = $pdo->prepare('SELECT s.id, s.waiting_pause_started_at
        FROM job_stops s
        JOIN jobs j ON j.id = s.job_id
        WHERE j.vehicle_id = :vehicle
          AND j.status = "active"
          AND s.completed_at IS NULL
          AND s.waiting_pause_started_at IS NOT NULL');
    $stmt->execute([':vehicle' => $vehicleId]);
    $update = $pdo->prepare('UPDATE job_stops
        SET waiting_paused_seconds = waiting_paused_seconds + :seconds,
            waiting_pause_started_at = NULL
        WHERE id = :id');
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $stop) {
        try {
            $started = new DateTimeImmutable((string)$stop['waiting_pause_started_at']);
        } catch (Throwable) {
            $started = $endedAt;
        }
        $seconds = max(0, $endedAt->getTimestamp() - $started->getTimestamp());
        $update->execute([
            ':seconds' => $seconds,
            ':id' => (int)$stop['id'],
        ]);
    }

    $state = $pdo->prepare('UPDATE vehicle_state
        SET stationary_since = :ended,
            last_motion_at = :ended,
            alerts_mask = 0
        WHERE vehicle_id = :vehicle');
    $state->execute([
        ':ended' => $endedAt->format(DateTimeInterface::ATOM),
        ':vehicle' => $vehicleId,
    ]);
}

function aims_rest_mode_state(
    PDO $pdo,
    int $vehicleId,
    ?DateTimeImmutable $at = null
): array {
    $at ??= new DateTimeImmutable('now', new DateTimeZone('UTC'));
    $stmt = $pdo->prepare('SELECT rest_mode_started_at, rest_mode_until
        FROM vehicles WHERE id = :vehicle LIMIT 1');
    $stmt->execute([':vehicle' => $vehicleId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return ['active' => false, 'startedAt' => null, 'until' => null];
    }

    $startedRaw = trim((string)($row['rest_mode_started_at'] ?? ''));
    $untilRaw = trim((string)($row['rest_mode_until'] ?? ''));
    if ($startedRaw === '' || $untilRaw === '') {
        return ['active' => false, 'startedAt' => null, 'until' => null];
    }

    try {
        $startedAt = (new DateTimeImmutable($startedRaw))
            ->setTimezone(new DateTimeZone('UTC'));
        $until = (new DateTimeImmutable($untilRaw))
            ->setTimezone(new DateTimeZone('UTC'));
    } catch (Throwable) {
        $clear = $pdo->prepare('UPDATE vehicles
            SET rest_mode_started_at = NULL, rest_mode_until = NULL
            WHERE id = :vehicle');
        $clear->execute([':vehicle' => $vehicleId]);
        return ['active' => false, 'startedAt' => null, 'until' => null];
    }

    if ($until <= $at) {
        aims_finalize_rest_pause($pdo, $vehicleId, $until);
        $clear = $pdo->prepare('UPDATE vehicles
            SET rest_mode_started_at = NULL, rest_mode_until = NULL
            WHERE id = :vehicle');
        $clear->execute([':vehicle' => $vehicleId]);
        return ['active' => false, 'startedAt' => null, 'until' => null];
    }

    return [
        'active' => true,
        'startedAt' => $startedAt->format(DateTimeInterface::ATOM),
        'until' => $until->format(DateTimeInterface::ATOM),
    ];
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
