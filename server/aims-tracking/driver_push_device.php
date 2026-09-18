<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
$data=json_decode(file_get_contents('php://input') ?: '',true);
if (!is_array($data)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);
$plate=aims_normalize_plate((string)($data['plate'] ?? ''));
$deviceId=trim((string)($data['deviceId'] ?? ''));
$fcm=trim((string)($data['fcmToken'] ?? ''));
$platform=trim((string)($data['platform'] ?? 'android'));
if ($plate==='' || $deviceId==='' || $fcm==='') aims_json(['ok'=>false,'error'=>'invalid_payload'],422);
$pdo=aims_db();
$v=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$v->execute([':plate'=>$plate]);
$vehicle=$v->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok'=>false,'error'=>'vehicle_not_registered'],404);
$now=gmdate(DateTimeInterface::ATOM);
$q=$pdo->prepare('INSERT INTO driver_push_devices (vehicle_id,platform,device_id,fcm_token,enabled,created_at,updated_at)
VALUES (:vehicle,:platform,:device,:fcm,1,:created,:updated)
ON CONFLICT(fcm_token) DO UPDATE SET vehicle_id=excluded.vehicle_id,platform=excluded.platform,device_id=excluded.device_id,enabled=1,updated_at=excluded.updated_at');
$q->execute([':vehicle'=>$vehicle['id'],':platform'=>$platform,':device'=>$deviceId,':fcm'=>$fcm,':created'=>$now,':updated'=>$now]);
aims_json(['ok'=>true,'registered'=>true]);
