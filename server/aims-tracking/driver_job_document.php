<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

$plate = aims_normalize_plate((string)($data['plate'] ?? ''));
$jobId = (int)($data['jobId'] ?? 0);
$documentId = trim((string)($data['documentId'] ?? ''));
$syncState = trim((string)($data['syncState'] ?? 'pending'));

if ($plate === '' || $jobId < 1 || $documentId === '') {
    aims_json(['ok' => false, 'error' => 'invalid_payload'], 422);
}
if (mb_strlen($documentId) > 160) {
    aims_json(['ok' => false, 'error' => 'document_id_too_long'], 422);
}
if (!in_array($syncState, ['pending','failed','uploaded','approved','emailed'], true)) {
    $syncState = 'pending';
}

$pdo = aims_db();
$stmt = $pdo->prepare('SELECT j.*, v.plate, v.label, v.id AS vehicle_id, v.admin_user_id
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.id = :job AND v.plate = :plate AND v.enabled = 1
    LIMIT 1');
$stmt->execute([':job' => $jobId, ':plate' => $plate]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$job) aims_json(['ok' => false, 'error' => 'job_not_found'], 404);
if (($job['status'] ?? '') === 'deleted') {
    aims_json(['ok' => false, 'error' => 'job_deleted'], 410);
}

$remaining = $pdo->prepare('SELECT COUNT(*) FROM job_stops WHERE job_id = :job AND completed_at IS NULL');
$remaining->execute([':job' => $jobId]);
if ((int)$remaining->fetchColumn() !== 0) {
    aims_json(['ok' => false, 'error' => 'stops_incomplete'], 409);
}

$now = gmdate(DateTimeInterface::ATOM);
$update = $pdo->prepare('UPDATE jobs
    SET status = "completed",
        document_received_at = COALESCE(document_received_at, :received),
        document_local_id = :document,
        document_sync_state = :sync,
        updated_at = :updated
    WHERE id = :job AND status IN ("active","document_pending","completed")');
$update->execute([
    ':received' => $now,
    ':document' => $documentId,
    ':sync' => $syncState,
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
    'job_document_captured',
    'success',
    $label . ' · dokumentum rögzítve',
    (string)$job['reference'] . ' · CMR/dokumentum elmentve',
    'job_document_captured:' . $jobId,
    [
        'jobId' => $jobId,
        'reference' => (string)$job['reference'],
        'documentId' => $documentId,
        'syncState' => $syncState,
        'receivedAt' => $now,
    ]
);
aims_try_push($pdo, 8);

aims_json([
    'ok' => true,
    'jobId' => $jobId,
    'status' => 'completed',
    'documentId' => $documentId,
    'syncState' => $syncState,
    'receivedAt' => $now,
]);
