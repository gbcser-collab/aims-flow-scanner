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
$flowId = trim((string)($_SERVER['AIMS_FLOW_DRIVER_FLOW_ID'] ?? ''));
$claimedOwner = trim((string)($data['flowId'] ?? ''));
if ($flowId !== '' && $claimedOwner !== '' && !hash_equals($flowId, $claimedOwner)) {
    aims_json(['ok' => false, 'error' => 'document_owner_forbidden'], 403);
}
// Server-only legacy calls can retain an unassigned owner, never trust a claim.
if ($flowId !== '' && preg_match('/^smart_(\d{6})_/', $localId, $idOwner) &&
    !hash_equals($flowId, $idOwner[1])) {
    aims_json(['ok' => false, 'error' => 'document_owner_forbidden'], 403);
}
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

$dataDir = rtrim(trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: '')), '/');
if ($dataDir === '') $dataDir = __DIR__ . '/data';
try {
    $stored = aims_store_smart_document($pdo, $dataDir, [
        'localId' => $localId, 'vehicleId' => (int)$vehicle['id'], 'plate' => $plate,
        'flowId' => $flowId, 'type' => $type,
        'capturedAt' => $capturedAt->format('Y-m-d\\TH:i:s.uP'),
        'ocrText' => mb_substr($ocrText, 0, 40000, 'UTF-8'),
        'confidence' => $confidence, 'extension' => $ext, 'bytes' => $bytes,
    ]);
} catch (AimsSmartDocumentException $error) {
    aims_json(['ok' => false, 'error' => $error->getMessage()], $error->status);
} catch (Throwable $error) {
    error_log('AIMS smart document: ' . $error->getMessage());
    aims_json(['ok' => false, 'error' => 'storage_error'], 500);
}
if ($stored['duplicate']) aims_json(['ok' => true] + $stored);
$documentId = $stored['documentId'];

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

try {
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
} catch (Throwable $error) {
    // Notification failure must not revoke a durably accepted document.
    error_log('AIMS smart document notification: ' . $error->getMessage());
}

aims_json(['ok' => true] + $stored);
