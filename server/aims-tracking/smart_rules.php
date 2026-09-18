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
    return $due;
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
