<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
aims_require_token('AIMS_TRACKING_TOKEN');

function flow_ops_vehicle(PDO $pdo, string $plate): array {
    $normalized = aims_normalize_plate($plate);
    if ($normalized === '') aims_json(['ok'=>false,'error'=>'invalid_plate'],422);
    $stmt = $pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
    $stmt->execute([':plate'=>$normalized]);
    $vehicle = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$vehicle) aims_json(['ok'=>false,'error'=>'vehicle_not_registered'],404);
    return $vehicle;
}

function flow_ops_int(mixed $value, int $min, int $max, string $error): int {
    if (!is_numeric($value)) aims_json(['ok'=>false,'error'=>$error],422);
    $int=(int)$value;
    if ($int<$min || $int>$max) aims_json(['ok'=>false,'error'=>$error],422);
    return $int;
}

function flow_ops_iso(string $value, string $error): string {
    $value=trim($value);
    if ($value==='' || strtotime($value)===false) aims_json(['ok'=>false,'error'=>$error],422);
    return gmdate(DateTimeInterface::ATOM, (int)strtotime($value));
}

function flow_ops_data_dir(): string {
    $dir=trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: ''));
    if ($dir==='') $dir=__DIR__.'/data';
    if (!is_dir($dir) && !mkdir($dir,0700,true) && !is_dir($dir)) {
        aims_json(['ok'=>false,'error'=>'storage_unavailable'],503);
    }
    return $dir;
}

function flow_ops_current_km(PDO $pdo, int $vehicleId, ?int $payloadKm=null): ?int {
    if ($payloadKm !== null && $payloadKm >= 0) return $payloadKm;
    $stmt=$pdo->prepare('SELECT km FROM vehicle_odometer_log WHERE vehicle_id=:vehicle ORDER BY captured_at DESC,id DESC LIMIT 1');
    $stmt->execute([':vehicle'=>$vehicleId]);
    $value=$stmt->fetchColumn();
    return $value===false ? null : (int)$value;
}

function flow_ops_service_alerts(PDO $pdo, array $vehicle, ?int $currentKm): array {
    $vehicleId=(int)$vehicle['id'];
    $alerts=[];

    $state=$pdo->prepare('SELECT hold,hold_reason,hold_source,updated_at FROM vehicle_operational_state WHERE vehicle_id=:vehicle LIMIT 1');
    $state->execute([':vehicle'=>$vehicleId]);
    $op=$state->fetch(PDO::FETCH_ASSOC);
    if ($op && (int)$op['hold']===1) {
        $alerts[]=[
            'id'=>'hold',
            'title'=>'JÁRMŰ HOLD',
            'severity'=>'critical',
            'remainingKm'=>null,
            'dueDate'=>null,
            'detail'=>trim((string)$op['hold_reason'])!=='' ? (string)$op['hold_reason'] : 'Irodai feloldás szükséges',
        ];
    }

    $issues=$pdo->prepare('SELECT id,category,message,urgent,created_at FROM vehicle_issues WHERE vehicle_id=:vehicle AND status="open" ORDER BY urgent DESC,id DESC LIMIT 10');
    $issues->execute([':vehicle'=>$vehicleId]);
    foreach ($issues->fetchAll(PDO::FETCH_ASSOC) as $issue) {
        $alerts[]=[
            'id'=>'issue-'.(int)$issue['id'],
            'title'=>'Nyitott hiba: '.(string)$issue['category'],
            'severity'=>(int)$issue['urgent']===1 ? 'critical' : 'warning',
            'remainingKm'=>null,
            'dueDate'=>null,
            'detail'=>(string)$issue['message'],
        ];
    }

    $items=$pdo->prepare('SELECT * FROM vehicle_service_items WHERE vehicle_id=:vehicle AND enabled=1 ORDER BY id ASC');
    $items->execute([':vehicle'=>$vehicleId]);
    $today=new DateTimeImmutable('today',new DateTimeZone('UTC'));

    foreach ($items->fetchAll(PDO::FETCH_ASSOC) as $item) {
        $remainingKm=null;
        $kmSeverity=null;
        if ($item['due_km'] !== null && $currentKm !== null) {
            $remainingKm=(int)$item['due_km']-$currentKm;
            if ($remainingKm <= 0) $kmSeverity='overdue';
            elseif ($remainingKm <= max(0,(int)$item['warning_km'])) $kmSeverity='warning';
        }

        $dateSeverity=null;
        $dueDate=null;
        if (trim((string)($item['due_date']??''))!=='') {
            try {
                $due=new DateTimeImmutable((string)$item['due_date'],new DateTimeZone('UTC'));
                $dueDate=$due->format('Y-m-d');
                $days=(int)$today->diff($due)->format('%r%a');
                if ($days < 0) $dateSeverity='overdue';
                elseif ($days <= max(0,(int)$item['warning_days'])) $dateSeverity='warning';
            } catch(Throwable $e) {}
        }

        $severity='info';
        if ($kmSeverity==='overdue' || $dateSeverity==='overdue') $severity='overdue';
        elseif ($kmSeverity==='warning' || $dateSeverity==='warning') $severity='warning';
        else continue;

        $alerts[]=[
            'id'=>'service-'.(int)$item['id'],
            'title'=>(string)$item['title'],
            'severity'=>$severity,
            'remainingKm'=>$remainingKm,
            'dueDate'=>$dueDate,
            'detail'=>(string)$item['notes'],
        ];
    }
    return $alerts;
}

