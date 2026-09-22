<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
$data=json_decode(file_get_contents('php://input') ?: '',true);
if (!is_array($data)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);
$plate=aims_normalize_plate((string)($data['plate'] ?? ''));
$type=trim((string)($data['type'] ?? ''));
$message=trim((string)($data['message'] ?? ''));
$urgent=($data['urgent'] ?? false)===true;
$eventId=trim((string)($data['eventId'] ?? ''));
$occurredAt=trim((string)($data['occurredAt'] ?? ''));
if ($plate==='' || $type==='') aims_json(['ok'=>false,'error'=>'invalid_payload'],422);
if ($eventId!=='' && preg_match('/^[A-Za-z0-9._:-]{1,180}$/',$eventId)!==1) {
    aims_json(['ok'=>false,'error'=>'invalid_event_id'],422);
}
$pdo=aims_db();
$v=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$v->execute([':plate'=>$plate]);
$vehicle=$v->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok'=>false,'error'=>'vehicle_not_registered'],404);
$name=trim((string)$vehicle['label'])!=='' ? $vehicle['label'] : $vehicle['plate'];
$body=$message!=='' ? $message : $type;
$payload=[
    'signalType'=>$type,
    'message'=>$message,
    'latitude'=>$data['latitude'] ?? null,
    'longitude'=>$data['longitude'] ?? null,
    'eventId'=>$eventId!=='' ? $eventId : null,
    'occurredAt'=>$occurredAt!=='' ? $occurredAt : null,
];
$dedupeSuffix=$eventId!=='' ? hash('sha256',$eventId) : hash('sha256',microtime(true).'|'.$body);
$dedupeKey='driver_signal:'.$vehicle['id'].':'.$dedupeSuffix;
aims_notify($pdo,(int)$vehicle['admin_user_id'],(int)$vehicle['id'],'driver_signal',$urgent?'critical':'warning',"$name · $type",$body,$dedupeKey,$payload);
aims_try_push($pdo,8);
aims_json(['ok'=>true,'sent'=>true,'eventId'=>$eventId!=='' ? $eventId : null]);
