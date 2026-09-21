<?php
declare(strict_types=1);

function aims_distance_m(float $lat1, float $lng1, float $lat2, float $lng2): float {
    $earth = 6371000.0;
    $p1 = deg2rad($lat1);
    $p2 = deg2rad($lat2);
    $dp = deg2rad($lat2 - $lat1);
    $dl = deg2rad($lng2 - $lng1);
    $a = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;
    return $earth * 2 * atan2(sqrt($a), sqrt(max(0.0, 1.0 - $a)));
}

function aims_motion_threshold_m(?float $accuracy): float {
    $accuracy = $accuracy === null ? 12.0 : max(3.0, min(60.0, $accuracy));
    // Conservative against GPS jitter, but a credible small movement still resets the timer.
    return max(5.0, min(15.0, $accuracy * 0.50));
}

function aims_motion_detected(
    float $anchorLat,
    float $anchorLng,
    float $lat,
    float $lng,
    ?float $accuracy,
    ?float $speedMps
): bool {
    if ($speedMps !== null && $speedMps >= 0.8) return true; // ~2.9 km/h
    return aims_distance_m($anchorLat, $anchorLng, $lat, $lng) >= aims_motion_threshold_m($accuracy);
}

function aims_due_stop_alerts(int $stationarySeconds, int $sentMask): array {
    $thresholds = [
        ['seconds' => 15 * 60, 'minutes' => 15, 'bit' => 1],
        ['seconds' => 30 * 60, 'minutes' => 30, 'bit' => 2],
        ['seconds' => 60 * 60, 'minutes' => 60, 'bit' => 4],
    ];
    $due = [];
    foreach ($thresholds as $threshold) {
        if ($stationarySeconds >= $threshold['seconds'] && ($sentMask & $threshold['bit']) === 0) {
            $due[] = $threshold;
        }
    }
    if (count($due) <= 1) return $due;
    // After an offline/reconnect gap, do not burst 15+30+60 at once.
    return [end($due)];
}


function aims_due_job_waiting_slot(int $waitingSeconds, int $lastSlot): ?array {
    $slot = intdiv(max(0, $waitingSeconds), 20 * 60);
    if ($slot < 1 || $slot <= $lastSlot) return null;
    return [
        'slot' => $slot,
        'minutes' => $slot * 20,
    ];
}

function aims_geofence_radius_m(float $configuredRadius, ?float $accuracy): float {
    $gpsRadius = $accuracy === null ? 0.0 : min(350.0, max(0.0, $accuracy * 2.0));
    return max($configuredRadius, $gpsRadius);
}

function aims_inside_geofence(
    float $lat,
    float $lng,
    float $stopLat,
    float $stopLng,
    float $configuredRadius,
    ?float $accuracy
): bool {
    return aims_distance_m($lat, $lng, $stopLat, $stopLng)
        <= aims_geofence_radius_m($configuredRadius, $accuracy);
}

function aims_geocode_address_candidates(string $address): array {
    $original = trim(preg_replace('/\s+/u', ' ', $address) ?: '');
    if ($original === '') return [];

    $candidates = [$original];

    // Many European addresses arrive as "street house, 123 45 City".
    // Nominatim can reject that exact shape even when the street + city is
    // valid, so retry without only the postal-code token.
    $withoutPostal = preg_replace(
        '/,\s*[0-9]{3}\s?[0-9]{2}\s+(?=\S)/u',
        ', ',
        $original
    );
    $withoutPostal = trim((string)$withoutPostal);
    if ($withoutPostal !== '' && !in_array($withoutPostal, $candidates, true)) {
        $candidates[] = $withoutPostal;
    }

    // Accentless fallback is useful for partner PDFs and foreign keyboards,
    // but keep the street + house number + city intact to avoid city-only
    // false positives.
    foreach (array_values($candidates) as $candidate) {
        $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $candidate);
        if (!is_string($ascii)) continue;
        $ascii = trim(preg_replace('/\s+/', ' ', $ascii) ?: '');
        if ($ascii !== '' && !in_array($ascii, $candidates, true)) {
            $candidates[] = $ascii;
        }
    }

    return $candidates;
}

