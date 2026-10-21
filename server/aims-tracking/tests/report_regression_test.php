<?php
declare(strict_types=1);
require __DIR__.'/monthly_report_test.php';

// All mutations below use the isolated test database created by that test.
$pdo->exec('DELETE FROM driver_workdays');
$pdo->exec('UPDATE report_capture_metadata SET started_at="2026-01-01T00:00:00+00:00"');
function report_day(PDO $pdo,int $vehicle,string $key,string $start,?string $finish):void {
    $pdo->prepare('INSERT INTO driver_workdays
        (workday_key,vehicle_id,started_at,finished_at,start_km,end_km,created_at,updated_at)
        VALUES (:key,:vehicle,:start,:end,100000,100100,:start,:start)')->execute([
            ':key'=>$key,':vehicle'=>$vehicle,':start'=>$start,':end'=>$finish,
        ]);
}
$utc = new DateTimeZone('UTC');
$at = static fn(string $s):DateTimeImmutable => new DateTimeImmutable($s,$utc);
report_day($pdo,$vehicleId,'123456-day1','2026-09-10T06:00:00Z','2026-09-10T14:00:00Z');
// Duplicated/overlapping work must not duplicate seconds.
report_day($pdo,$vehicleId,'123456-overlap','2026-09-10T07:00:00Z','2026-09-10T12:00:00Z');
aims_rest_history_begin($pdo,$vehicleId,'123456',$at('2026-09-10T09:00:00Z'),$at('2026-09-10T10:00:00Z'));
aims_rest_history_finish($pdo,$vehicleId,$at('2026-09-10T09:45:00Z'));
$report=aims_monthly_build_report($pdo,'2026-09');
$day=$report['attendanceRows'][0];
test_assert($day['grossSeconds']===28800,'Overlapping workdays double-counted.');
test_assert($day['restSeconds']===2700,'45-minute rest was not deducted once.');
test_assert($day['duration']['hhmm']==='07:15','Net FLOW time must be 07:15.');
test_assert(!$day['incompleteRest'],'Rest coverage should be complete in this fixture.');
test_assert(abs($report['attendanceSummary'][0]['differenceHours']-(7.25-176))<0.001,'Difference must use net time.');
test_assert(str_contains(aims_monthly_attendance_csv($report),'Rögzített pihenő'),'Daily CSV lacks rest column.');

// A second vehicle on the same date must still be a single working day.
$pdo->prepare('INSERT INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES ("TST002","TST002",:admin,1,:at)')
    ->execute([':admin'=>$adminId,':at'=>$now]);
$second=(int)$pdo->lastInsertId();
report_day($pdo,$second,'123456-second-vehicle','2026-09-10T13:00:00Z','2026-09-10T16:00:00Z');
$summary=aims_monthly_build_report($pdo,'2026-09')['attendanceSummary'][0];
test_assert($summary['days']===1,'Vehicle change counted twice as a working day.');
test_assert($summary['grossSeconds']===36000 && $summary['seconds']===33300,'Cross-vehicle overlap counted twice.');

// Midnight in Budapest is 22:00 UTC here; split both work and rest accurately.
report_day($pdo,$vehicleId,'123456-overnight','2026-09-11T21:00:00Z','2026-09-11T23:00:00Z');
aims_rest_history_begin($pdo,$vehicleId,'123456',$at('2026-09-11T21:30:00Z'),$at('2026-09-11T22:30:00Z'));
aims_rest_history_finish($pdo,$vehicleId,$at('2026-09-12T06:00:00Z'));
$rows=aims_monthly_build_report($pdo,'2026-09')['attendanceRows'];
$byDate=[];foreach($rows as $row)$byDate[$row['date']]=$row;
test_assert($byDate['2026-09-11']['restSeconds']===1800 && $byDate['2026-09-12']['restSeconds']===1800,'Midnight rest split incorrect.');
test_assert($byDate['2026-09-12']['seconds']===1800,'Expired rest extended beyond planned end.');

// Another driver's rest cannot reduce this driver's time.
report_day($pdo,$vehicleId,'123456-owner','2026-09-14T06:00:00Z','2026-09-14T14:00:00Z');
aims_rest_history_begin($pdo,$vehicleId,'654321',$at('2026-09-14T08:00:00Z'),$at('2026-09-14T09:00:00Z'));
aims_rest_history_finish($pdo,$vehicleId,$at('2026-09-14T09:00:00Z'));
$rows=aims_monthly_build_report($pdo,'2026-09')['attendanceRows'];
foreach($rows as $row)if($row['date']==='2026-09-14')test_assert($row['restSeconds']===0,'Rest reassigned to a different driver.');

// Repeated starts extend one record. A driver change closes the old owner.
$start=$at('2026-09-15T08:00:00Z');
aims_rest_history_begin($pdo,$vehicleId,'123456',$start,$start->modify('+1 hour'));
aims_rest_history_begin($pdo,$vehicleId,'123456',$start->modify('+5 minutes'),$start->modify('+2 hours'));
test_assert((int)$pdo->query('SELECT COUNT(*) FROM driver_rest_periods WHERE ended_at IS NULL')->fetchColumn()===1,'Retry duplicated active rest.');
aims_rest_history_begin($pdo,$vehicleId,'654321',$start->modify('+10 minutes'),$start->modify('+1 hour'));
test_assert((int)$pdo->query('SELECT COUNT(*) FROM driver_rest_periods WHERE ended_at IS NULL')->fetchColumn()===1,'Driver switch left two open rests.');
aims_rest_history_finish($pdo,$vehicleId,$start->modify('+20 minutes'));

// A 25-hour DST day has 25 actual hours, not a hard-coded 24.
report_day($pdo,$vehicleId,'123456-dst','2026-10-24T22:00:00Z','2026-10-25T23:00:00Z');
// Use a past DST date to keep this test independent of today's date.
$pdo->exec('UPDATE driver_workdays SET started_at="2025-10-25T22:00:00Z",finished_at="2025-10-26T23:00:00Z" WHERE workday_key="123456-dst"');
$dst=aims_monthly_build_report($pdo,'2025-10')['attendanceRows'][0];
test_assert($dst['grossSeconds']===25*3600,'DST day lost an hour.');
test_assert($dst['incompleteRest'],'Pre-migration history incorrectly marked complete.');

// A week spanning August/September must include August's hours.
report_day($pdo,$vehicleId,'123456-week-start','2026-08-31T04:00:00Z','2026-08-31T16:00:00Z');
report_day($pdo,$vehicleId,'123456-week-end','2026-09-01T04:00:00Z','2026-09-01T16:00:00Z');
$summary=aims_monthly_build_report($pdo,'2026-09')['attendanceSummary'][0];
test_assert($summary['maxWeeklyHours']>=24,'Month boundary truncated an ISO week.');

report_day($pdo,$vehicleId,'123456-open','2026-09-30T20:00:00Z',null);
$summary=aims_monthly_build_report($pdo,'2026-09')['attendanceSummary'][0];
test_assert($summary['openWorkday'] && str_contains($summary['status'],'IDEIGLENES'),'Open workday must be provisional.');
test_assert($summary['average4MonthWeeklyHours']===null,'Incomplete reference average must not look verified.');
echo "REPORT REST, NET TIME, OWNERSHIP, OVERLAP, DST AND MONTH EDGE REGRESSIONS OK\n";
