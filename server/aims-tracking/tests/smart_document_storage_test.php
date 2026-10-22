<?php
declare(strict_types=1);
require dirname(__DIR__) . '/smart_document_storage.php';

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}
function connection(string $root): PDO {
    $pdo = new PDO('sqlite:' . $root . '/test.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA busy_timeout=10000');
    return $pdo;
}
function document(string $id): array {
    return ['localId' => $id, 'flowId' => '199001', 'vehicleId' => 1, 'plate' => 'TEST199',
        'type' => 'pod', 'capturedAt' => '2026-10-22T08:00:00.123456+00:00',
        'ocrText' => 'Delivery', 'confidence' => 0.9, 'extension' => 'jpg', 'bytes' => str_repeat('image-data', 200)];
}
function files(string $root): array {
    $found = [];
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)) as $file) {
        if (str_contains($file->getPathname(), '/smart-documents/')) $found[] = $file->getPathname();
    }
    sort($found); return $found;
}
if (($argv[1] ?? '') === '--worker') {
    $root = $argv[2];
    $pdo = connection($root);
    while (!is_file($root . '/go')) usleep(1000);
    echo json_encode(aims_store_smart_document($pdo, $root, document('concurrent')));
    exit;
}
$root = sys_get_temp_dir() . '/aims-smart-' . bin2hex(random_bytes(8));
mkdir($root, 0700, true);
try {
    $pdo = connection($root);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('CREATE TABLE smart_documents(id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT NOT NULL UNIQUE,vehicle_id INTEGER NOT NULL,document_type TEXT NOT NULL,
        captured_at TEXT NOT NULL,ocr_text TEXT,confidence REAL,image_path TEXT NOT NULL,created_at TEXT NOT NULL)');
    $pdo->exec("INSERT INTO smart_documents(local_id,vehicle_id,document_type,captured_at,image_path,created_at)
        VALUES ('legacy',1,'pod','2026-01-01','legacy.jpg','2026-01-01')");
    aims_smart_document_schema($pdo); aims_smart_document_schema($pdo);
    check((int)$pdo->query('SELECT count(*) FROM smart_documents')->fetchColumn() === 1, 'migration preserves records');
    $calls = 0;
    $first = aims_store_smart_document($pdo, $root, document('partial'),
        function ($stream, $chunk) use (&$calls): int|false { $calls++; return fwrite($stream, substr($chunk, 0, 7)); });
    check($calls > 1 && !$first['duplicate'], 'short writes are completed');
    $before = files($root);
    check(count($before) === 1 && file_get_contents($before[0]) === document('partial')['bytes'], 'complete image before acknowledgement');
    $retry = aims_store_smart_document($pdo, $root, document('partial'));
    check($retry['duplicate'] && $retry['documentId'] === $first['documentId'] && files($root) === $before, 'retry preserves image');
    foreach (['bytes' => 'different image', 'flowId' => '199002', 'vehicleId' => 2,
        'ocrText' => 'changed', 'capturedAt' => '2026-10-22T08:00:00.123457+00:00'] as $key => $value) {
        try { aims_store_smart_document($pdo, $root, array_replace(document('partial'), [$key => $value]));
            throw new RuntimeException('conflicting retry accepted');
        } catch (AimsSmartDocumentException $error) { check($error->status === 409, 'conflict status'); }
        check(files($root) === $before && file_get_contents($before[0]) === document('partial')['bytes'], 'conflict preserves original');
    }
    try { aims_store_smart_document($pdo, $root, document('legacy')); throw new RuntimeException('legacy owner guessed'); }
    catch (AimsSmartDocumentException $error) { check($error->getMessage() === 'document_owner_unverified', 'legacy held'); }
    $writes = 0;
    try {
        aims_store_smart_document($pdo, $root, document('full-disk'), function ($stream, $chunk) use (&$writes): int|false {
            return ++$writes === 1 ? fwrite($stream, substr($chunk, 0, 20)) : 0;
        });
        throw new RuntimeException('partial image accepted');
    } catch (AimsSmartDocumentException $error) { check($error->getMessage() === 'image_write_failed', 'write failure'); }
    check(files($root) === $before, 'partial temporary image removed');
    $pdo->exec("CREATE TRIGGER fail_insert BEFORE INSERT ON smart_documents WHEN NEW.local_id='db-failure'
        BEGIN SELECT RAISE(FAIL, 'injected database failure'); END");
    try { aims_store_smart_document($pdo, $root, document('db-failure')); throw new RuntimeException('DB failure ignored'); }
    catch (PDOException) {}
    check(files($root) === $before, 'database rollback removes only owned image');
    file_put_contents($before[0], 'damaged');
    try { aims_store_smart_document($pdo, $root, document('partial')); throw new RuntimeException('damaged image acknowledged'); }
    catch (AimsSmartDocumentException $error) { check($error->getMessage() === 'stored_image_unavailable', 'damaged image detected'); }
    file_put_contents($before[0], document('partial')['bytes']);
    $workers = [];
    for ($i = 0; $i < 8; $i++) {
        $process = proc_open([PHP_BINARY, __FILE__, '--worker', $root], [0 => ['pipe','r'], 1 => ['pipe','w'], 2 => ['pipe','w']], $pipes);
        check(is_resource($process), 'worker started'); fclose($pipes[0]); $workers[] = [$process, $pipes];
    }
    touch($root . '/go');
    $ids = []; $duplicates = 0;
    foreach ($workers as [$process, $pipes]) {
        $output = stream_get_contents($pipes[1]); $error = stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]);
        check(proc_close($process) === 0, 'worker failed: ' . $error);
        $result = json_decode($output, true, 512, JSON_THROW_ON_ERROR);
        $ids[] = $result['documentId']; $duplicates += (int)$result['duplicate'];
    }
    check(count(array_unique($ids)) === 1 && $duplicates === 7, '8 concurrent requests share one document');
    check(count(files($root)) === 2, 'one image per successful document, no temporary files');
    $row = $pdo->query("SELECT * FROM smart_documents WHERE local_id='concurrent'")->fetch(PDO::FETCH_ASSOC);
    check(file_get_contents($root . '/' . $row['image_path']) === document('concurrent')['bytes'], 'concurrent image survives');
    check((int)$pdo->query('SELECT count(*) FROM smart_documents')->fetchColumn() === 3, 'failed writes never become rows');
    echo "SMART STORAGE: MIGRATION, SHORT WRITES, ROLLBACK, OWNER, REPLAY, CORRUPTION AND 8-PROCESS RACE PASSED\n";
} finally {
    $pdo = null;
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST) as $file) {
        $file->isDir() ? rmdir($file->getPathname()) : unlink($file->getPathname());
    }
    rmdir($root);
}
