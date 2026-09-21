<?php
declare(strict_types=1);

require __DIR__ . '/smart_rules.php';

function assert_same(mixed $expected, mixed $actual, string $label): void {
    if ($expected !== $actual) {
        fwrite(STDERR, "FAIL: $label\nExpected: " . var_export($expected, true) . "\nActual: " . var_export($actual, true) . "\n");
        exit(1);
    }
}

assert_same(20 * 60, aims_effective_waiting_seconds(80 * 60, 60 * 60), 'rest time excluded from waiting');
assert_same(0, aims_effective_waiting_seconds(20 * 60, 30 * 60), 'rest cannot produce negative waiting');
assert_same(null, aims_due_job_waiting_slot(19 * 60 + 59, 0), 'no alert before 20 minutes');
assert_same(['slot' => 1, 'minutes' => 20], aims_due_job_waiting_slot(20 * 60, 0), '20 minute alert');
assert_same(null, aims_due_job_waiting_slot(39 * 60 + 59, 1), 'no duplicate before 40 minutes');
assert_same(['slot' => 2, 'minutes' => 40], aims_due_job_waiting_slot(40 * 60, 1), '40 minute alert');
assert_same(['slot' => 3, 'minutes' => 60], aims_due_job_waiting_slot(60 * 60, 2), '60 minute alert');
assert_same(['slot' => 5, 'minutes' => 100], aims_due_job_waiting_slot(100 * 60, 2), 'offline gap emits current 20-minute slot without burst');
assert_same(null, aims_due_job_waiting_slot(100 * 60, 5), 'same slot is deduplicated');

echo "PASS: job waiting 20-minute cadence\n";
