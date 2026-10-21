<?php
declare(strict_types=1);

/**
 * AIMS FLOW driver identity v2.
 *
 * This module deliberately keeps the PIN and session implementation outside
 * the public UI. Only password hashes and token hashes are stored.
 */

function aims_driver_auth_schema(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS driver_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        flow_id TEXT NOT NULL UNIQUE,
        pin_hash TEXT NOT NULL,
        email TEXT NOT NULL,
        driver_name TEXT NOT NULL DEFAULT "",
        vehicle_id INTEGER,
        onboarding_complete INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login_at TEXT,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_accounts_vehicle
        ON driver_accounts(vehicle_id, enabled)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_accounts_email
        ON driver_accounts(email, enabled)');

    $pdo->exec('CREATE TABLE IF NOT EXISTS driver_sessions (
        token_hash TEXT PRIMARY KEY,
        account_id INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        revoked_at TEXT,
        FOREIGN KEY(account_id) REFERENCES driver_accounts(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_sessions_account
        ON driver_sessions(account_id, revoked_at, expires_at)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_driver_sessions_device
        ON driver_sessions(device_id, revoked_at, expires_at)');
}

function aims_driver_flow_id_valid(string $value): bool {
    return preg_match('/^[0-9]{6}$/', trim($value)) === 1;
}

function aims_driver_pin_valid(string $value): bool {
    return preg_match('/^[0-9]{5}$/', trim($value)) === 1;
}

function aims_driver_generate_digits(int $length): string {
    if ($length < 1 || $length > 18) throw new InvalidArgumentException('invalid_length');
    $out = '';
    for ($i = 0; $i < $length; $i++) $out .= (string)random_int(0, 9);
    return $out;
}

function aims_driver_generate_unique_flow_id(PDO $pdo): string {
    aims_driver_auth_schema($pdo);
    $check = $pdo->prepare('SELECT 1 FROM driver_accounts WHERE flow_id=:flow LIMIT 1');
    for ($attempt = 0; $attempt < 100; $attempt++) {
        // Avoid leading zero so copied IDs remain six visible digits in every client.
        $flowId = (string)random_int(100000, 999999);
        $check->execute([':flow' => $flowId]);
        if ($check->fetchColumn() === false) return $flowId;
    }
    throw new RuntimeException('flow_id_space_exhausted');
}

function aims_driver_generate_pin(): string {
    return str_pad((string)random_int(0, 99999), 5, '0', STR_PAD_LEFT);
}

function aims_driver_find_account(PDO $pdo, string $flowId): ?array {
    aims_driver_auth_schema($pdo);
    $query = $pdo->prepare('SELECT a.*,v.plate,v.label
        FROM driver_accounts a
        LEFT JOIN vehicles v ON v.id=a.vehicle_id
        WHERE a.flow_id=:flow LIMIT 1');
    $query->execute([':flow' => trim($flowId)]);
    $row = $query->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function aims_driver_issue_session(
    PDO $pdo,
    int $accountId,
    string $deviceId,
    int $ttlDays = 90
): array {
    aims_driver_auth_schema($pdo);
    $deviceId = trim($deviceId);
    if ($accountId < 1 || strlen($deviceId) < 16 || strlen($deviceId) > 200) {
        throw new InvalidArgumentException('invalid_session_identity');
    }

    $now = gmdate(DateTimeInterface::ATOM);
    $expiresAt = gmdate(DateTimeInterface::ATOM, time() + max(1, min(180, $ttlDays)) * 86400);
    $token = bin2hex(random_bytes(32));
    $hash = hash('sha256', $token);

    $pdo->beginTransaction();
    try {
        // A device keeps one current session for the account. Other phones can
        // remain signed in until the office explicitly revokes them.
        $revoke = $pdo->prepare('UPDATE driver_sessions
            SET revoked_at=:now
            WHERE account_id=:account AND device_id=:device AND revoked_at IS NULL');
        $revoke->execute([
            ':now' => $now,
            ':account' => $accountId,
            ':device' => $deviceId,
        ]);

        $insert = $pdo->prepare('INSERT INTO driver_sessions
            (token_hash,account_id,device_id,created_at,expires_at,last_seen_at,revoked_at)
            VALUES (:hash,:account,:device,:created,:expires,:seen,NULL)');
        $insert->execute([
            ':hash' => $hash,
            ':account' => $accountId,
            ':device' => $deviceId,
            ':created' => $now,
            ':expires' => $expiresAt,
            ':seen' => $now,
        ]);
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $error;
    }

    return [
        'token' => $token,
        'expiresAt' => $expiresAt,
        'deviceId' => $deviceId,
    ];
}

function aims_driver_session_from_token(
    PDO $pdo,
    string $token,
    bool $touch = true
): ?array {
    aims_driver_auth_schema($pdo);
    $token = trim($token);
    if (!preg_match('/^[a-f0-9]{64}$/', $token)) return null;

    $hash = hash('sha256', $token);
    $now = gmdate(DateTimeInterface::ATOM);
    $query = $pdo->prepare('SELECT
            s.token_hash,s.account_id,s.device_id,s.created_at AS session_created_at,
            s.expires_at,s.last_seen_at,s.revoked_at,
            a.flow_id,a.email,a.driver_name,a.vehicle_id,a.onboarding_complete,a.enabled,
            v.plate,v.label
        FROM driver_sessions s
        JOIN driver_accounts a ON a.id=s.account_id
        LEFT JOIN vehicles v ON v.id=a.vehicle_id
        WHERE s.token_hash=:hash
          AND s.revoked_at IS NULL
          AND s.expires_at>:now
          AND a.enabled=1
        LIMIT 1');
    $query->execute([':hash' => $hash, ':now' => $now]);
    $row = $query->fetch(PDO::FETCH_ASSOC);
    if (!$row) return null;

    if ($touch) {
        $touchStmt = $pdo->prepare('UPDATE driver_sessions
            SET last_seen_at=:now WHERE token_hash=:hash');
        $touchStmt->execute([':now' => $now, ':hash' => $hash]);
        $row['last_seen_at'] = $now;
    }
    return $row;
}

function aims_driver_session_from_bearer(PDO $pdo, bool $touch = true): ?array {
    return aims_driver_session_from_token($pdo, aims_bearer(), $touch);
}

function aims_require_driver_session(PDO $pdo, bool $touch = true): array {
    $session = aims_driver_session_from_bearer($pdo, $touch);
    if (!$session) aims_json(['ok' => false, 'error' => 'invalid_session'], 401);
    return $session;
}

function aims_driver_authorize_plate(array $session, string $plate): string {
    $requested = aims_normalize_plate($plate);
    $assigned = aims_normalize_plate((string)($session['plate'] ?? ''));
    if ($requested === '' || $assigned === '' || !hash_equals($assigned, $requested)) {
        aims_json(['ok' => false, 'error' => 'plate_forbidden'], 403);
    }
    return $assigned;
}

function aims_driver_account_payload(PDO $pdo, array $account): array {
    $vehicleId = isset($account['vehicle_id']) ? (int)$account['vehicle_id'] : 0;
    $currentKm = null;
    if ($vehicleId > 0) {
        $km = $pdo->prepare('SELECT km FROM vehicle_odometer_log
            WHERE vehicle_id=:vehicle ORDER BY captured_at DESC,id DESC LIMIT 1');
        $km->execute([':vehicle' => $vehicleId]);
        $value = $km->fetchColumn();
        if ($value !== false) $currentKm = (int)$value;
    }

    return [
        'flowId' => (string)$account['flow_id'],
        'email' => (string)$account['email'],
        'driverName' => (string)($account['driver_name'] ?? ''),
        'plate' => (string)($account['plate'] ?? ''),
        'vehicleLabel' => (string)($account['label'] ?? ''),
        'currentKm' => $currentKm,
        'onboardingComplete' => ((int)($account['onboarding_complete'] ?? 0)) === 1,
    ];
}

function aims_driver_revoke_session(PDO $pdo, string $token): void {
    $token = trim($token);
    if (!preg_match('/^[a-f0-9]{64}$/', $token)) return;
    $stmt = $pdo->prepare('UPDATE driver_sessions SET revoked_at=:now
        WHERE token_hash=:hash AND revoked_at IS NULL');
    $stmt->execute([
        ':now' => gmdate(DateTimeInterface::ATOM),
        ':hash' => hash('sha256', $token),
    ]);
}
