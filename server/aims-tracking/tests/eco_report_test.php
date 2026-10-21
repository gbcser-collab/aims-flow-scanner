<?php
declare(strict_types=1);

$testDir=sys_get_temp_dir().'/aims-flow-eco-'.bin2hex(random_bytes(6));
if(!mkdir($testDir,0700,true)&&!is_dir($testDir))throw new RuntimeException('Test directory cannot be created.');
putenv('AIMS_TRACKING_DATA_DIR='.$testDir);
putenv('AIMS_DEFAULT_ADMIN_NAME=ECO Test');

require dirname(__DIR__).'/bootstrap.php';
require dirname(__DIR__).'/driver_auth_v2.php';
require dirname(__DIR__).'/eco_report_lib.php';

function eco_assert(bool $condition,string $message):void{
    if(!$condition)throw new RuntimeException($message);
}

$pdo=aims_db();
aims_driver_auth_schema($pdo);
$adminId=aims_ensure_default_admin($pdo);
$now=gmdate(DateTimeInterface::ATOM);

function eco_create_vehicle_and_driver(PDO $pdo,int $adminId,string $plate,string $flowId,string $name):int{
    $now=gmdate(DateTimeInterface::ATOM);
    $vehicle=$pdo->prepare('INSERT INTO vehicles (plate,label,admin_user_id,enabled,created_at) VALUES (:plate,:label,:admin,1,:created)');
    $vehicle->execute([':plate'=>$plate,':label'=>$plate,':admin'=>$adminId,':created'=>$now]);
    $vehicleId=(int)$pdo->lastInsertId();
    $account=$pdo->prepare('INSERT INTO driver_accounts
      (flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at)
      VALUES (:flow,:pin,:email,:name,:vehicle,1,1,:created,:updated)');
    $account->execute([
      ':flow'=>$flowId,':pin'=>password_hash('12345',PASSWORD_DEFAULT),
      ':email'=>strtolower(str_replace(' ','',$name)).'@example.test',
      ':name'=>$name,':vehicle'=>$vehicleId,':created'=>$now,':updated'=>$now,
    ]);
    return $vehicleId;
}

function eco_create_workday(PDO $pdo,int $vehicleId,string $flowId,string $started,string $finished):void{
    $now=gmdate(DateTimeInterface::ATOM);
    $stmt=$pdo->prepare('INSERT INTO driver_workdays
      (workday_key,vehicle_id,start_job_id,started_at,finished_at,start_km,end_km,created_at,updated_at)
      VALUES (:key,:vehicle,NULL,:started,:finished,100000,100200,:created,:updated)');
    $stmt->execute([
      ':key'=>$flowId.'-eco-test',':vehicle'=>$vehicleId,':started'=>$started,
      ':finished'=>$finished,':created'=>$now,':updated'=>$now,
    ]);
}

function eco_insert_points(PDO $pdo,int $vehicleId,string $deviceId,DateTimeImmutable $start,array $speeds):void{
    $stmt=$pdo->prepare('INSERT INTO points
      (point_key,device_id,vehicle_id,vehicle_label,captured_at,received_at,latitude,longitude,accuracy,speed_mps,heading,altitude,source)
      VALUES (:key,:device,:vehicle,:label,:captured,:received,:lat,:lng,8,:speed,90,100,"stream")');
    foreach($speeds as $index=>$speed){
      $captured=$start->modify('+'.($index*8).' seconds')->format(DateTimeInterface::ATOM);
      $stmt->execute([
        ':key'=>$deviceId.'-'.$index,':device'=>$deviceId,':vehicle'=>$vehicleId,
        ':label'=>'TEST',':captured'=>$captured,':received'=>$captured,
        ':lat'=>47.50,':lng'=>16.00+$index*0.0001,':speed'=>$speed,
      ]);
    }
}

$vehicleA=eco_create_vehicle_and_driver($pdo,$adminId,'ECOA001','123456','Egyenletes Sofőr');
$vehicleD=eco_create_vehicle_and_driver($pdo,$adminId,'ECOD001','654321','Szélsőséges Sofőr');
$start=new DateTimeImmutable('2026-10-01T06:00:00+00:00');
$finish=$start->modify('+2 hours')->format(DateTimeInterface::ATOM);
eco_create_workday($pdo,$vehicleA,'123456',$start->format(DateTimeInterface::ATOM),$finish);
eco_create_workday($pdo,$vehicleD,'654321',$start->format(DateTimeInterface::ATOM),$finish);

$speedsA=array_fill(0,900,20.0);
foreach([250,650] as $index){
    $speedsA[$index-1]=10.0;
    $speedsA[$index]=22.0;
    $speedsA[$index+1]=22.0;
    $speedsA[$index+2]=10.0;
    $speedsA[$index+3]=20.0;
}
eco_insert_points($pdo,$vehicleA,'eco-a',$start,$speedsA);

$speedsD=array_fill(0,900,18.0);
for($index=20;$index<880;$index+=32){
    $speedsD[$index-1]=8.0;
    $speedsD[$index]=30.0;
    $speedsD[$index+1]=30.0;
    $speedsD[$index+2]=5.0;
    $speedsD[$index+3]=18.0;
}
eco_insert_points($pdo,$vehicleD,'eco-d',$start,$speedsD);

$report=aims_eco_build_report($pdo,'2026-10-01','2026-10-01');
eco_assert(count($report['rows'])===2,'Expected two ECO driver/plate rows.');
$byFlow=[];foreach($report['rows'] as $row)$byFlow[$row['flowId']]=$row;
eco_assert(isset($byFlow['123456'],$byFlow['654321']),'Both drivers must be present.');
eco_assert($byFlow['123456']['enoughData']===true,'A driver must have enough data.');
eco_assert($byFlow['654321']['enoughData']===true,'D driver must have enough data.');
eco_assert($byFlow['123456']['grade']==='A','Smooth driver should receive A, got '.$byFlow['123456']['grade']);
eco_assert($byFlow['654321']['grade']==='D','Aggressive driver should receive D, got '.$byFlow['654321']['grade']);
eco_assert($byFlow['654321']['severeAccel']>10,'Severe acceleration events were not detected.');
eco_assert($byFlow['654321']['severeBrake']>10,'Severe braking events were not detected.');
eco_assert(count($report['events'])>20,'Detailed ECO events were not produced.');

$filtered=aims_eco_build_report($pdo,'2026-10-01','2026-10-01','ECOA001','123456');
eco_assert(count($filtered['rows'])===1,'Driver/plate filter should return one row.');
eco_assert($filtered['rows'][0]['flowId']==='123456','Filtered report returned the wrong driver.');

$csv=aims_eco_csv($report);
eco_assert(str_contains($csv,'Egyenletes Sofőr'),'CSV is missing the smooth driver.');
eco_assert(str_contains($csv,'Szélsőséges Sofőr'),'CSV is missing the aggressive driver.');
eco_assert(str_contains($csv,';A;'),'CSV is missing grade A.');
eco_assert(str_contains($csv,';D;'),'CSV is missing grade D.');

echo "ECO REPORT A-D SCORING OK\n";
