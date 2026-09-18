<?php
declare(strict_types=1);

function aims_base64url(string $value): string {
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function aims_push_config(): ?array {
    static $cached = false;
    static $config = null;
    if ($cached) return $config;
    $cached = true;

    $fakeLog = trim((string)(getenv('AIMS_PUSH_FAKE_LOG') ?: ''));
    if ($fakeLog !== '') {
        $config = ['mode' => 'fake', 'log' => $fakeLog, 'project_id' => 'aims-test'];
        return $config;
    }

    $raw = trim((string)(getenv('AIMS_FIREBASE_SERVICE_ACCOUNT_JSON') ?: ''));
    $b64 = trim((string)(getenv('AIMS_FIREBASE_SERVICE_ACCOUNT_B64') ?: ''));
    $file = trim((string)(getenv('AIMS_FIREBASE_SERVICE_ACCOUNT_FILE') ?: ''));
    if ($file === '' && is_file('/etc/aims-flow/firebase-service-account.json')) {
        $file = '/etc/aims-flow/firebase-service-account.json';
    }

    if ($raw === '' && $b64 !== '') {
        $decoded = base64_decode($b64, true);
        if (is_string($decoded)) $raw = $decoded;
    }
    if ($raw === '' && $file !== '' && is_file($file)) {
        $loaded = @file_get_contents($file);
        if (is_string($loaded)) $raw = $loaded;
    }
    if ($raw === '') return null;

    $json = json_decode($raw, true);
    if (!is_array($json)) return null;
    foreach (['client_email', 'private_key', 'project_id'] as $key) {
        if (!isset($json[$key]) || trim((string)$json[$key]) === '') return null;
    }

    $projectOverride = trim((string)(getenv('AIMS_FIREBASE_PROJECT_ID') ?: ''));
    $config = [
        'mode' => 'fcm',
        'client_email' => trim((string)$json['client_email']),
        'private_key' => (string)$json['private_key'],
        'project_id' => $projectOverride !== '' ? $projectOverride : trim((string)$json['project_id']),
    ];
    return $config;
}

function aims_http_post(string $url, array $headers, string $body, string $contentType = 'application/json'): array {
    if (!function_exists('curl_init')) {
        return ['ok' => false, 'status' => 0, 'body' => '', 'error' => 'curl_missing'];
    }
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_TIMEOUT => 8,
        CURLOPT_HTTPHEADER => array_merge([
            'Accept: application/json',
            'Content-Type: ' . $contentType,
        ], $headers),
    ]);
    $response = curl_exec($ch);
    $error = curl_error($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [
        'ok' => is_string($response) && $status >= 200 && $status < 300,
        'status' => $status,
        'body' => is_string($response) ? $response : '',
        'error' => $error,
    ];
}

function aims_fcm_access_token(array $config): ?string {
    static $memoryToken = null;
    static $memoryExp = 0;
    $now = time();
    if (is_string($memoryToken) && $memoryToken !== '' && $memoryExp > $now + 60) {
        return $memoryToken;
    }

    $dataDir = __DIR__ . '/data';
    if (!is_dir($dataDir)) @mkdir($dataDir, 0700, true);
    $cachePath = $dataDir . '/fcm_access_token.json';
    if (is_file($cachePath)) {
        $raw = @file_get_contents($cachePath);
        $cache = is_string($raw) ? json_decode($raw, true) : null;
        if (is_array($cache)
            && ($cache['client_email'] ?? '') === $config['client_email']
            && ($cache['project_id'] ?? '') === $config['project_id']
            && (int)($cache['expires_at'] ?? 0) > $now + 60
            && is_string($cache['access_token'] ?? null)
        ) {
            $memoryToken = $cache['access_token'];
            $memoryExp = (int)$cache['expires_at'];
            return $memoryToken;
        }
    }

    $header = aims_base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_UNESCAPED_SLASHES));
    $claims = aims_base64url(json_encode([
        'iss' => $config['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3500,
    ], JSON_UNESCAPED_SLASHES));
    $unsigned = $header . '.' . $claims;

    $privateKey = openssl_pkey_get_private($config['private_key']);
    if ($privateKey === false) return null;
    $signature = '';
    $signed = openssl_sign($unsigned, $signature, $privateKey, OPENSSL_ALGO_SHA256);
    if (!$signed) return null;
    $jwt = $unsigned . '.' . aims_base64url($signature);

    $response = aims_http_post(
        'https://oauth2.googleapis.com/token',
        [],
        http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
        'application/x-www-form-urlencoded'
    );
    if (!$response['ok']) return null;

    $decoded = json_decode($response['body'], true);
    $token = is_array($decoded) ? trim((string)($decoded['access_token'] ?? '')) : '';
    $expiresIn = is_array($decoded) ? max(300, (int)($decoded['expires_in'] ?? 3600)) : 3600;
    if ($token === '') return null;

    $memoryToken = $token;
    $memoryExp = $now + $expiresIn;
    $cache = json_encode([
        'client_email' => $config['client_email'],
        'project_id' => $config['project_id'],
        'access_token' => $token,
        'expires_at' => $memoryExp,
    ], JSON_UNESCAPED_SLASHES);
    if (is_string($cache)) {
        @file_put_contents($cachePath, $cache, LOCK_EX);
        @chmod($cachePath, 0600);
    }
    return $token;
}

