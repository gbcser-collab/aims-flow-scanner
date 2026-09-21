<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$adminId = aims_admin_user_id($pdo);

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

$jobId = (int)($data['jobId'] ?? 0);
$reason = trim((string)($data['reason'] ?? 'admin_delete'));
if ($jobId < 1) aims_json(['ok' => false, 'error' => 'invalid_job_id'], 422);
if (mb_strlen($reason) > 250) $reason = mb_substr($reason, 0, 250);

$stmt = $pdo->prepare('SELECT j.*, v.plate, v.label, v.admin_user_id
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.id = :job AND v.admin_user_id = :admin
    LIMIT 1');
$stmt->execute([':job' => $jobId, ':admin' => $adminId]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$job) aims_json(['ok' => false, 'error' => 'job_not_found'], 404);

if (($job['status'] ?? '') === 'deleted') {
    aims_json([
        'ok' => true,
        'changed' => false,
        'jobId' => $jobId,
        'status' => 'deleted',
        'deletedAt' => $job['deleted_at'] ?? null,
    ]);
}

$now = gmdate(DateTimeInterface::ATOM);
$update = $pdo->prepare('UPDATE jobs
    SET status = "deleted",
        deleted_at = :deleted,
        delete_reason = :reason,
        updated_at = :updated
    WHERE id = :job AND status <> "deleted"');
$update->execute([
    ':deleted' => $now,
    ':reason' => $reason === '' ? 'admin_delete' : $reason,
    ':updated' => $now,
    ':job' => $jobId,
]);

$label = trim((string)($job['label'] ?? '')) !== ''
    ? (string)$job['label']
    : (string)$job['plate'];

aims_notify(
    $pdo,
    $adminId,
    (int)$job['vehicle_id'],
    'job_deleted',
    'warning',
    $label . ' fuvar törölve',
    (string)$job['reference'] . ' • ' . ($reason === '' ? 'admin_delete' : $reason),
    'job_deleted:' . $jobId,
    [
        'jobId' => $jobId,
        'reference' => (string)$job['reference'],
        'deletedAt' => $now,
        'reason' => $reason === '' ? 'admin_delete' : $reason,
    ]
);
aims_try_push($pdo, 8);

aims_json([
    'ok' => true,
    'changed' => $update->rowCount() === 1,
    'jobId' => $jobId,
    'status' => 'deleted',
    'deletedAt' => $now,
]);
