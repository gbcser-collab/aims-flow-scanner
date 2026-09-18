<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$pdo = aims_db();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'POST') {
    aims_require_token('AIMS_TRACKING_TOKEN');
    $data = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($data)) aims_json(['ok' => false, 'error' => 'invalid_json'], 400);

    $deviceId = trim((string)($data['deviceId'] ?? ''));
    $plateDisplay = trim((string)($data['plate'] ?? ''));
    $vehicle = aims_vehicle_for_point($pdo, $deviceId, $plateDisplay);
    if (!$vehicle) aims_json(['ok' => false, 'error' => 'vehicle_not_registered'], 409);

    $image = $data['image'] ?? null;
    if (!is_array($image)) aims_json(['ok' => false, 'error' => 'missing_image'], 422);
    $bytes = base64_decode((string)($image['base64'] ?? ''), true);
    if ($bytes === false || strlen($bytes) < 60 || strlen($bytes) > 10 * 1024 * 1024) {
        aims_json(['ok' => false, 'error' => 'invalid_image'], 422);
    }

    $imageInfo = @getimagesizefromstring($bytes);
    $detectedMime = is_array($imageInfo) ? (string)($imageInfo['mime'] ?? '') : '';
    if (!in_array($detectedMime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
        aims_json(['ok' => false, 'error' => 'unsupported_image'], 422);
    }
    $mime = $detectedMime;
    $ext = match ($mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        default => 'jpg',
    };

    $capturedText = trim((string)($data['capturedAt'] ?? ''));
    try {
        $captured = $capturedText === '' ? new DateTimeImmutable('now', new DateTimeZone('UTC')) : new DateTimeImmutable($capturedText);
        $captured = $captured->setTimezone(new DateTimeZone('UTC'));
    } catch (Throwable) {
        aims_json(['ok' => false, 'error' => 'invalid_timestamp'], 422);
    }

    $dir = __DIR__ . '/data/fuel';
    if (!is_dir($dir)) mkdir($dir, 0700, true);
    $fileName = bin2hex(random_bytes(18)) . '.' . $ext;
    $path = $dir . '/' . $fileName;
    if (file_put_contents($path, $bytes, LOCK_EX) === false) {
        aims_json(['ok' => false, 'error' => 'image_write_failed'], 500);
    }
    @chmod($path, 0600);

    $station = mb_substr(trim((string)($data['station'] ?? '')), 0, 200);
    $currency = mb_substr(strtoupper(trim((string)($data['currency'] ?? ''))), 0, 8);
    $receiptNumber = mb_substr(trim((string)($data['receiptNumber'] ?? '')), 0, 120);
    $ocr = mb_substr((string)($data['ocrText'] ?? ''), 0, 40000);
    $total = isset($data['totalAmount']) ? (float)$data['totalAmount'] : null;
    $liters = isset($data['liters']) ? (float)$data['liters'] : null;
    $unitPrice = isset($data['pricePerLiter']) ? (float)$data['pricePerLiter'] : null;

    try {
        $stmt = $pdo->prepare('INSERT INTO fuel_receipts
            (vehicle_id, admin_user_id, captured_at, station, total_amount, currency, liters,
             price_per_liter, receipt_number, ocr_text, image_path, created_at)
            VALUES (:vehicle, :admin, :captured, :station, :total, :currency, :liters,
                    :unit, :receipt, :ocr, :path, :created)');
        $stmt->execute([
            ':vehicle' => $vehicle['id'],
            ':admin' => $vehicle['admin_user_id'],
            ':captured' => $captured->format(DateTimeInterface::ATOM),
            ':station' => $station === '' ? null : $station,
            ':total' => $total,
            ':currency' => $currency === '' ? null : $currency,
            ':liters' => $liters,
            ':unit' => $unitPrice,
            ':receipt' => $receiptNumber === '' ? null : $receiptNumber,
            ':ocr' => $ocr === '' ? null : $ocr,
            ':path' => $fileName,
            ':created' => gmdate(DateTimeInterface::ATOM),
        ]);
        $id = (int)$pdo->lastInsertId();

        $plate = $vehicle['label'] !== '' ? $vehicle['label'] : $vehicle['plate'];
        $summary = [];
        if ($liters !== null) $summary[] = rtrim(rtrim(number_format($liters, 2, '.', ''), '0'), '.') . ' l';
        if ($total !== null) $summary[] = rtrim(rtrim(number_format($total, 2, '.', ''), '0'), '.') . ($currency !== '' ? " $currency" : '');
        if ($station !== '') $summary[] = $station;
        aims_notify(
            $pdo,
            (int)$vehicle['admin_user_id'],
            (int)$vehicle['id'],
            'fuel_receipt',
            'success',
            "$plate tankolási bizonylat érkezett",
            $summary ? implode(' • ', $summary) : 'A bizonylat megérkezett a főnökségi rendszerbe.',
            "fuel_receipt:$id",
            ['fuelReceiptId' => $id]
        );
    } catch (Throwable $error) {
        @unlink($path);
        error_log('AIMS fuel receipt: ' . $error->getMessage());
        aims_json(['ok' => false, 'error' => 'storage_error'], 500);
    }

    aims_try_push($pdo, 8);
    aims_json(['ok' => true, 'fuelReceiptId' => $id]);
}

if ($method === 'GET') {
    $adminId = aims_admin_user_id($pdo);
    $id = max(0, (int)($_GET['id'] ?? 0));
    $imageOnly = ($_GET['image'] ?? '0') === '1';

    if ($imageOnly && $id > 0) {
        $stmt = $pdo->prepare('SELECT * FROM fuel_receipts WHERE id = :id AND admin_user_id = :admin');
        $stmt->execute([':id' => $id, ':admin' => $adminId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) aims_json(['ok' => false, 'error' => 'not_found'], 404);
        $path = __DIR__ . '/data/fuel/' . basename((string)$row['image_path']);
        if (!is_file($path)) aims_json(['ok' => false, 'error' => 'image_not_found'], 404);
        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        header('Cache-Control: no-store');
        header('Content-Type: ' . ($ext === 'png' ? 'image/png' : ($ext === 'webp' ? 'image/webp' : 'image/jpeg')));
        readfile($path);
        exit;
    }

    $stmt = $pdo->prepare('SELECT f.id, f.captured_at, f.station, f.total_amount, f.currency,
                                  f.liters, f.price_per_liter, f.receipt_number, f.created_at,
                                  v.plate, v.label
                           FROM fuel_receipts f
                           JOIN vehicles v ON v.id = f.vehicle_id
                           WHERE f.admin_user_id = :admin
                           ORDER BY f.id DESC LIMIT 100');
    $stmt->execute([':admin' => $adminId]);
    $items = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $items[] = [
            'id' => (int)$row['id'],
            'plate' => $row['label'] !== '' ? $row['label'] : $row['plate'],
            'capturedAt' => $row['captured_at'],
            'station' => $row['station'],
            'totalAmount' => $row['total_amount'] === null ? null : (float)$row['total_amount'],
            'currency' => $row['currency'],
            'liters' => $row['liters'] === null ? null : (float)$row['liters'],
            'pricePerLiter' => $row['price_per_liter'] === null ? null : (float)$row['price_per_liter'],
            'receiptNumber' => $row['receipt_number'],
            'createdAt' => $row['created_at'],
        ];
    }
    aims_json(['ok' => true, 'receipts' => $items]);
}

header('Allow: GET, POST');
aims_json(['ok' => false, 'error' => 'method_not_allowed'], 405);
