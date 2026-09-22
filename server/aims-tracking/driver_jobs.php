<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    header('Allow: GET');
    aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
}
$plate=aims_normalize_plate((string)($_GET['plate'] ?? ''));
if ($plate==='') aims_json(['ok'=>false,'error'=>'invalid_plate'],422);
$pdo=aims_db();
$v=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
$v->execute([':plate'=>$plate]);
$vehicle=$v->fetch(PDO::FETCH_ASSOC);
if (!$vehicle) aims_json(['ok'=>true,'jobs'=>[]]);
$j=$pdo->prepare('SELECT * FROM jobs WHERE vehicle_id=:vehicle AND status IN ("active","document_pending") ORDER BY id DESC');
$j->execute([':vehicle'=>$vehicle['id']]);
$normalizeRegistrationKey=function(string $value): string {
    $value=mb_strtolower(trim($value),'UTF-8');
    $value=preg_replace('/\s+/u',' ',$value) ?: '';
    $ascii=@iconv('UTF-8','ASCII//TRANSLIT//IGNORE',$value);
    if (is_string($ascii) && $ascii!=='') $value=$ascii;
    $value=preg_replace('/[^a-z0-9]+/',' ',strtolower($value)) ?: '';
    return trim(preg_replace('/\s+/',' ',$value) ?: '');
};
$jobs=[];
foreach ($j->fetchAll(PDO::FETCH_ASSOC) as $job) {
    $st=$pdo->prepare('SELECT * FROM job_stops WHERE job_id=:job ORDER BY stop_order ASC');
    $st->execute([':job'=>$job['id']]);
    $stops=[];
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $company=(string)($row['company'] ?? '');
        $address=(string)($row['address'] ?? '');
        $companyKey=$normalizeRegistrationKey($company);
        $addressKey=$normalizeRegistrationKey($address);
        $knownPoint=null;
        if ($companyKey!=='' && $addressKey!=='') {
            $rp=$pdo->prepare('SELECT id,latitude,longitude,confirmations,updated_at FROM registration_points
                WHERE company_key=:company_key AND address_key=:address_key AND stop_type=:stop_type LIMIT 1');
            $rp->execute([':company_key'=>$companyKey,':address_key'=>$addressKey,':stop_type'=>$row['stop_type']]);
            $knownPoint=$rp->fetch(PDO::FETCH_ASSOC) ?: null;
        }
        $stops[]=[
            'id'=>(int)$row['id'],'type'=>$row['stop_type'],'order'=>(int)$row['stop_order'],
            'company'=>$company,'address'=>$address,
            'phone'=>$row['contact_phone'] ?? '',
            'latitude'=>$row['latitude'] === null ? null : (float)$row['latitude'],
            'longitude'=>$row['longitude'] === null ? null : (float)$row['longitude'],
            'arrived'=>$row['arrival_notified_at'] !== null,
            'completed'=>$row['completed_at'] !== null,
            'arrivedAt'=>$row['arrival_notified_at'] ?? null,
            'completedAt'=>$row['completed_at'] ?? null,
            'registrationCheckedAt'=>$row['registration_checked_at'] ?? null,
            'registrationPoint'=>$knownPoint ? [
                'id'=>(int)$knownPoint['id'],
                'latitude'=>(float)$knownPoint['latitude'],
                'longitude'=>(float)$knownPoint['longitude'],
                'confirmations'=>(int)$knownPoint['confirmations'],
                'updatedAt'=>$knownPoint['updated_at'] ?? null,
            ] : null,
        ];
    }
    $orderData=[];
    if (!empty($job['order_payload_json'])) {
        $decoded=json_decode((string)$job['order_payload_json'],true);
        if (is_array($decoded)) $orderData=$decoded;
    }
    $jobs[]=[
        'id'=>(int)$job['id'],'reference'=>$job['reference'],'status'=>$job['status'],
        'partial'=>(int)($job['partial_load'] ?? 0)===1,
        'sourceOrderId'=>$job['source_order_id'] ?? null,
        'orderData'=>$orderData,
        'seenAt'=>$job['driver_seen_at'] ?? null,'acceptedAt'=>$job['driver_accepted_at'] ?? null,
        'stops'=>$stops,
    ];
}
aims_json(['ok'=>true,'plate'=>$plate,'jobs'=>$jobs]);
