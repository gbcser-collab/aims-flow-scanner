<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    exit('POST only');
}
if (!aims_check_admin_csrf($_POST['csrf'] ?? '')) {
    http_response_code(403);
    exit('Érvénytelen munkamenet.');
}

require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

$pdo = aims_db();
$jobId = (int)($_POST['job_id'] ?? 0);
$reason = trim((string)($_POST['reason'] ?? 'Admin törlés a Flow felületről'));
if ($jobId < 1) {
    $_SESSION['aims_flow_dispatch_flash'] = [
        'ok' => false,
        'message' => 'Érvénytelen fuvarazonosító.',
    ];
    header('Location: aims-flow.php');
    exit;
}

$stmt = $pdo->prepare('SELECT j.*, v.plate, v.label, v.admin_user_id
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.id = :job
    LIMIT 1');
$stmt->execute([':job' => $jobId]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$job) {
    $_SESSION['aims_flow_dispatch_flash'] = [
        'ok' => false,
        'message' => 'A fuvar nem található.',
    ];
    header('Location: aims-flow.php');
    exit;
}

if (($job['status'] ?? '') === 'deleted') {
    $_SESSION['aims_flow_dispatch_flash'] = [
        'ok' => true,
        'message' => 'A fuvar már törölve van.',
    ];
    header('Location: aims-flow.php');
    exit;
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
    ':reason' => $reason === '' ? 'Admin törlés a Flow felületről' : mb_substr($reason, 0, 250),
    ':updated' => $now,
    ':job' => $jobId,
]);

$label = trim((string)($job['label'] ?? '')) !== ''
    ? (string)$job['label']
    : (string)$job['plate'];

aims_notify(
    $pdo,
    (int)$job['admin_user_id'],
    (int)$job['vehicle_id'],
    'job_deleted',
    'warning',
    $label . ' fuvar törölve',
    (string)$job['reference'],
    'job_deleted:' . $jobId,
    [
        'jobId' => $jobId,
        'reference' => (string)$job['reference'],
        'deletedAt' => $now,
    ]
);
aims_try_push($pdo, 8);

$_SESSION['aims_flow_dispatch_flash'] = [
    'ok' => true,
    'message' => 'Flow-fuvar törölve: ' . (string)$job['reference'] . ' • ' . $label,
];
header('Location: aims-flow.php');
exit;