$method=$_SERVER['REQUEST_METHOD']??'GET';
if ($method!=='POST') {
    header('Allow: POST');
    aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);
}

$contentType=strtolower((string)($_SERVER['CONTENT_TYPE']??''));
$isMultipart=str_contains($contentType,'multipart/form-data');
$data=[];

if ($isMultipart) {
    $data=$_POST;
} else {
    $decoded=json_decode(file_get_contents('php://input')?:'',true);
    if (!is_array($decoded)) aims_json(['ok'=>false,'error'=>'invalid_json'],400);
    $data=$decoded;
}

$action=trim((string)($data['action']??''));
$plate=(string)($data['plate']??'');
if ($action==='' || trim($plate)==='') aims_json(['ok'=>false,'error'=>'invalid_payload'],422);

$pdo=aims_db();
$vehicle=flow_ops_vehicle($pdo,$plate);
$vehicleId=(int)$vehicle['id'];
$adminId=(int)$vehicle['admin_user_id'];
$now=gmdate(DateTimeInterface::ATOM);

if ($action==='workday_start') {
    $key=trim((string)($data['workdayId']??''));
    if ($key==='' || strlen($key)>180) aims_json(['ok'=>false,'error'=>'invalid_workday_id'],422);
    $started=flow_ops_iso((string)($data['startedAt']??''),'invalid_started_at');
    $startKm=flow_ops_int($data['startKm']??null,0,5000000,'invalid_start_km');
    $jobId=isset($data['jobId']) && is_numeric($data['jobId']) ? max(0,(int)$data['jobId']) : 0;

    $pdo->beginTransaction();
    try {
        $existing=$pdo->prepare('SELECT * FROM driver_workdays WHERE workday_key=:key LIMIT 1');
        $existing->execute([':key'=>$key]);
        $row=$existing->fetch(PDO::FETCH_ASSOC);
        if ($row && (int)$row['vehicle_id']!==$vehicleId) {
            $pdo->rollBack();
            aims_json(['ok'=>false,'error'=>'workday_id_conflict'],409);
        }
        if (!$row) {
            $insert=$pdo->prepare('INSERT INTO driver_workdays
                (workday_key,vehicle_id,start_job_id,started_at,start_km,created_at,updated_at)
                VALUES (:key,:vehicle,:job,:started,:km,:created,:updated)');
            $insert->execute([
                ':key'=>$key,':vehicle'=>$vehicleId,':job'=>$jobId>0?$jobId:null,
                ':started'=>$started,':km'=>$startKm,':created'=>$now,':updated'=>$now,
            ]);
        }
        $odo=$pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
            VALUES (:vehicle,:km,"workday_start",:captured,:created)');
        $odo->execute([':vehicle'=>$vehicleId,':km'=>$startKm,':captured'=>$started,':created'=>$now]);
        $pdo->commit();
    } catch(Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    aims_json(['ok'=>true,'workdayId'=>$key,'startedAt'=>$started]);
}

if ($action==='workday_finish') {
    $key=trim((string)($data['workdayId']??''));
    if ($key==='' || strlen($key)>180) aims_json(['ok'=>false,'error'=>'invalid_workday_id'],422);
    $finished=flow_ops_iso((string)($data['finishedAt']??''),'invalid_finished_at');
    $endKm=flow_ops_int($data['endKm']??null,0,5000000,'invalid_end_km');

    $stmt=$pdo->prepare('SELECT * FROM driver_workdays WHERE workday_key=:key AND vehicle_id=:vehicle LIMIT 1');
    $stmt->execute([':key'=>$key,':vehicle'=>$vehicleId]);
    $row=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) aims_json(['ok'=>false,'error'=>'workday_not_found'],404);
    if ($endKm < (int)$row['start_km']) aims_json(['ok'=>false,'error'=>'end_km_before_start'],409);

    $pdo->beginTransaction();
    try {
        $update=$pdo->prepare('UPDATE driver_workdays
            SET finished_at=:finished,end_km=:km,updated_at=:updated
            WHERE id=:id');
        $update->execute([':finished'=>$finished,':km'=>$endKm,':updated'=>$now,':id'=>(int)$row['id']]);
        $odo=$pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
            VALUES (:vehicle,:km,"workday_finish",:captured,:created)');
        $odo->execute([':vehicle'=>$vehicleId,':km'=>$endKm,':captured'=>$finished,':created'=>$now]);
        $pdo->commit();
    } catch(Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    aims_json(['ok'=>true,'workdayId'=>$key,'finishedAt'=>$finished,'distanceKm'=>$endKm-(int)$row['start_km']]);
}

if ($action==='odometer') {
    $km=flow_ops_int($data['km']??null,0,5000000,'invalid_km');
    $source=trim((string)($data['source']??'manual'));
    if ($source==='' || strlen($source)>80) $source='manual';
    $captured=trim((string)($data['capturedAt']??''));
    $captured=$captured!=='' ? flow_ops_iso($captured,'invalid_captured_at') : $now;
    $stmt=$pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
        VALUES (:vehicle,:km,:source,:captured,:created)');
    $stmt->execute([':vehicle'=>$vehicleId,':km'=>$km,':source'=>$source,':captured'=>$captured,':created'=>$now]);
    aims_json(['ok'=>true,'km'=>$km,'capturedAt'=>$captured]);
}

if ($action==='service_alerts') {
    $payloadKm=null;
    if (isset($data['currentKm']) && $data['currentKm']!=='' && is_numeric($data['currentKm'])) {
        $payloadKm=flow_ops_int($data['currentKm'],0,5000000,'invalid_current_km');
    }
    $currentKm=flow_ops_current_km($pdo,$vehicleId,$payloadKm);
    aims_json([
        'ok'=>true,
        'plate'=>(string)$vehicle['plate'],
        'currentKm'=>$currentKm,
        'alerts'=>flow_ops_service_alerts($pdo,$vehicle,$currentKm),
    ]);
}

if ($action==='safety_check') {
    if (!$isMultipart) aims_json(['ok'=>false,'error'=>'multipart_required'],415);
    $clientId=trim((string)($data['id']??''));
    if ($clientId==='' || preg_match('/^[A-Za-z0-9._:-]{1,180}$/',$clientId)!==1) {
        aims_json(['ok'=>false,'error'=>'invalid_check_id'],422);
    }
    $km=flow_ops_int($data['km']??null,0,5000000,'invalid_km');
    $created=flow_ops_iso((string)($data['createdAt']??''),'invalid_created_at');
    $statuses=json_decode((string)($data['statuses']??''),true);
    if (!is_array($statuses)) aims_json(['ok'=>false,'error'=>'invalid_statuses'],422);

    $required=['oil','coolant','tires','odometer'];
    foreach ($required as $kind) {
        $field='photo_'.$kind;
        if (!isset($_FILES[$field]) || !is_array($_FILES[$field]) || (int)($_FILES[$field]['error']??UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK) {
            aims_json(['ok'=>false,'error'=>'missing_photo_'.$kind],422);
        }
    }

    $hasProblem=false;
    foreach ($statuses as $value) {
        if (strtolower(trim((string)$value))!=='ok') {$hasProblem=true;break;}
    }

    $existing=$pdo->prepare('SELECT id FROM vehicle_safety_checks WHERE client_check_id=:id LIMIT 1');
    $existing->execute([':id'=>$clientId]);
    $checkId=(int)($existing->fetchColumn()?:0);

    if ($checkId===0) {
        $insert=$pdo->prepare('INSERT INTO vehicle_safety_checks
            (client_check_id,vehicle_id,km,statuses_json,has_problem,created_at,received_at)
            VALUES (:id,:vehicle,:km,:statuses,:problem,:created,:received)');
        $insert->execute([
            ':id'=>$clientId,':vehicle'=>$vehicleId,':km'=>$km,
            ':statuses'=>json_encode($statuses,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
            ':problem'=>$hasProblem?1:0,':created'=>$created,':received'=>$now,
        ]);
        $checkId=(int)$pdo->lastInsertId();
    }

    $base=flow_ops_data_dir().'/safety/'.$vehicleId;
    if (!is_dir($base) && !mkdir($base,0700,true) && !is_dir($base)) {
        aims_json(['ok'=>false,'error'=>'safety_storage_unavailable'],503);
    }
    $safeClient=preg_replace('/[^A-Za-z0-9._-]/','_',$clientId) ?: (string)$checkId;
    $finfo=new finfo(FILEINFO_MIME_TYPE);
    $stored=[];

    foreach ($required as $kind) {
        $field='photo_'.$kind;
        $file=$_FILES[$field];
        $size=(int)($file['size']??0);
        if ($size<1 || $size>8*1024*1024) aims_json(['ok'=>false,'error'=>'photo_size_'.$kind],422);
        $tmp=(string)($file['tmp_name']??'');
        $mime=(string)$finfo->file($tmp);
        $ext=match($mime){
            'image/jpeg'=>'jpg',
            'image/png'=>'png',
            'image/webp'=>'webp',
            default=>'',
        };
        if ($ext==='') aims_json(['ok'=>false,'error'=>'photo_type_'.$kind],422);
        $filename=$safeClient.'_'.$kind.'.'.$ext;
        $target=$base.'/'.$filename;
        if (!is_file($target)) {
            if (!move_uploaded_file($tmp,$target)) aims_json(['ok'=>false,'error'=>'photo_store_'.$kind],500);
            @chmod($target,0600);
        }
        $relative='safety/'.$vehicleId.'/'.$filename;
        $photo=$pdo->prepare('INSERT INTO vehicle_safety_photos
            (safety_check_id,photo_type,relative_path,mime_type,size_bytes,created_at)
            VALUES (:check,:type,:path,:mime,:size,:created)
            ON CONFLICT(safety_check_id,photo_type) DO UPDATE SET
              relative_path=excluded.relative_path,mime_type=excluded.mime_type,
              size_bytes=excluded.size_bytes,created_at=excluded.created_at');
        $photo->execute([
            ':check'=>$checkId,':type'=>$kind,':path'=>$relative,':mime'=>$mime,
            ':size'=>$size,':created'=>$now,
        ]);
        $stored[$kind]=true;
    }

    $odo=$pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
        VALUES (:vehicle,:km,"safety_check",:captured,:created)');
    $odo->execute([':vehicle'=>$vehicleId,':km'=>$km,':captured'=>$created,':created'=>$now]);

    if ($hasProblem) {
        $name=trim((string)$vehicle['label'])!==''?(string)$vehicle['label']:(string)$vehicle['plate'];
        aims_notify(
            $pdo,$adminId,$vehicleId,'safety_check_problem','warning',
            $name.' · Safety Check probléma',
            'A sofőr problémát jelölt a járműellenőrzésen.',
            'safety_check_problem:'.$checkId,
            ['safetyCheckId'=>$checkId,'plate'=>(string)$vehicle['plate'],'km'=>$km]
        );
        aims_try_push($pdo,8);
    }

    aims_json([
        'ok'=>true,
        'safetyCheckId'=>$checkId,
        'clientCheckId'=>$clientId,
        'hasProblem'=>$hasProblem,
        'storedPhotos'=>array_keys($stored),
        'receivedAt'=>$now,
    ]);
}

aims_json(['ok'=>false,'error'=>'unsupported_action'],422);
