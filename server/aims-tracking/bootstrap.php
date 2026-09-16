<?php
declare(strict_types=1);

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
    if ($expected === '') {
        aims_json(['ok' => false, 'error' => 'server_not_configured'], 503);
    }
    $provided = aims_bearer();
    if ($provided === '' || !hash_equals($expected, $provided)) {
        aims_json(['ok' => false, 'error' => 'unauthorized'], 401);
    }
}

function aims_db(): PDO {
    $dataDir = __DIR__ . '/data';
    if (!is_dir($dataDir)) mkdir($dataDir, 0700, true);
    $pdo = new PDO('sqlite:' . $dataDir . '/tracking.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('PRAGMA synchronous=NORMAL');
    $pdo->exec('CREATE TABLE IF NOT EXISTS points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        vehicle_label TEXT NOT NULL DEFAULT "",
        captured_at TEXT NOT NULL,
        received_at TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed_mps REAL,
        heading REAL,
        altitude REAL
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_device_time ON points(device_id, captured_at DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_received ON points(received_at DESC)');
    return $pdo;
}
