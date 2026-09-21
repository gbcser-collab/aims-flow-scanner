<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
}

$data=json_decode(file_get_contents('php://input') ?: '',true);
if(!is_array($data)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);

$plate=aims_normalize_plate((string)($data['plate'] ?? ''));
$stopId=(int)($data['stopId'] ?? 0);
$action=trim((string)($data['action'] ?? ''));
$source=trim((string)($data['source'] ?? 'manual'));
$occurredRaw=trim((string)($data['occurredAt'] ?? ''));
if($plate==='' || $stopId<=0 || !in_array($action,['arrived','completed'],true)){
    aims_json(['ok'=>false,'error'=>'invalid_payload'],422);
}
if(!in_array($source,['voice','manual','touch'],true)) $source='manual';

$pdo=aims_db();
$q=$pdo->prepare('SELECT s.*,j.reference,j.status AS job_status,v.id AS vehicle_id,v.label AS vehicle_label,v.plate,v.admin_user_id
    FROM job_stops s
    JOIN jobs j ON j.id=s.job_id
    JOIN vehicles v ON v.id=j.vehicle_id
    WHERE s.id=:stop AND v.plate=:plate AND v.enabled=1
    LIMIT 1');
$q->execute([':stop'=>$stopId,':plate'=>$plate]);
$stop=$q->fetch(PDO::FETCH_ASSOC);
if(!$stop) aims_json(['ok'=>false,'error'=>'stop_not_found'],404);
if(($stop['job_status'] ?? '')==='deleted'){
    aims_json(['ok'=>false,'error'=>'job_deleted'],410);
}
if(($stop['job_status'] ?? '')!=='active' && $action!=='completed'){
    aims_json(['ok'=>false,'error'=>'job_not_active'],409);
}

$serverNow=new DateTimeImmutable('now',new DateTimeZone('UTC'));
$eventAt=$serverNow;
if($occurredRaw!==''){
    try{
        $candidate=(new DateTimeImmutable($occurredRaw))->setTimezone(new DateTimeZone('UTC'));
        $tooFuture=$candidate>$serverNow->modify('+10 minutes');
        $tooOld=$candidate<$serverNow->modify('-14 days');
        if(!$tooFuture && !$tooOld) $eventAt=$candidate;
    }catch(Throwable){}
}
$eventStamp=$eventAt->format(DateTimeInterface::ATOM);
$updatedStamp=$serverNow->format(DateTimeInterface::ATOM);
$changed=false;
$kind=$stop['stop_type']==='pickup' ? 'felrakó' : 'lerakó';
$plateLabel=trim((string)($stop['vehicle_label'] ?? '')) ?: (string)$stop['plate'];
$place=trim((string)($stop['company'] ?? ''));
$address=trim((string)($stop['address'] ?? ''));
if($place!=='') $place.=' • '.$address; else $place=$address;

if($action==='arrived'){
    if($stop['arrival_notified_at']===null){
        $u=$pdo->prepare('UPDATE job_stops
            SET arrival_notified_at=:now,
                arrival_source=:source,
                inside_since=COALESCE(inside_since,:now),
                waiting_alert_slot=0,
                waiting_alert_last_at=NULL
            WHERE id=:id AND arrival_notified_at IS NULL');
        $u->execute([':now'=>$eventStamp,':source'=>$source,':id'=>$stopId]);
        $changed=$u->rowCount()===1;
    }
    if($changed){
        aims_notify(
            $pdo,
            (int)$stop['admin_user_id'],
            (int)$stop['vehicle_id'],
            'job_arrival',
            'success',
            $plateLabel.' megérkezett a '.$kind.'ra',
            $place.' • Fuvar: '.$stop['reference'].' • '.($source==='voice'?'hangparancs':($source==='touch'?'app gomb':'kézi jelzés')),
            'arrival:'.$stopId,
            [
                'jobReference'=>$stop['reference'],
                'stopId'=>$stopId,
                'stopType'=>$stop['stop_type'],
                'address'=>$address,
                'source'=>$source,
            ]
        );
    }
}else{
    if($stop['completed_at']===null){
        $u=$pdo->prepare('UPDATE job_stops
            SET arrival_notified_at=COALESCE(arrival_notified_at,:now),
                arrival_source=COALESCE(arrival_source,:source),
                completed_at=:now,
                completion_source=:source
            WHERE id=:id AND completed_at IS NULL');
        $u->execute([':now'=>$eventStamp,':source'=>$source,':id'=>$stopId]);
        $changed=$u->rowCount()===1;
    }
    if($changed){
        $title=$stop['stop_type']==='pickup'
            ? $plateLabel.' felrakás kész'
            : $plateLabel.' lerakás kész';
        aims_notify(
            $pdo,
            (int)$stop['admin_user_id'],
            (int)$stop['vehicle_id'],
            'job_stop_completed',
            'success',
            $title,
            $place.' • Fuvar: '.$stop['reference'].' • '.($source==='voice'?'hangparancs':($source==='touch'?'app gomb':'kézi jelzés')),
            'completion:'.$stopId,
            [
                'jobReference'=>$stop['reference'],
                'stopId'=>$stopId,
                'stopType'=>$stop['stop_type'],
                'address'=>$address,
                'source'=>$source,
            ]
        );

        $remaining=$pdo->prepare('SELECT COUNT(*) FROM job_stops WHERE job_id=:job AND completed_at IS NULL');
        $remaining->execute([':job'=>$stop['job_id']]);
        if((int)$remaining->fetchColumn()===0){
            // R92 document gate: completing the final stop does not close the
            // transport yet. Keep it visible to the driver until the required
            // CMR/document has been captured locally.
            $done=$pdo->prepare('UPDATE jobs SET status="document_pending",updated_at=:now WHERE id=:job AND status="active"');
            $done->execute([':now'=>$updatedStamp,':job'=>$stop['job_id']]);
        }else{
            $touch=$pdo->prepare('UPDATE jobs SET updated_at=:now WHERE id=:job');
            $touch->execute([':now'=>$updatedStamp,':job'=>$stop['job_id']]);
        }
    }
}

aims_try_push($pdo,8);
$fresh=$pdo->prepare('SELECT arrival_notified_at,completed_at FROM job_stops WHERE id=:id');
$fresh->execute([':id'=>$stopId]);
$row=$fresh->fetch(PDO::FETCH_ASSOC) ?: [];

aims_json([
    'ok'=>true,
    'changed'=>$changed,
    'stopId'=>$stopId,
    'action'=>$action,
    'occurredAt'=>$eventStamp,
    'arrived'=>!empty($row['arrival_notified_at']),
    'completed'=>!empty($row['completed_at']),
]);