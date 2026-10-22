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

if ($action==='workday_start' || $action==='workday_finish') {
    $closing=$action==='workday_finish';
    $key=trim((string)($data['workdayId']??''));
    if ($key==='' || strlen($key)>180) aims_json(['ok'=>false,'error'=>'invalid_workday_id'],422);
    $started=isset($data['startedAt']) ? flow_ops_iso((string)$data['startedAt'],'invalid_started_at') : null;
    $startKm=isset($data['startKm']) ? flow_ops_int($data['startKm'],0,5000000,'invalid_start_km') : null;
    $jobId=isset($data['jobId']) && is_numeric($data['jobId']) ? max(0,(int)$data['jobId']) : 0;
    $finished=$closing ? flow_ops_iso((string)($data['finishedAt']??''),'invalid_finished_at') : null;
    $endKm=$closing ? flow_ops_int($data['endKm']??null,0,5000000,'invalid_end_km') : null;
    if (!$closing && ($started===null || $startKm===null)) {
        aims_json(['ok'=>false,'error'=>'workday_start_snapshot_required'],422);
    }

    $pdo->beginTransaction();
    try {
        $reject=static function(string $error) use ($pdo): never {
            $pdo->rollBack();
            aims_json(['ok'=>false,'error'=>$error],409);
        };
        $stmt=$pdo->prepare('SELECT * FROM driver_workdays WHERE workday_key=:key LIMIT 1');
        $stmt->execute([':key'=>$key]);
        $row=$stmt->fetch(PDO::FETCH_ASSOC);
        if ($row && (int)$row['vehicle_id']!==$vehicleId) $reject('workday_id_conflict');
        if (!$row && ($started===null || $startKm===null)) $reject('workday_start_snapshot_required');
        if ($row) {
            if (($started!==null && strtotime($started)!==strtotime((string)$row['started_at'])) ||
                ($startKm!==null && $startKm!==(int)$row['start_km']) ||
                (isset($data['jobId']) && $jobId!==(int)($row['start_job_id']??0))) {
                $reject('workday_start_conflict');
            }
        }
        $effectiveStart=$row ? (string)$row['started_at'] : (string)$started;
        $effectiveKm=$row ? (int)$row['start_km'] : (int)$startKm;
        if ($closing) {
            if ($endKm<$effectiveKm) $reject('end_km_before_start');
            if (strtotime((string)$finished)<strtotime($effectiveStart)) $reject('finish_before_start');
            if ($row && $row['finished_at']!==null &&
                (strtotime((string)$row['finished_at'])!==strtotime((string)$finished) ||
                 (int)$row['end_km']!==$endKm)) $reject('workday_finish_conflict');
        }
        // Reconstruct a completely offline day in the same transaction as its
        // closure. Invalid closure data must not leave an orphaned open day.
        if (!$row) {
            $pdo->prepare('INSERT INTO driver_workdays
                (workday_key,vehicle_id,start_job_id,started_at,start_km,created_at,updated_at)
                VALUES (:key,:vehicle,:job,:started,:km,:created,:updated)')->execute([
                    ':key'=>$key,':vehicle'=>$vehicleId,':job'=>$jobId>0?$jobId:null,
                    ':started'=>$effectiveStart,':km'=>$effectiveKm,':created'=>$now,':updated'=>$now,
                ]);
            $stmt->execute([':key'=>$key]);
            $row=$stmt->fetch(PDO::FETCH_ASSOC);
            $pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
                VALUES (:vehicle,:km,"workday_start",:captured,:created)')->execute([
                    ':vehicle'=>$vehicleId,':km'=>$effectiveKm,':captured'=>$effectiveStart,':created'=>$now,
                ]);
        }
        // Exact replays are successful without adding another odometer event.
        // A delayed start never reopens a day that has already been closed.
        if ($closing && $row['finished_at']===null) {
            $pdo->prepare('UPDATE driver_workdays SET finished_at=:finished,end_km=:km,updated_at=:updated
                WHERE id=:id')->execute([
                    ':finished'=>$finished,':km'=>$endKm,':updated'=>$now,':id'=>(int)$row['id'],
                ]);
            $pdo->prepare('INSERT INTO vehicle_odometer_log (vehicle_id,km,source,captured_at,created_at)
                VALUES (:vehicle,:km,"workday_finish",:captured,:created)')->execute([
                    ':vehicle'=>$vehicleId,':km'=>$endKm,':captured'=>$finished,':created'=>$now,
                ]);
        }
        $pdo->commit();
    } catch(Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    aims_json($closing
        ? ['ok'=>true,'workdayId'=>$key,'finishedAt'=>$finished,'distanceKm'=>$endKm-$effectiveKm]
        : ['ok'=>true,'workdayId'=>$key,'startedAt'=>$effectiveStart]);
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
    require_once __DIR__.'/safety_check_store.php';
    try {
        $result=aims_store_safety_check($pdo,$vehicle,$data,$_FILES,
            (string)($_SERVER['AIMS_FLOW_DRIVER_FLOW_ID']??''),$now);
        aims_json($result);
    } catch (AimsSafetyCheckError $error) {
        aims_json(['ok'=>false,'error'=>$error->getMessage()],$error->httpStatus);
    }
}

aims_json(['ok'=>false,'error'=>'unsupported_action'],422);

