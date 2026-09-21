<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) {
    aims_json(['ok' => false, 'error' => 'invalid_json'], 400);
}

$plate = aims_normalize_plate((string)($data['plate'] ?? ''));
$localId = trim((string)($data['localId'] ?? ''));
$type = trim((string)($data['type'] ?? 'other'));
$capturedAtRaw = trim((string)($data['capturedAt'] ?? ''));
$ocrText = trim((string)($data['ocrText'] ?? ''));
$confidence = isset($data['confidence']) && is_numeric($data['confidence'])
    ? max(0.0, min(1.0, (float)$data['confidence']))
    : null;
$image = $data['image'] ?? null;

$allowedTypes = [
    'pod',
    'delivery_note',
    'customs',
    'pallet_exchange',
    'other',
];
if ($plate === '' || $localId === '' || strlen($localId) > 160) {
    aims_json(['ok' => false, 'error' => 'invalid_payload'], 422);
}
if (!in_array($type, $allowedTypes, true)) {
    aims_json(['ok' => false, 'error' => 'unsupported_document_type'], 422);
}
if (!is_array($image)) {
    aims_json(['ok' => false, 'error' => 'missing_image'], 422);
}

try {
    $capturedAt = $capturedAtRaw === ''
        ? new DateTimeImmutable('now', new DateTimeZone('UTC'))
        : (new DateTimeImmutable($capturedAtRaw))->setTimezone(new DateTimeZone('UTC'));
} catch (Throwable) {
    aims_json(['ok' => false, 'error' => 'invalid_captured_at'], 422);
}

$bytes = base64_decode((string)($image['base64'] ?? ''), true);
if ($bytes === false || strlen($bytes) < 60 || strlen($bytes) > 12 * 1024 * 1024) {
    aims_json(['ok' => false, 'error' => 'invalid_image'], 422);
}
$info = @getimagesizefromstring($bytes);
$mime = is_array($info) ? (string)($info['mime'] ?? '') : '';
if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
    aims_json(['ok' => false, 'error' => 'unsupported_image'], 422);
}
$ext = $mime === 'image/png' ? 'png' : ($mime === 'image/webp' ? 'webp' : 'jpg');

$pdo = aims_db();
$stmt = $pdo->prepare('SELECT * FROM vehicles
    WHERE plate = :plate AND enabled = 1 LIMIT 1');
$stmt->execute([':plate' => $plate]);
$vehicle = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) {
    aims_json(['ok' => false, 'error' => 'vehicle_not_registered'], 404);
}

$existing = $pdo->prepare('SELECT id FROM smart_documents
    WHERE local_id = :local LIMIT 1');
$existing->execute([':local' => $localId]);
$existingId = $existing->fetchColumn();
if ($existingId !== false) {
    aims_json([
        'ok' => true,
        'documentId' => (string)$existingId,
        'state' => 'uploaded',
        'duplicate' => true,
    ]);
}

$dataDir = trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: ''));
if ($dataDir === '') {
    $dataDir = __DIR__ . '/data';
}
$year = $capturedAt->format('Y');
$month = $capturedAt->format('m');
$vehicleDir = preg_replace('/[^A-Za-z0-9_-]/', '_', $plate) ?: 'vehicle';
$dir = $dataDir . '/smart-documents/' . $vehicleDir . '/' . $year . '/' . $month;
if (!is_dir($dir) && !@mkdir($dir, 0700, true)) {
    aims_json(['ok' => false, 'error' => 'storage_dir'], 500);
}

$safeLocal = preg_replace('/[^A-Za-z0-9_-]/', '_', $localId) ?: bin2hex(random_bytes(8));
$filename = $safeLocal . '.' . $ext;
$destination = $dir . '/' . $filename;
if (file_put_contents($destination, $bytes, LOCK_EX) === false) {
    aims_json(['ok' => false, 'error' => 'image_write_failed'], 500);
}
@chmod($destination, 0600);

$relativePath = 'smart-documents/' . $vehicleDir . '/' . $year . '/' . $month . '/' . $filename;

try {
    $insert = $pdo->prepare('INSERT INTO smart_documents
        (local_id, vehicle_id, document_type, captured_at, ocr_text,
         confidence, image_path, created_at)
        VALUES (:local, :vehicle, :type, :captured, :ocr, :confidence, :path, :created)');
    $insert->execute([
        ':local' => $localId,
        ':vehicle' => (int)$vehicle['id'],
        ':type' => $type,
        ':captured' => $capturedAt->format(DateTimeInterface::ATOM),
        ':ocr' => mb_substr($ocrText, 0, 40000, 'UTF-8'),
        ':confidence' => $confidence,
        ':path' => $relativePath,
        ':created' => gmdate(DateTimeInterface::ATOM),
    ]);
    $documentId = (string)$pdo->lastInsertId();
} catch (Throwable $error) {
    @unlink($destination);
    error_log('AIMS smart document: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}

$label = trim((string)($vehicle['label'] ?? '')) !== ''
    ? (string)$vehicle['label']
    : (string)$vehicle['plate'];
$typeLabel = [
    'pod' => 'POD',
    'delivery_note' => 'szállítólevél',
    'customs' => 'vámokmány',
    'pallet_exchange' => 'raklapcsere-papír',
    'other' => 'egyéb dokumentum',
][$type] ?? $type;

aims_notify(
    $pdo,
    (int)$vehicle['admin_user_id'],
    (int)$vehicle['id'],
    'smart_document',
    'success',
    "$label · új dokumentum",
    $typeLabel . ' • AIMS Flow Smart Scanner',
    'smart_document:' . $localId,
    [
        'documentId' => $documentId,
        'localId' => $localId,
        'documentType' => $type,
        'confidence' => $confidence,
        'capturedAt' => $capturedAt->format(DateTimeInterface::ATOM),
    ]
);
aims_try_push($pdo, 8);

aims_json([
    'ok' => true,
    'documentId' => $documentId,
    'state' => 'uploaded',
    'duplicate' => false,
]);
