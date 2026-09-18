<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();

if (PHP_SAPI !== 'cli') {
    $expected = trim((string)(getenv('AIMS_PUSH_WORKER_TOKEN') ?: ''));
    $provided = aims_bearer();
    if ($expected === '' || $provided === '' || !hash_equals($expected, $provided)) {
        aims_json(['ok' => false, 'error' => 'unauthorized'], 401);
    }
}

$limit = PHP_SAPI === 'cli'
    ? max(1, min(50, (int)($argv[1] ?? 25)))
    : max(1, min(50, (int)($_GET['limit'] ?? 25)));

$result = aims_process_push_queue($pdo, $limit);
$driverResult = aims_process_driver_job_reminders($pdo, $limit);
$result = array_merge($result, $driverResult);

if (PHP_SAPI === 'cli') {
    echo json_encode(['ok' => true] + $result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    exit(0);
}
aims_json(['ok' => true] + $result);
