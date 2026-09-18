<?php
declare(strict_types=1);
require dirname(__DIR__) . '/smart_rules.php';

function check(bool $value, string $message): void {
    if (!$value) {
        fwrite(STDERR, "FAIL: $message\n");
        exit(1);
    }
}

check(count(aims_due_stop_alerts(14 * 60 + 59, 0)) === 0, 'No alert before 15 min');
check(array_column(aims_due_stop_alerts(15 * 60, 0), 'minutes') === [15], '15 min alert');
check(array_column(aims_due_stop_alerts(30 * 60, 1), 'minutes') === [30], '30 min alert after 15');
check(array_column(aims_due_stop_alerts(60 * 60, 3), 'minutes') === [60], '60 min alert after 15/30');
check(array_column(aims_due_stop_alerts(60 * 60, 0), 'minutes') === [60], 'Reconnect catch-up emits only highest threshold');
check(count(aims_due_stop_alerts(2 * 60 * 60, 7)) === 0, 'No duplicate alerts after all stages sent');

check(aims_motion_detected(47.0, 18.0, 47.000055, 18.0, 5.0, 0.1), 'About six metres of credible movement resets timer');
check(!aims_motion_detected(47.0, 18.0, 47.00002, 18.0, 18.0, 0.1), 'GPS jitter does not reset timer');
check(aims_motion_detected(47.0, 18.0, 47.0, 18.0, 20.0, 1.0), 'Speed signal resets timer');

check(aims_inside_geofence(47.0, 18.0, 47.0005, 18.0, 180.0, 5.0), 'Nearby point inside geofence');
check(!aims_inside_geofence(47.0, 18.0, 47.005, 18.0, 180.0, 5.0), 'Far point outside geofence');

echo "tracking rules: PASS\n";
