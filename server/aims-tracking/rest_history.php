<?php
declare(strict_types=1);

// Rest belongs to the authenticated driver at capture time, never to the
// vehicle's current assignee when a historical report is generated.
function aims_rest_history_schema(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS driver_rest_periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL,
        flow_id TEXT NOT NULL DEFAULT "",
        started_at TEXT NOT NULL,
        planned_until TEXT NOT NULL,
        ended_at TEXT,
        FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_rest_driver_time
        ON driver_rest_periods(flow_id, vehicle_id, started_at)');
    $pdo->exec('CREATE TABLE IF NOT EXISTS report_capture_metadata (
        name TEXT PRIMARY KEY, started_at TEXT NOT NULL
    )');
    $pdo->prepare('INSERT OR IGNORE INTO report_capture_metadata(name,started_at)
        VALUES ("rest_history",:now)')->execute([':now'=>gmdate(DateTimeInterface::ATOM)]);
}

function aims_rest_history_finish(PDO $pdo, int $vehicleId, DateTimeImmutable $end): void {
    $stmt = $pdo->prepare('SELECT id,started_at,planned_until FROM driver_rest_periods
        WHERE vehicle_id=:vehicle AND ended_at IS NULL');
    $stmt->execute([':vehicle'=>$vehicleId]);
    $update = $pdo->prepare('UPDATE driver_rest_periods SET ended_at=:end
        WHERE id=:id AND ended_at IS NULL');
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $start = new DateTimeImmutable($row['started_at']);
        $planned = new DateTimeImmutable($row['planned_until']);
        $bounded = max($start->getTimestamp(), min($end->getTimestamp(), $planned->getTimestamp()));
        $update->execute([':end'=>gmdate(DateTimeInterface::ATOM,$bounded), ':id'=>(int)$row['id']]);
    }
}

function aims_rest_history_begin(
    PDO $pdo, int $vehicleId, string $flowId, DateTimeImmutable $now, DateTimeImmutable $until
): string {
    if (!preg_match('/^\d{6}$/', $flowId)) $flowId = '';
    $stmt = $pdo->prepare('SELECT * FROM driver_rest_periods
        WHERE vehicle_id=:vehicle AND ended_at IS NULL ORDER BY id DESC LIMIT 1');
    $stmt->execute([':vehicle'=>$vehicleId]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($existing && $existing['flow_id'] === $flowId
        && new DateTimeImmutable($existing['planned_until']) > $now) {
        $pdo->prepare('UPDATE driver_rest_periods SET planned_until=:until WHERE id=:id')
            ->execute([':until'=>$until->format(DateTimeInterface::ATOM), ':id'=>$existing['id']]);
        return $existing['started_at'];
    }
    aims_rest_history_finish($pdo, $vehicleId, $now);
    $start = $now->format(DateTimeInterface::ATOM);
    $pdo->prepare('INSERT INTO driver_rest_periods(vehicle_id,flow_id,started_at,planned_until)
        VALUES (:vehicle,:flow,:start,:until)')->execute([
            ':vehicle'=>$vehicleId, ':flow'=>$flowId, ':start'=>$start,
            ':until'=>$until->format(DateTimeInterface::ATOM),
        ]);
    return $start;
}

/** Union of half-open Unix timestamp intervals, without duplicate seconds. */
function aims_time_union(array $intervals): array {
    usort($intervals, static fn(array $a, array $b): int => $a[0] <=> $b[0]);
    $merged = [];
    foreach ($intervals as [$start,$end]) {
        if ($end <= $start) continue;
        $last = count($merged)-1;
        if ($last >= 0 && $start <= $merged[$last][1]) {
            $merged[$last][1] = max($merged[$last][1], $end);
        } else {
            $merged[] = [$start,$end];
        }
    }
    return $merged;
}

function aims_time_subtract(array $work, array $rest): array {
    $result = [];
    $rests = aims_time_union($rest);
    foreach (aims_time_union($work) as [$start,$end]) {
        foreach ($rests as [$rs,$re]) {
            if ($re <= $start) continue;
            if ($rs >= $end) break;
            if ($rs > $start) $result[] = [$start,min($rs,$end)];
            $start = max($start,$re);
            if ($start >= $end) break;
        }
        if ($start < $end) $result[] = [$start,$end];
    }
    return $result;
}

function aims_time_seconds(array $intervals): int {
    $seconds = 0;
    foreach (aims_time_union($intervals) as [$start,$end]) $seconds += $end-$start;
    return $seconds;
}
