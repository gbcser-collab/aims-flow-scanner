<?php
declare(strict_types=1);

function aims_process_country_stay(
    PDO $pdo,
    array $vehicle,
    string $countryCode,
    float $lat,
    float $lng,
    DateTimeImmutable $captured,
    bool $emitNotifications = true
): int {
    if ($countryCode === '') return 0;

    $vehicleId = (int)$vehicle['id'];
    $stamp = $captured->format(DateTimeInterface::ATOM);
    $now = gmdate(DateTimeInterface::ATOM);

    $stateStmt = $pdo->prepare(
        'SELECT * FROM vehicle_country_state WHERE vehicle_id = :vehicle'
    );
    $stateStmt->execute([':vehicle' => $vehicleId]);
    $state = $stateStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    if ($state === null ||
        trim((string)($state['confirmed_country_code'] ?? '')) === '') {
        $insertState = $pdo->prepare('INSERT INTO vehicle_country_state
            (vehicle_id, confirmed_country_code, candidate_country_code,
             candidate_since, candidate_hits, last_observed_at,
             last_latitude, last_longitude, updated_at)
            VALUES (:vehicle, :country, NULL, NULL, 0, :observed,
                    :lat, :lng, :updated)
            ON CONFLICT(vehicle_id) DO UPDATE SET
              confirmed_country_code=excluded.confirmed_country_code,
              candidate_country_code=NULL,
              candidate_since=NULL,
              candidate_hits=0,
              last_observed_at=excluded.last_observed_at,
              last_latitude=excluded.last_latitude,
              last_longitude=excluded.last_longitude,
              updated_at=excluded.updated_at');
        $insertState->execute([
            ':vehicle' => $vehicleId,
            ':country' => $countryCode,
            ':observed' => $stamp,
            ':lat' => $lat,
            ':lng' => $lng,
            ':updated' => $now,
        ]);
        $open = $pdo->prepare('SELECT id FROM country_stays
            WHERE vehicle_id = :vehicle AND exited_at IS NULL
            ORDER BY id DESC LIMIT 1');
        $open->execute([':vehicle' => $vehicleId]);

        if ($open->fetchColumn() === false) {
            $stay = $pdo->prepare('INSERT INTO country_stays
                (vehicle_id, country_code, entered_at, exited_at,
                 entry_latitude, entry_longitude, transition_from,
                 confirmed_at, created_at)
                VALUES (:vehicle, :country, :entered, NULL,
                        :lat, :lng, NULL, :confirmed, :created)');
            $stay->execute([
                ':vehicle' => $vehicleId,
                ':country' => $countryCode,
                ':entered' => $stamp,
                ':lat' => $lat,
                ':lng' => $lng,
                ':confirmed' => $stamp,
                ':created' => $now,
            ]);
        }
        return 0;
    }
    $lastObserved = trim((string)($state['last_observed_at'] ?? ''));
    if ($lastObserved !== '') {
        try {
            if ($captured <= new DateTimeImmutable($lastObserved)) return 0;
        } catch (Throwable) {
        }
    }

    $confirmed = strtoupper(
        trim((string)$state['confirmed_country_code'])
    );

    if ($countryCode === $confirmed) {
        $reset = $pdo->prepare('UPDATE vehicle_country_state SET
            candidate_country_code=NULL,
            candidate_since=NULL,
            candidate_hits=0,
            last_observed_at=:observed,
            last_latitude=:lat,
            last_longitude=:lng,
            updated_at=:updated
            WHERE vehicle_id=:vehicle');
        $reset->execute([
            ':observed' => $stamp,
            ':lat' => $lat,
            ':lng' => $lng,
            ':updated' => $now,
            ':vehicle' => $vehicleId,
        ]);
        return 0;
    }
    $candidate = strtoupper(
        trim((string)($state['candidate_country_code'] ?? ''))
    );

    if ($candidate !== $countryCode) {
        $start = $pdo->prepare('UPDATE vehicle_country_state SET
            candidate_country_code=:country,
            candidate_since=:since,
            candidate_hits=1,
            last_observed_at=:observed,
            last_latitude=:lat,
            last_longitude=:lng,
            updated_at=:updated
            WHERE vehicle_id=:vehicle');
        $start->execute([
            ':country' => $countryCode,
            ':since' => $stamp,
            ':observed' => $stamp,
            ':lat' => $lat,
            ':lng' => $lng,
            ':updated' => $now,
            ':vehicle' => $vehicleId,
        ]);
        return 0;
    }

    $hits = (int)($state['candidate_hits'] ?? 0) + 1;
    try {
        $candidateSince = new DateTimeImmutable(
            (string)$state['candidate_since']
        );
    } catch (Throwable) {
        $candidateSince = $captured;
    }

    $elapsed = max(
        0,
        $captured->getTimestamp() - $candidateSince->getTimestamp()
    );

    if ($hits < 4 || $elapsed < 90) {
        $pending = $pdo->prepare('UPDATE vehicle_country_state SET
            candidate_hits=:hits,
            last_observed_at=:observed,
            last_latitude=:lat,
            last_longitude=:lng,
            updated_at=:updated
            WHERE vehicle_id=:vehicle');
        $pending->execute([
            ':hits' => $hits,
            ':observed' => $stamp,
            ':lat' => $lat,
            ':lng' => $lng,
            ':updated' => $now,
            ':vehicle' => $vehicleId,
        ]);
        return 0;
    }
    $transitionAt = $candidateSince->format(DateTimeInterface::ATOM);

    $close = $pdo->prepare('UPDATE country_stays SET
        exited_at=:exited,
        exit_latitude=:lat,
        exit_longitude=:lng
        WHERE id = (
          SELECT id FROM country_stays
          WHERE vehicle_id=:vehicle AND exited_at IS NULL
          ORDER BY id DESC LIMIT 1
        )');
    $close->execute([
        ':exited' => $transitionAt,
        ':lat' => $lat,
        ':lng' => $lng,
        ':vehicle' => $vehicleId,
    ]);

    $open = $pdo->prepare('INSERT INTO country_stays
        (vehicle_id, country_code, entered_at, exited_at,
         entry_latitude, entry_longitude, transition_from,
         confirmed_at, created_at)
        VALUES (:vehicle, :country, :entered, NULL,
                :lat, :lng, :from_country, :confirmed, :created)');
    $open->execute([
        ':vehicle' => $vehicleId,
        ':country' => $countryCode,
        ':entered' => $transitionAt,
        ':lat' => $lat,
        ':lng' => $lng,
        ':from_country' => $confirmed,
        ':confirmed' => $stamp,
        ':created' => $now,
    ]);

    $confirm = $pdo->prepare('UPDATE vehicle_country_state SET
        confirmed_country_code=:country,
        candidate_country_code=NULL,
        candidate_since=NULL,
        candidate_hits=0,
        last_observed_at=:observed,
        last_latitude=:lat,
        last_longitude=:lng,
        updated_at=:updated
        WHERE vehicle_id=:vehicle');
    $confirm->execute([
        ':country' => $countryCode,
        ':observed' => $stamp,
        ':lat' => $lat,
        ':lng' => $lng,
        ':updated' => $now,
        ':vehicle' => $vehicleId,
    ]);
    if ($emitNotifications) {
        $plate = $vehicle['label'] !== ''
            ? $vehicle['label']
            : $vehicle['plate'];

        aims_notify(
            $pdo,
            (int)$vehicle['admin_user_id'],
            $vehicleId,
            'border_crossing',
            'info',
            "$plate határátlépés: $confirmed → $countryCode",
            "Rögzítve: $transitionAt",
            "border:$vehicleId:$transitionAt:$confirmed:$countryCode",
            [
                'fromCountry' => $confirmed,
                'toCountry' => $countryCode,
                'enteredAt' => $transitionAt,
                'confirmedAt' => $stamp,
                'latitude' => $lat,
                'longitude' => $lng,
            ]
        );
    }

    return 1;
}