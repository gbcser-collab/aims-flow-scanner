<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
$data=json_decode(file_get_contents('php://input') ?: '',true);
if (!is_array($data)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);
$plate=aims_normalize_plate((string)($data['plate'] ?? ''));
$jobId=(int)($data['jobId'] ?? 0);
$action=trim((string)($data['action'] ?? ''));
if ($plate==='' || $jobId<1 || !in_array($action,['seen','accepted'],true)) aims_json(['ok'=>false,'error'=>'invalid_payload'],422);
$pdo=aims_db();
$q=$pdo->prepare('SELECT j.*,v.admin_user_id,v.id AS vehicle_id,v.label,v.plate FROM jobs j JOIN vehicles v ON v.id=j.vehicle_id WHERE j.id=:job AND v.plate=:plate AND v.enabled=1 LIMIT 1');
$q->execute([':job'=>$jobId,':plate'=>$plate]);
$row=$q->fetch(PDO::FETCH_ASSOC);
if (!$row) aims_json(['ok'=>false,'error'=>'job_not_found'],404);
$now=gmdate(DateTimeInterface::ATOM);
if ($action==='seen') {
    $u=$pdo->prepare('UPDATE jobs SET driver_seen_at=COALESCE(driver_seen_at,:now),updated_at=:now2 WHERE id=:id');
    $u->execute([':now'=>$now,':now2'=>$now,':id'=>$jobId]);
} else {
    $u=$pdo->prepare('UPDATE jobs SET driver_seen_at=COALESCE(driver_seen_at,:now),driver_accepted_at=COALESCE(driver_accepted_at,:now2),updated_at=:now3 WHERE id=:id');
    $u->execute([':now'=>$now,':now2'=>$now,':now3'=>$now,':id'=>$jobId]);
}
$name=trim((string)$row['label'])!=='' ? $row['label'] : $row['plate'];
$title=$action==='accepted' ? "$name elfogadta a fuvart" : "$name sofőrje látta a fuvart";
aims_notify($pdo,(int)$row['admin_user_id'],(int)$row['vehicle_id'],'driver_job_'.$action,'success',$title,(string)$row['reference'],"driver_ack:$jobId:$action",['jobId'=>$jobId,'reference'=>$row['reference']]);
aims_try_push($pdo,8);
aims_json(['ok'=>true,'action'=>$action,'acknowledgedAt'=>$now]);
