<?php
declare(strict_types=1);
$dir=sys_get_temp_dir().'/aims-mileage-'.bin2hex(random_bytes(6));mkdir($dir,0700,true);putenv('AIMS_TRACKING_DATA_DIR='.$dir);
require __DIR__.'/../bootstrap.php';require __DIR__.'/../driver_auth_v2.php';require __DIR__.'/../mileage_report_lib.php';require __DIR__.'/../monthly_report_lib.php';
error_reporting(E_ALL);set_error_handler(function($n,$s,$f,$l){if(error_reporting()&$n)throw new ErrorException($s,0,$n,$f,$l);return false;});
$pdo=aims_db();aims_driver_auth_schema($pdo);aims_mileage_schema($pdo);$admin=aims_ensure_default_admin($pdo);$checks=0;
function check(bool $ok,string $name):void{global $checks;if(!$ok)throw new RuntimeException($name);$checks++;}
function near(float $a,float $b,float $epsilon=0.001):bool{return abs($a-$b)<$epsilon;}
function vehicle(string $plate,string $flow):int{global $pdo,$admin;$now=gmdate('c');$pdo->prepare('INSERT INTO vehicles(plate,label,admin_user_id,created_at) VALUES(?,?,?,?)')->execute([$plate,$plate,$admin,$now]);$id=(int)$pdo->lastInsertId();$pdo->prepare('INSERT INTO driver_accounts(flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?)')->execute([$flow,'fixture','test@example.test','Sofőr '.$flow,$id,$now,$now]);return $id;}
function home(int $id,string $flow,string $date='2026-01-01',float $lon=19.04):int{global $pdo;return aims_mileage_save_home($pdo,['vehicle_id'=>$id,'flow_id'=>$flow,'address'=>'Teszt lakóhely','latitude'=>47,'longitude'=>$lon,'radius_m'=>50,'valid_from'=>$date]);}
function job(int $vehicle,int $start,string $ref='TEST'):int{global $pdo;$pdo->prepare('INSERT INTO jobs(reference,vehicle_id,status,created_at,updated_at) VALUES(?,?,"completed",?,?)')->execute([$ref,$vehicle,gmdate('c',$start-600),gmdate('c',$start)]);$id=(int)$pdo->lastInsertId();$pdo->prepare('INSERT INTO job_stops(job_id,stop_type,stop_order,address,latitude,longitude,radius_m,created_at,completed_at) VALUES(?,"delivery",1,"Utolsó lerakó",47,19.01,100,?,?)')->execute([$id,gmdate('c',$start-600),gmdate('c',$start)]);return $id;}
function point(int $id,string $flow,int $t,float $lng,float $lat=47,?float $accuracy=5,string $device='fixture',float $speed=8):void{global $pdo;$pdo->prepare('INSERT INTO points(device_id,vehicle_id,vehicle_label,captured_at,received_at,latitude,longitude,accuracy,speed_mps,flow_id) VALUES(?,?,?,?,?,?,?,?,?,?)')->execute([$device,$id,'',gmdate('c',$t),gmdate('c',$t),$lat,$lng,$accuracy,$speed,$flow]);}
function route(int $id,string $flow,int $start,bool $reverse=false):void{
 $points=[];for($i=0;$i<=40;$i++)$points[]=[$start+$i*60,19+$i*.001,47+($i>10&&$i<30?.001:0),8];
 $points[]=[$start+42*60,19.04,47,0];$points[]=[$start+44*60,19.04,47,0];$points[40][3]=0;
 if($reverse)$points=array_reverse($points);foreach($points as [$t,$lon,$lat,$speed])point($id,$flow,$t,$lon,$lat,5,'fixture',$speed);
}
$t=strtotime('2026-05-04T08:00:00Z');$a=vehicle('TEST44','440001');home($a,'440001');$job=job($a,$t+600);route($a,'440001',$t,true);
aims_mileage_save_finance($pdo,$job,['planned_km'=>'1,50','revenue_eur'=>'10,00','flow_id'=>'440001']);
$r=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44');
check(count($r['trips'])===1&&$r['trips'][0]['verified'],'confirmed delivery-to-home');
check($r['trips'][0]['arrival']===$t+2400,'two minute dwell confirms first arrival time');
$s=$r['summary'][0];check($s['actualKm']>$s['homeKm']&&$s['homeKm']>0,'home is a subset of actual distance');
check(near($s['netKm'],$s['actualKm']-$s['homeKm']),'deduction exactly once');
check(near($s['differenceKm'],$s['netKm']-1.5),'planned versus corrected distance');
check($s['revenueCents']===1000&&$s['costCents']===(int)round($s['actualKm']*30)&&$s['marginCents']===1000-$s['costCents'],'all-inclusive cost includes home distance');
check($r['trips'][0]['km']>aims_distance_m(47,19.01,47,19.04)/1000,'actual route, not home straight-line distance');
point($a,'440001',$t+1200,19.02,47.001);$again=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44');
check(near($again['summary'][0]['actualKm'],$s['actualKm']),'same timestamp is not double-counted');
check(count($again['trips'])===1,'rebuild and duplicate GPS do not duplicate home trips');
home($a,'440001','2026-05-05',20.5);$old=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44');check(near($old['summary'][0]['homeKm'],$s['homeKm']),'historical address retained after driver moves');
$b=vehicle('GAP44','440002');home($b,'440002');$jb=job($b,$t+600);route($b,'440002',$t);$pdo->prepare('DELETE FROM points WHERE vehicle_id=? AND julianday(captured_at)>julianday(?) AND julianday(captured_at)<julianday(?)')->execute([$b,gmdate('c',$t+600),gmdate('c',$t+1500)]);
aims_mileage_save_finance($pdo,$jb,['planned_km'=>'1','revenue_eur'=>'10','flow_id'=>'440002']);$gap=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','GAP44');
check(count($gap['trips'])===1&&!$gap['trips'][0]['verified'],'GPS gap marks home journey unverified');check($gap['summary'][0]['homeKm']===0.0&&$gap['summary'][0]['marginCents']===null,'no invented deduction or final margin across gaps');
$c=vehicle('DRIVE44','440003');home($c,'440003');job($c,$t+600);route($c,'440003',$t);$pdo->prepare('UPDATE points SET speed_mps=15 WHERE vehicle_id=?')->execute([$c]);$drive=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','DRIVE44');check(count($drive['trips'])===0,'drive-by is not arrival');
$d=vehicle('OTHER44','440004');home($d,'440004');job($d,$t+600);route($d,'440001',$t);$other=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','OTHER44');check(count($other['trips'])===0,'another driver does not inherit home geofence');
$e=vehicle('NEWJOB44','440005');home($e,'440005');$je=job($e,$t+600);route($e,'440005',$t);$pdo->prepare('INSERT INTO job_stops(job_id,stop_type,stop_order,address,created_at,completed_at) VALUES(?,"pickup",2,"Új felrakó",?,?)')->execute([$je,gmdate('c',$t),gmdate('c',$t+1200)]);$newjob=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','NEWJOB44');check(!$newjob['trips'],'new pickup prevents home deduction');
$f=vehicle('MONTH44','440006');home($f,'440006');$cross=strtotime('2026-05-31T21:40:00Z');$jf=job($f,$cross+600);route($f,'440006',$cross);aims_mileage_save_finance($pdo,$jf,['planned_km'=>'1','revenue_eur'=>'1','flow_id'=>'440006']);
$may=aims_mileage_build_report($pdo,'2026-05-31','2026-05-31','MONTH44');$june=aims_mileage_build_report($pdo,'2026-06-01','2026-06-01','MONTH44');$both=aims_mileage_build_report($pdo,'2026-05-31','2026-06-01','MONTH44');
check(near($may['summary'][0]['homeKm']+$june['summary'][0]['homeKm'],$both['summary'][0]['homeKm']),'month boundary apportions home distance without duplication');
check(near($may['summary'][0]['actualKm']+$june['summary'][0]['actualKm'],$both['summary'][0]['actualKm']),'daily kilometres reconcile across midnight');
check($may['summary'][0]['revenueCents']===100&&$june['summary'][0]['revenueCents']===0,'revenue booked once on completion date');
$spring=aims_report_period('2026-03-29','2026-03-29');$autumn=aims_report_period('2026-10-25','2026-10-25');check($spring['endUtc']->getTimestamp()-$spring['startUtc']->getTimestamp()===23*3600,'DST spring day');check($autumn['endUtc']->getTimestamp()-$autumn['startUtc']->getTimestamp()===25*3600,'DST autumn day');
$bad=false;try{aims_report_period('2026-02-30','2026-03-01');}catch(InvalidArgumentException){$bad=true;}check($bad,'invalid date rejected');
$bad=false;try{aims_mileage_decimal('-5',100);}catch(InvalidArgumentException){$bad=true;}check($bad,'negative finance input rejected');
aims_mileage_save_finance($pdo,$job,['planned_km'=>'0','revenue_eur'=>'0','flow_id'=>'440001']);$zero=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44');check($zero['summary'][0]['missingRevenue']===0&&$zero['summary'][0]['marginCents']<0,'explicit zero revenue remains valid and negative margin visible');
aims_mileage_save_finance($pdo,$job,['planned_km'=>'','revenue_eur'=>'','flow_id'=>'440001']);$missing=aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44');check($missing['summary'][0]['missingRevenue']===1&&$missing['summary'][0]['marginCents']===null,'missing revenue never becomes zero');
$pdo->prepare('UPDATE driver_accounts SET driver_name=? WHERE flow_id=?')->execute(['=HYPERLINK("bad")','440001']);$csv=aims_mileage_csv(aims_mileage_build_report($pdo,'2026-05-04','2026-05-04','TEST44'));check(str_contains($csv,"'=HYPERLINK"),'CSV formula neutralized');
$range=aims_monthly_build_range_report($pdo,'2026-05-04','2026-05-06');check($range['period']['endLocal']->format('Y-m-d')==='2026-05-07','inclusive arbitrary date range');
check((int)$pdo->query('SELECT COUNT(*) FROM flow_mileage_audit')->fetchColumn()>=10,'configuration and finance changes audited');
echo "MILEAGE REGRESSIONS: $checks checks passed\n";
