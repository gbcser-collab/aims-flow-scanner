<?php
declare(strict_types=1);
require __DIR__.'/eco_report_test.php';

foreach ([['2026-02-30','2026-03-01'],['2026-01-02','2026-01-01']] as [$from,$to]) {
    $rejected=false;
    try { aims_eco_period($from,$to); } catch (InvalidArgumentException) { $rejected=true; }
    eco_assert($rejected,'Invalid or reversed date range was accepted.');
}
aims_eco_period('2026-09-01','2026-12-02'); // 93 calendar days across DST.
$template=$report['rows'][0];
$template=array_merge($template,[
    'flowId'=>'123456','distanceM'=>100000.0,'movingSeconds'=>3600,'validSegments'=>450,
    'smoothSegments'=>450,'hardBrake'=>0,'severeAccel'=>0,'severeBrake'=>0,
]);
foreach ([0=>'A',5=>'A',10=>'B',20=>'C',40=>'D'] as $events=>$grade) {
    $result=aims_eco_grade(array_merge($template,['hardAccel'=>$events]),aims_eco_thresholds());
    eco_assert($result['grade']===$grade,'Grade disagrees with documented score bands.');
}
foreach (['distanceM'=>49999.0,'movingSeconds'=>2699,'validSegments'=>79,'flowId'=>''] as $key=>$value) {
    $result=aims_eco_grade(array_merge($template,[$key=>$value]),aims_eco_thresholds());
    eco_assert(!$result['enoughData'] && $result['grade']==='—','Insufficient/unidentified sample received a grade.');
}

$bad=eco_create_vehicle_and_driver($pdo,$adminId,'ECOBAD','777777','GPS Teszt');
eco_create_workday($pdo,$bad,'777777',$start->format(DateTimeInterface::ATOM),$finish);
eco_insert_points($pdo,$bad,'eco-bad',$start,[20.0,80.0,40.0,40.0]);
$badReport=aims_eco_build_report($pdo,'2026-10-01','2026-10-01','ECOBAD');
eco_assert(count($badReport['events'])===0,'Rejected speed became a false braking baseline.');
eco_assert($badReport['rows'][0]['validSegments']===1,'Rejected GPS segment added time/distance.');

// A legacy workday must never be assigned to today's vehicle assignee.
$pdo->exec('UPDATE driver_workdays SET workday_key="legacy-unknown" WHERE vehicle_id='.$vehicleA);
$unknown=aims_eco_build_report($pdo,'2026-10-01','2026-10-01','ECOA001');
eco_assert($unknown['rows'][0]['flowId']==='' && !$unknown['rows'][0]['enoughData'],'Historical unknown work reassigned to current driver.');
$pdo->exec('UPDATE driver_workdays SET workday_key="123456-eco-test" WHERE vehicle_id='.$vehicleA);
// Filtering a driver must not hide a conflicting simultaneous driver's shift.
$pdo->prepare('INSERT INTO driver_workdays(workday_key,vehicle_id,started_at,finished_at,start_km,created_at,updated_at)
    VALUES ("654321-conflict",:vehicle,:start,:end,100000,:start,:start)')->execute([
        ':vehicle'=>$vehicleA,':start'=>$start->format(DateTimeInterface::ATOM),':end'=>$finish,
    ]);
$conflict=aims_eco_build_report($pdo,'2026-10-01','2026-10-01','ECOA001','123456');
eco_assert(count($conflict['rows'])===0,'Conflicting driver intervals produced an individual grade.');
echo "ECO INVALID GPS, DATE, SCORE AND DRIVER OWNERSHIP REGRESSIONS OK\n";
