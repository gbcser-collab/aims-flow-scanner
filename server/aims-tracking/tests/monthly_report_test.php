<?php
declare(strict_types=1);

$testDir = sys_get_temp_dir().'/aims-flow-monthly-'.bin2hex(random_bytes(6));
if (!mkdir($testDir, 0700, true) && !is_dir($testDir)) {
    throw new RuntimeException('Test directory cannot be created.');
}
putenv('AIMS_TRACKING_DATA_DIR='.$testDir);
putenv('AIMS_DEFAULT_ADMIN_NAME=Monthly Test');

require dirname(__DIR__).'/bootstrap.php';
require dirname(__DIR__).'/driver_auth_v2.php';
require dirname(__DIR__).'/country_stay.php';
require dirname(__DIR__).'/monthly_report_lib.php';

function test_assert(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

$pdo = aims_db();
aims_driver_auth_schema($pdo);
$adminId = aims_ensure_default_admin($pdo);
$now = gmdate(DateTimeInterface::ATOM);

$vehicleInsert = $pdo->prepare('INSERT INTO vehicles
    (plate,label,admin_user_id,enabled,created_at)
    VALUES ("TST001","TST-001",:admin,1,:created)');
$vehicleInsert->execute([':admin'=>$adminId, ':created'=>$now]);
$vehicleId = (int)$pdo->lastInsertId();
$vehicle = $pdo->query('SELECT * FROM vehicles WHERE id='.$vehicleId)->fetch(PDO::FETCH_ASSOC);
test_assert(is_array($vehicle), 'Vehicle not created.');

$account = $pdo->prepare('INSERT INTO driver_accounts
    (flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at)
    VALUES ("123456",:pin,"driver@example.test","Teszt Sofőr",:vehicle,1,1,:created,:updated)');
$account->execute([
    ':pin'=>password_hash('12345', PASSWORD_DEFAULT),
    ':vehicle'=>$vehicleId,
    ':created'=>$now,
    ':updated'=>$now,
]);

// Initial confirmed country.
aims_process_country_stay(
    $pdo,
    $vehicle,
    'HU',
    47.5000,
    16.0000,
    new DateTimeImmutable('2026-09-10T06:00:00Z'),
    false
);

// Candidate AT fixes: roughly one kilometre per step at this latitude.
$longitudes = [16.0000, 16.0135, 16.0270, 16.0405, 16.0540];
foreach ($longitudes as $index=>$longitude) {
    aims_process_country_stay(
        $pdo,
        $vehicle,
        'AT',
        47.5000,
        $longitude,
        new DateTimeImmutable(sprintf('2026-09-10T06:%02d:00Z', 1 + $index)),
        false
    );
}
$confirmedBefore = $pdo->query('SELECT confirmed_country_code FROM vehicle_country_state WHERE vehicle_id='.$vehicleId)->fetchColumn();
test_assert($confirmedBefore === 'HU', 'Border crossing was confirmed before 5 km.');

// The next plausible segment moves the cumulative candidate distance over 5 km.
aims_process_country_stay(
    $pdo,
    $vehicle,
    'AT',
    47.5000,
    16.0675,
    new DateTimeImmutable('2026-09-10T06:06:00Z'),
    false
);
$state = $pdo->query('SELECT * FROM vehicle_country_state WHERE vehicle_id='.$vehicleId)->fetch(PDO::FETCH_ASSOC);
test_assert(($state['confirmed_country_code'] ?? '') === 'AT', 'Border crossing was not confirmed after 5 km.');
test_assert((float)($state['candidate_distance_m'] ?? -1) === 0.0, 'Candidate distance was not reset.');

$stays = $pdo->query('SELECT country_code,entered_at,exited_at FROM country_stays WHERE vehicle_id='.$vehicleId.' ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
test_assert(count($stays) === 2, 'Expected two country stays after confirmed crossing.');
test_assert($stays[0]['country_code'] === 'HU' && $stays[1]['country_code'] === 'AT', 'Country stay sequence is wrong.');

$workday = $pdo->prepare('INSERT INTO driver_workdays
    (workday_key,vehicle_id,start_job_id,started_at,finished_at,start_km,end_km,created_at,updated_at)
    VALUES (:key,:vehicle,NULL,:started,:finished,100000,100450,:created,:updated)');
$workday->execute([
    ':key'=>'123456-1789010400000000-1',
    ':vehicle'=>$vehicleId,
    ':started'=>'2026-09-10T06:00:00+00:00',
    ':finished'=>'2026-09-10T14:00:00+00:00',
    ':created'=>$now,
    ':updated'=>$now,
]);

$report = aims_monthly_build_report($pdo, '2026-09');
test_assert(count($report['countryRows']) >= 2, 'Country rows were not generated.');
test_assert(count($report['attendanceRows']) === 1, 'Attendance day was not generated.');
test_assert(count($report['attendanceSummary']) === 1, 'Attendance summary was not generated.');
test_assert(abs((float)$report['attendanceSummary'][0]['normHours'] - 176.0) < 0.01, '2026-09 monthly norm should be 176 hours.');
test_assert($report['attendanceRows'][0]['duration']['hhmm'] === '08:00', 'Daily attendance duration should be 08:00.');

$countryCsv = aims_monthly_country_csv($report);
$attendanceCsv = aims_monthly_attendance_csv($report);
$summaryCsv = aims_monthly_attendance_summary_csv($report);
test_assert(str_contains($countryCsv, 'Ausztria'), 'Country CSV is missing Austria.');
test_assert(str_contains($attendanceCsv, 'Teszt Sofőr'), 'Attendance CSV is missing the driver.');
test_assert(str_contains($summaryCsv, '176,00'), 'Summary CSV is missing the monthly norm.');

$paths = aims_monthly_store_report($report);
test_assert(isset($paths['AIMS-FLOW-orszagido-2026-09.csv']), 'Combined country report file is missing.');
test_assert(isset($paths['AIMS-FLOW-orszagido-TST001-2026-09.csv']), 'Per-plate country report file is missing.');
foreach ($paths as $path) test_assert(is_file($path) && filesize($path) > 10, 'Generated report file is empty.');

echo "MONTHLY REPORT AND 5 KM BORDER GUARD OK\n";
