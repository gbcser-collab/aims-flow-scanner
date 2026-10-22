<?php
declare(strict_types=1);

final class AimsSmartDocumentException extends RuntimeException {
    public function __construct(string $reason, public readonly int $status = 500) {
        parent::__construct($reason);
    }
}

function aims_smart_document_schema(PDO $pdo): void {
    $columns = array_column($pdo->query('PRAGMA table_info(smart_documents)')->fetchAll(PDO::FETCH_ASSOC), 'name');
    if (in_array('flow_id', $columns, true) && in_array('payload_hash', $columns, true)) return;
    $pdo->exec('BEGIN IMMEDIATE');
    try {
        // A concurrent first request may already have completed the migration.
        $columns = array_column($pdo->query('PRAGMA table_info(smart_documents)')->fetchAll(PDO::FETCH_ASSOC), 'name');
        foreach (['flow_id', 'payload_hash'] as $name) {
            if (!in_array($name, $columns, true)) {
                $pdo->exec("ALTER TABLE smart_documents ADD COLUMN $name TEXT NOT NULL DEFAULT ''");
            }
        }
        $pdo->exec('COMMIT');
    } catch (Throwable $error) {
        try { $pdo->exec('ROLLBACK'); } catch (Throwable) {}
        throw $error;
    }
}

/** Write all bytes, flush, then publish a private, request-owned image. */
function aims_smart_write_image(string $dir, string $extension, string $bytes, ?callable $writer = null): string {
    if (!is_dir($dir) && !@mkdir($dir, 0700, true) && !is_dir($dir)) {
        throw new AimsSmartDocumentException('storage_dir');
    }
    $path = $dir . '/' . bin2hex(random_bytes(24)) . '.' . $extension;
    $temporary = $path . '.tmp';
    $stream = @fopen($temporary, 'xb');
    if ($stream === false) throw new AimsSmartDocumentException('image_write_failed');
    try {
        if (!@chmod($temporary, 0600)) throw new AimsSmartDocumentException('image_permissions_failed');
        $offset = 0;
        $length = strlen($bytes);
        while ($offset < $length) {
            $chunk = substr($bytes, $offset, 1048576);
            $written = $writer === null ? @fwrite($stream, $chunk) : $writer($stream, $chunk);
            if (!is_int($written) || $written <= 0 || $written > strlen($chunk)) {
                throw new AimsSmartDocumentException('image_write_failed');
            }
            $offset += $written;
        }
        if (!fflush($stream) || !fsync($stream)) throw new AimsSmartDocumentException('image_flush_failed');
        fclose($stream);
        $stream = null;
        if (!@rename($temporary, $path)) throw new AimsSmartDocumentException('image_publish_failed');
        return $path;
    } finally {
        if (is_resource($stream)) fclose($stream);
        if (is_file($temporary)) @unlink($temporary);
    }
}

/** The write lock covers duplicate validation, image publication and DB insert. */
function aims_store_smart_document(PDO $pdo, string $dataDir, array $document, ?callable $writer = null): array {
    $imageHash = hash('sha256', $document['bytes']);
    $payloadHash = hash('sha256', json_encode([
        $document['vehicleId'], $document['flowId'], $document['type'],
        $document['capturedAt'], $document['ocrText'], $document['confidence'], $imageHash,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    $ownedImage = null;
    $transaction = false;
    try {
        $pdo->exec('PRAGMA synchronous=FULL');
        $pdo->exec('BEGIN IMMEDIATE');
        $transaction = true;
        $existing = $pdo->prepare('SELECT * FROM smart_documents WHERE local_id=:local LIMIT 1');
        $existing->execute([':local' => $document['localId']]);
        $row = $existing->fetch(PDO::FETCH_ASSOC);
        $existing->closeCursor();
        if ($row) {
            if ((int)$row['vehicle_id'] !== $document['vehicleId'] ||
                ($row['flow_id'] !== '' && !hash_equals((string)$row['flow_id'], $document['flowId']))) {
                throw new AimsSmartDocumentException('document_identity_conflict', 409);
            }
            // Preserve old records; never invent the original driver's identity.
            if ($row['payload_hash'] === '') {
                throw new AimsSmartDocumentException('document_owner_unverified', 409);
            }
            if (!hash_equals((string)$row['payload_hash'], $payloadHash)) {
                throw new AimsSmartDocumentException('document_identity_conflict', 409);
            }
            $storedPath = $dataDir . '/' . $row['image_path'];
            $storedHash = is_file($storedPath) ? @hash_file('sha256', $storedPath) : false;
            if (!is_string($storedHash) || !hash_equals($imageHash, $storedHash)) {
                throw new AimsSmartDocumentException('stored_image_unavailable');
            }
            $pdo->exec('COMMIT');
            $transaction = false;
            return ['documentId' => (string)$row['id'], 'localId' => $document['localId'],
                'state' => 'uploaded', 'duplicate' => true];
        }
        $date = new DateTimeImmutable($document['capturedAt']);
        $relativeDir = 'smart-documents/' . $document['plate'] . '/' . $date->format('Y/m');
        $ownedImage = aims_smart_write_image($dataDir . '/' . $relativeDir,
            $document['extension'], $document['bytes'], $writer);
        $relativePath = $relativeDir . '/' . basename($ownedImage);
        $insert = $pdo->prepare('INSERT INTO smart_documents
            (local_id,vehicle_id,flow_id,payload_hash,document_type,captured_at,ocr_text,confidence,image_path,created_at)
            VALUES (:local,:vehicle,:flow,:hash,:type,:captured,:ocr,:confidence,:path,:created)');
        $insert->execute([
            ':local' => $document['localId'], ':vehicle' => $document['vehicleId'],
            ':flow' => $document['flowId'], ':hash' => $payloadHash, ':type' => $document['type'],
            ':captured' => $document['capturedAt'], ':ocr' => $document['ocrText'],
            ':confidence' => $document['confidence'], ':path' => $relativePath,
            ':created' => gmdate(DateTimeInterface::ATOM),
        ]);
        $id = (string)$pdo->lastInsertId();
        $pdo->exec('COMMIT');
        $transaction = false;
        return ['documentId' => $id, 'localId' => $document['localId'], 'state' => 'uploaded', 'duplicate' => false];
    } catch (Throwable $error) {
        $rolledBack = false;
        if ($transaction) {
            try { $pdo->exec('ROLLBACK'); $rolledBack = true; } catch (Throwable) {}
        }
        // Never remove another request's image, or one with an uncertain commit.
        if ($rolledBack && $ownedImage !== null) @unlink($ownedImage);
        throw $error;
    }
}