function aims_fcm_data(array $payload): array {
    $data = [];
    foreach ($payload as $key => $value) {
        if ($value === null) continue;
        if (is_scalar($value)) {
            $data[(string)$key] = (string)$value;
        } else {
            $encoded = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if (is_string($encoded)) $data[(string)$key] = $encoded;
        }
    }
    return $data;
}

function aims_send_push(array $device, array $notification): array {
    $config = aims_push_config();
    if ($config === null) return ['ok' => false, 'configured' => false, 'error' => 'push_not_configured'];

    $payload = [
        'notificationId' => (string)$notification['id'],
        'type' => (string)$notification['type'],
        'severity' => (string)$notification['severity'],
        'vehicleId' => $notification['vehicle_id'] === null ? '' : (string)$notification['vehicle_id'],
    ];
    $extra = $notification['payload_json'] ? json_decode((string)$notification['payload_json'], true) : null;
    if (is_array($extra)) $payload = array_merge($payload, $extra);
    $data = aims_fcm_data($payload);

    if ($config['mode'] === 'fake') {
        $line = json_encode([
            'adminUserId' => (int)$notification['admin_user_id'],
            'pushDeviceId' => (int)$device['id'],
            'platform' => $device['platform'],
            'title' => $notification['title'],
            'body' => $notification['body'],
            'data' => $data,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (is_string($line)) {
            @file_put_contents($config['log'], $line . PHP_EOL, FILE_APPEND | LOCK_EX);
        }
        return ['ok' => true, 'configured' => true, 'message_id' => 'fake-' . $notification['id'] . '-' . $device['id']];
    }

    $accessToken = aims_fcm_access_token($config);
    if ($accessToken === null) {
        return ['ok' => false, 'configured' => true, 'error' => 'oauth_token_failed'];
    }

    $message = [
        'message' => [
            'token' => $device['fcm_token'],
            'notification' => [
                'title' => $notification['title'],
                'body' => $notification['body'],
            ],
            'data' => $data,
            'android' => [
                'priority' => 'high',
                'notification' => [
                    'sound' => 'default',
                ],
            ],
            'apns' => [
                'headers' => ['apns-priority' => '10'],
                'payload' => ['aps' => ['sound' => 'default']],
            ],
        ],
    ];

    $response = aims_http_post(
        'https://fcm.googleapis.com/v1/projects/' . rawurlencode($config['project_id']) . '/messages:send',
        ['Authorization: Bearer ' . $accessToken],
        json_encode($message, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    );
    $decoded = json_decode($response['body'], true);
    if ($response['ok']) {
        return [
            'ok' => true,
            'configured' => true,
            'message_id' => is_array($decoded) ? (string)($decoded['name'] ?? '') : '',
        ];
    }

    $body = $response['body'];
    $invalid = $response['status'] === 404
        || str_contains($body, 'UNREGISTERED')
        || str_contains($body, 'registration-token-not-registered');

    return [
        'ok' => false,
        'configured' => true,
        'invalid_token' => $invalid,
        'status' => $response['status'],
        'error' => $response['error'] !== '' ? $response['error'] : ('fcm_http_' . $response['status']),
        'response' => mb_substr($body, 0, 1200),
    ];
}

function aims_enqueue_push_for_notification(PDO $pdo, int $notificationId, int $adminUserId): int {
    $stmt = $pdo->prepare('INSERT OR IGNORE INTO push_queue
        (notification_id, admin_user_id, push_device_id, status, attempts, next_attempt_at, created_at)
        SELECT :notification, :admin, d.id, "pending", 0, :now, :now
        FROM push_devices d
        WHERE d.admin_user_id = :admin2 AND d.enabled = 1');
    $now = gmdate(DateTimeInterface::ATOM);
    $stmt->execute([
        ':notification' => $notificationId,
        ':admin' => $adminUserId,
        ':admin2' => $adminUserId,
        ':now' => $now,
    ]);
    return $stmt->rowCount();
}

function aims_retry_delay_seconds(int $attempts): int {
    return match (true) {
        $attempts <= 1 => 60,
        $attempts === 2 => 300,
        $attempts === 3 => 900,
        $attempts <= 5 => 3600,
        default => 21600,
    };
}

function aims_process_push_queue(PDO $pdo, int $limit = 10): array {
    $config = aims_push_config();
    if ($config === null) return ['configured' => false, 'processed' => 0, 'sent' => 0, 'failed' => 0];

    $limit = max(1, min(50, $limit));
    $now = gmdate(DateTimeInterface::ATOM);
    $stmt = $pdo->prepare('SELECT q.*, d.fcm_token, d.platform, d.device_id,
                                  n.vehicle_id, n.type, n.severity, n.title, n.body, n.payload_json, n.created_at AS notification_created_at
                           FROM push_queue q
                           JOIN push_devices d ON d.id = q.push_device_id
                           JOIN notifications n ON n.id = q.notification_id
                           WHERE q.status IN ("pending", "retry", "sending")
                             AND q.next_attempt_at <= :now
                             AND d.enabled = 1
                           ORDER BY q.id ASC
                           LIMIT ' . $limit);
    $stmt->execute([':now' => $now]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $sent = 0;
    $failed = 0;
    foreach ($rows as $row) {
        $leaseUntil = (new DateTimeImmutable('now', new DateTimeZone('UTC')))
            ->modify('+90 seconds')
            ->format(DateTimeInterface::ATOM);
        $claim = $pdo->prepare('UPDATE push_queue
            SET status = "sending", next_attempt_at = :lease
            WHERE id = :id
              AND status IN ("pending", "retry", "sending")
              AND next_attempt_at <= :now');
        $claim->execute([
            ':lease' => $leaseUntil,
            ':id' => $row['id'],
            ':now' => gmdate(DateTimeInterface::ATOM),
        ]);
        if ($claim->rowCount() !== 1) continue;

        $notification = [
            'id' => (int)$row['notification_id'],
            'admin_user_id' => (int)$row['admin_user_id'],
            'vehicle_id' => $row['vehicle_id'] === null ? null : (int)$row['vehicle_id'],
            'type' => $row['type'],
            'severity' => $row['severity'],
            'title' => $row['title'],
            'body' => $row['body'],
            'payload_json' => $row['payload_json'],
        ];
        $device = [
            'id' => (int)$row['push_device_id'],
            'fcm_token' => $row['fcm_token'],
            'platform' => $row['platform'],
            'device_id' => $row['device_id'],
        ];

        $result = aims_send_push($device, $notification);
        if (($result['ok'] ?? false) === true) {
            $update = $pdo->prepare('UPDATE push_queue
                SET status = "sent", attempts = attempts + 1, sent_at = :sent, last_error = NULL, provider_message_id = :message
                WHERE id = :id');
            $update->execute([
                ':sent' => gmdate(DateTimeInterface::ATOM),
                ':message' => $result['message_id'] ?? null,
                ':id' => $row['id'],
            ]);
            $sent++;
            continue;
        }

        $attempts = ((int)$row['attempts']) + 1;
        if (($result['invalid_token'] ?? false) === true) {
            $pdo->prepare('UPDATE push_devices SET enabled = 0, updated_at = :now WHERE id = :id')
                ->execute([':now' => gmdate(DateTimeInterface::ATOM), ':id' => $row['push_device_id']]);
        }
        $dead = ($result['invalid_token'] ?? false) === true || $attempts >= 8;
        $next = (new DateTimeImmutable('now', new DateTimeZone('UTC')))
            ->modify('+' . aims_retry_delay_seconds($attempts) . ' seconds')
            ->format(DateTimeInterface::ATOM);
        $update = $pdo->prepare('UPDATE push_queue
            SET status = :status, attempts = :attempts, next_attempt_at = :next, last_error = :error
            WHERE id = :id');
        $update->execute([
            ':status' => $dead ? 'dead' : 'retry',
            ':attempts' => $attempts,
            ':next' => $next,
            ':error' => mb_substr((string)($result['error'] ?? 'push_failed'), 0, 500),
            ':id' => $row['id'],
        ]);
        $failed++;
    }

    return ['configured' => true, 'processed' => count($rows), 'sent' => $sent, 'failed' => $failed];
}

function aims_try_push(PDO $pdo, int $limit = 10): void {
    try {
        aims_process_push_queue($pdo, $limit);
    } catch (Throwable $error) {
        error_log('AIMS push delivery: ' . $error->getMessage());
    }
}
