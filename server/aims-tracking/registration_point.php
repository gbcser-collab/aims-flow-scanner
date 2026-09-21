<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
}

$data=json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);

$plate=aims_normalize_plate((string)($data['plate'] ?? ''));
$jobId=(int)($data['jobId'] ?? 0);
$stopId=(int)($data['stopId'] ?? 0);
$lat=isset($data['latitude']) ? (float)$data['latitude'] : 999.0;
$lng=isset($data['longitude']) ? (float)$data['longitude'] : 999.0;
$accuracy=isset($data['accuracy']) && is_numeric($data['accuracy']) ? (float)$data['accuracy'] : null;

if ($plate==='' || $jobId<1 || $stopId<1 || $lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
    aims_json(['ok'=>false,'error'=>'invalid_payload'],422);
}

$pdo=aims_db();
$v=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$v->execute([':plate'=>$plate]);
$vehicle=$v->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok'=>false,'error'=>'vehicle_not_found'],404);

$s=$pdo->prepare('SELECT s.*, j.vehicle_id, j.status
    FROM job_stops s
    JOIN jobs j ON j.id=s.job_id
    WHERE s.id=:stop AND s.job_id=:job AND j.vehicle_id=:vehicle
    LIMIT 1');
$s->execute([':stop'=>$stopId,':job'=>$jobId,':vehicle'=>$vehicle['id']]);
$stop=$s->fetch(PDO::FETCH_ASSOC);
if (!$stop) aims_json(['ok'=>false,'error'=>'stop_not_found'],404);
if (($stop['status'] ?? '') !== 'active') aims_json(['ok'=>false,'error'=>'job_not_active'],409);
if (empty($stop['arrival_notified_at'])) aims_json(['ok'=>false,'error'=>'arrival_required'],409);

$normalizeStatic=function(string $value): string {
    $value=mb_strtolower(trim($value),'UTF-8');
    $value=preg_replace('/\s+/u',' ',$value) ?: '';
    $ascii=@iconv('UTF-8','ASCII//TRANSLIT//IGNORE',$value);
    if (is_string($ascii) && $ascii!=='') $value=$ascii;
    $value=preg_replace('/[^a-z0-9]+/',' ',strtolower($value)) ?: '';
    return trim(preg_replace('/\s+/',' ',$value) ?: '');
};

$company=(string)($stop['company'] ?? '');
$address=(string)($stop['address'] ?? '');
$companyKey=$normalizeStatic($company);
$addressKey=$normalizeStatic($address);
$type=(string)($stop['stop_type'] ?? '');
if ($companyKey==='') $companyKey='unknown';
if ($addressKey==='') $addressKey='unknown';

$now=gmdate(DateTimeInterface::ATOM);
$pdo->beginTransaction();
try {
    $q=$pdo->prepare('SELECT * FROM registration_points
        WHERE company_key=:company_key AND address_key=:address_key AND stop_type=:stop_type LIMIT 1');
    $q->execute([':company_key'=>$companyKey,':address_key'=>$addressKey,':stop_type'=>$type]);
    $existing=$q->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
        $count=max(1,(int)$existing['confirmations']);
        $newCount=$count+1;
        $newLat=(((float)$existing['latitude'])*$count+$lat)/$newCount;
        $newLng=(((float)$existing['longitude'])*$count+$lng)/$newCount;
        $newAccuracy=$accuracy ?? ($existing['accuracy'] !== null ? (float)$existing['accuracy'] : null);
        $u=$pdo->prepare('UPDATE registration_points
            SET company_name=:company_name,address=:address,latitude=:lat,longitude=:lng,
                accuracy=:accuracy,confirmations=:confirmations,last_vehicle_id=:vehicle,updated_at=:updated
            WHERE id=:id');
        $u->execute([
            ':company_name'=>$company,':address'=>$address,':lat'=>$newLat,':lng'=>$newLng,
            ':accuracy'=>$newAccuracy,':confirmations'=>$newCount,':vehicle'=>$vehicle['id'],
            ':updated'=>$now,':id'=>$existing['id'],
        ]);
        $pointId=(int)$existing['id'];
        $confirmations=$newCount;
        $savedLat=$newLat;
        $savedLng=$newLng;
    } else {
        $i=$pdo->prepare('INSERT INTO registration_points
            (company_key,company_name,address_key,address,stop_type,latitude,longitude,accuracy,confirmations,last_vehicle_id,created_at,updated_at)
            VALUES (:company_key,:company_name,:address_key,:address,:stop_type,:lat,:lng,:accuracy,1,:vehicle,:created,:updated)');
        $i->execute([
            ':company_key'=>$companyKey,':company_name'=>$company,':address_key'=>$addressKey,
            ':address'=>$address,':stop_type'=>$type,':lat'=>$lat,':lng'=>$lng,
            ':accuracy'=>$accuracy,':vehicle'=>$vehicle['id'],':created'=>$now,':updated'=>$now,
        ]);
        $pointId=(int)$pdo->lastInsertId();
        $confirmations=1;
        $savedLat=$lat;
        $savedLng=$lng;
    }

    $u=$pdo->prepare('UPDATE job_stops
        SET registration_checked_at=:checked,registration_point_id=:point
        WHERE id=:stop');
    $u->execute([':checked'=>$now,':point'=>$pointId,':stop'=>$stopId]);

    aims_notify(
        $pdo,
        (int)$vehicle['admin_user_id'],
        (int)$vehicle['id'],
        'registration_point',
        'info',
        ($company !== '' ? $company : $plate).' regisztrációs pont mentve',
        ($type==='pickup'?'Felrakó':'Lerakó').' • '.$address,
        'registration_point:'.$pointId.':'.$confirmations,
        ['registrationPointId'=>$pointId,'jobId'=>$jobId,'stopId'=>$stopId,'confirmations'=>$confirmations]
    );

    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    aims_json(['ok'=>false,'error'=>'registration_point_save_failed'],500);
}

aims_json([
    'ok'=>true,
    'registrationPoint'=>[
        'id'=>$pointId,
        'latitude'=>$savedLat,
        'longitude'=>$savedLng,
        'confirmations'=>$confirmations,
        'checkedAt'=>$now,
    ],
]);