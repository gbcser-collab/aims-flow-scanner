<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
require __DIR__ . '/smart_rules.php';
aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
}
$plate=aims_normalize_plate((string)($_GET['plate'] ?? ''));
if ($plate==='') aims_json(['ok'=>false,'error'=>'invalid_plate'],422);
$pdo=aims_db();
$q=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$q->execute([':plate'=>$plate]);
$vehicle=$q->fetch(PDO::FETCH_ASSOC);
$now=new DateTimeImmutable('now',new DateTimeZone('UTC'));
$minutesAgo=function(?string $value)use($now):?int{
    if(!$value)return null;
    try{$dt=(new DateTimeImmutable($value))->setTimezone(new DateTimeZone('UTC'));return max(0,(int)floor(($now->getTimestamp()-$dt->getTimestamp())/60));}
    catch(Throwable){return null;}
};
if(!$vehicle) aims_json(['ok'=>true,'plate'=>$plate,'autopilot'=>[
    'mode'=>'idle','actionCode'=>'wait_job','severity'=>'info','reference'=>'','seen'=>false,'accepted'=>false,
    'totalStops'=>0,'completedStops'=>0,'gpsFresh'=>false,'documentsRequired'=>false,'sequenceAnomaly'=>false,
]]);
$j=$pdo->prepare('SELECT * FROM jobs WHERE vehicle_id=:v AND status="active" ORDER BY id DESC LIMIT 1');
$j->execute([':v'=>$vehicle['id']]);$job=$j->fetch(PDO::FETCH_ASSOC);
$p=$pdo->prepare('SELECT * FROM points WHERE vehicle_id=:v ORDER BY captured_at DESC,id DESC LIMIT 1');
$p->execute([':v'=>$vehicle['id']]);$point=$p->fetch(PDO::FETCH_ASSOC)?:null;
$vs=$pdo->prepare('SELECT * FROM vehicle_state WHERE vehicle_id=:v LIMIT 1');
$vs->execute([':v'=>$vehicle['id']]);$state=$vs->fetch(PDO::FETCH_ASSOC)?:null;
$gpsAge=$minutesAgo($point['captured_at']??null);
$stationaryMin=$minutesAgo($state['stationary_since']??null);
$base=[
 'mode'=>'idle','actionCode'=>'wait_job','severity'=>'info','jobId'=>null,'reference'=>'','seen'=>false,'accepted'=>false,
 'totalStops'=>0,'completedStops'=>0,'nextStop'=>null,'gpsAgeMinutes'=>$gpsAge,'stationaryMinutes'=>$stationaryMin,
 'stopDwellMinutes'=>null,'distanceKm'=>null,'etaMinutes'=>null,'plannedAt'=>null,'timeBufferMinutes'=>null,
 'sequenceAnomaly'=>false,'documentsRequired'=>false,'gpsFresh'=>$gpsAge!==null&&$gpsAge<20,
 'updatedAt'=>$now->format(DateTimeInterface::ATOM),
];
if(!$job) aims_json(['ok'=>true,'plate'=>$plate,'autopilot'=>$base]);
$st=$pdo->prepare('SELECT * FROM job_stops WHERE job_id=:j ORDER BY stop_order ASC,id ASC');
$st->execute([':j'=>$job['id']]);$stops=$st->fetchAll(PDO::FETCH_ASSOC)?:[];
$completed=0;$next=null;$seenIncomplete=false;$sequenceAnomaly=false;
foreach($stops as $row){
    $done=!empty($row['completed_at']);
    if($done)$completed++;
    if(!$done&&$next===null){$next=$row;$seenIncomplete=true;continue;}
    if($seenIncomplete&&(!empty($row['inside_since'])||!empty($row['arrival_notified_at'])||!empty($row['completed_at'])))$sequenceAnomaly=true;
}
$allDone=count($stops)>0&&$completed===count($stops);
$seen=!empty($job['driver_seen_at']);$accepted=!empty($job['driver_accepted_at']);
$action='navigate_next';$mode='enroute';$severity='ok';
if(!$seen){$action='open_job';$mode='new_job';$severity='warn';}
elseif(!$accepted){$action='accept_job';$mode='awaiting_acceptance';$severity='warn';}
elseif($allDone){$action='scan_documents';$mode='documents';$severity='warn';}
elseif($next&&!empty($next['inside_since'])){$action=$next['stop_type']==='delivery'?'finish_delivery':'finish_pickup';$mode='at_stop';}
elseif($next){$action='navigate_next';$mode='enroute';}
else{$action='refresh_job';$mode='attention';$severity='warn';}
$dwell=$next?$minutesAgo($next['inside_since']??null):null;
if($dwell!==null&&$dwell>=60)$severity='high';
elseif($dwell!==null&&$dwell>=30&&$severity==='ok')$severity='warn';
if($accepted&&($gpsAge===null||$gpsAge>=20))$severity='high';
if($sequenceAnomaly)$severity='high';
$distanceKm=null;$etaMin=null;
if($next&&$point&&is_numeric($point['latitude']??null)&&is_numeric($point['longitude']??null)){
    $distanceKm=aims_distance_m((float)$point['latitude'],(float)$point['longitude'],(float)$next['latitude'],(float)$next['longitude'])/1000*1.18;
    $speedKmh=(float)($point['speed_mps']??0)*3.6;
    $cruise=($speedKmh>=35&&$speedKmh<=110)?max(55,min(90,$speedKmh*.4+68*.6)):68;
    $etaMin=(int)ceil($distanceKm/$cruise*60);
}
$order=[];
if(!empty($job['order_payload_json'])){$x=json_decode((string)$job['order_payload_json'],true);if(is_array($x))$order=$x;}
$planned=null;
if($next){$planned=(string)($next['stop_type']==='delivery'?($order['delivery_time']??''):($order['pickup_time']??''));}
$buffer=null;
if($planned&&$etaMin!==null){try{$pt=new DateTimeImmutable($planned);$buffer=(int)floor(($pt->getTimestamp()-$now->getTimestamp())/60)-$etaMin;if($buffer<0)$severity='high';elseif($buffer<15&&$severity==='ok')$severity='warn';}catch(Throwable){}}
$out=$base;
$out['mode']=$mode;$out['actionCode']=$action;$out['severity']=$severity;$out['jobId']=(int)$job['id'];$out['reference']=(string)$job['reference'];
$out['seen']=$seen;$out['accepted']=$accepted;$out['totalStops']=count($stops);$out['completedStops']=$completed;
$out['nextStop']=$next?['id'=>(int)$next['id'],'type'=>(string)$next['stop_type'],'order'=>(int)$next['stop_order'],'company'=>(string)($next['company']??''),'address'=>(string)$next['address'],'arrived'=>!empty($next['inside_since'])||!empty($next['arrival_notified_at'])]:null;
$out['stopDwellMinutes']=$dwell;$out['distanceKm']=$distanceKm;$out['etaMinutes']=$etaMin;$out['plannedAt']=$planned?:null;$out['timeBufferMinutes']=$buffer;
$out['sequenceAnomaly']=$sequenceAnomaly;$out['documentsRequired']=$allDone;
aims_json(['ok'=>true,'plate'=>$plate,'autopilot'=>$out]);
