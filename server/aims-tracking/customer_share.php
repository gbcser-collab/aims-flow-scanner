<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

$jobId = (int)($data['jobId'] ?? 0);
$action = strtolower(trim((string)($data['action'] ?? 'create')));
$expiresHours = max(1, min(720, (int)($data['expiresHours'] ?? 336)));

if ($jobId < 1) aims_json(['ok' => false, 'error' => 'invalid_job'], 422);
if (!in_array($action, ['create', 'revoke'], true)) {
    aims_json(['ok' => false, 'error' => 'invalid_action'], 422);
}

$stmt = $pdo->prepare('SELECT j.*, v.plate, v.label
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.id = :job
      AND v.admin_user_id = :admin
      AND COALESCE(j.status, "") <> "deleted"
    LIMIT 1');
$stmt->execute([':job' => $jobId, ':admin' => $adminId]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$job) aims_json(['ok' => false, 'error' => 'job_not_found'], 404);

$now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

if ($action === 'revoke') {
    $update = $pdo->prepare('UPDATE jobs
        SET customer_tracking_token_hash = NULL,
            customer_tracking_expires_at = NULL,
            customer_tracking_last_view_at = NULL,
            updated_at = :updated
        WHERE id = :job');
    $update->execute([
        ':updated' => $now->format(DateTimeInterface::ATOM),
        ':job' => $jobId,
    ]);
    aims_json([
        'ok' => true,
        'jobId' => $jobId,
        'reference' => (string)$job['reference'],
        'revoked' => true,
    ]);
}

$token = bin2hex(random_bytes(32));
$tokenHash = hash('sha256', $token);
$expiresAt = $now->modify("+{$expiresHours} hours")->format(DateTimeInterface::ATOM);

$update = $pdo->prepare('UPDATE jobs
    SET customer_tracking_token_hash = :hash,
        customer_tracking_expires_at = :expires,
        customer_tracking_created_at = :created,
        customer_tracking_last_view_at = NULL,
        updated_at = :updated
    WHERE id = :job');
$update->execute([
    ':hash' => $tokenHash,
    ':expires' => $expiresAt,
    ':created' => $now->format(DateTimeInterface::ATOM),
    ':updated' => $now->format(DateTimeInterface::ATOM),
    ':job' => $jobId,
]);

$base = trim((string)(getenv('AIMS_PUBLIC_BASE_URL') ?: ''));
if ($base === '') {
    $host = trim((string)($_SERVER['HTTP_HOST'] ?? 'logistic-aims.hu'));
    $host = preg_replace('/[^A-Za-z0-9.:-]/', '', $host) ?: 'logistic-aims.hu';
    $base = 'https://' . $host;
}
$scriptDir = rtrim(str_replace('\\', '/', dirname((string)($_SERVER['SCRIPT_NAME'] ?? '/api/aims-tracking/customer_share.php'))), '/');
$url = rtrim($base, '/') . $scriptDir . '/customer_portal.php?t=' . rawurlencode($token);

aims_json([
    'ok' => true,
    'jobId' => $jobId,
    'reference' => (string)$job['reference'],
    'plate' => trim((string)$job['label']) !== '' ? (string)$job['label'] : (string)$job['plate'],
    'trackingUrl' => $url,
    'expiresAt' => $expiresAt,
    'expiresHours' => $expiresHours,
]);
