<?php
declare(strict_types=1);

/**
 * Session guard for the existing driver endpoints.
 *
 * The public phone sends its revocable driver-session token. After validating
 * the session, assigned plate and device identity, this guard replaces the
 * request bearer with the server-only tracking token and executes the existing
 * endpoint. The server token never reaches the Android application.
 */

function aims_flow_session_json(array $payload,int $status=200):never{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    exit;
}

function aims_flow_session_load_config():void{
    $shared=dirname(__DIR__,4).'/aims-flow-config.php';
    if(!is_file($shared))return;
    $cfg=require $shared;
    if(!is_array($cfg))return;
    foreach($cfg as $key=>$value){
        if(!is_string($key)||!is_scalar($value))continue;
        $current=getenv($key);
        if($current===false||$current==='')putenv($key.'='.(string)$value);
    }
}

function aims_flow_session_db():PDO{
    static $pdo=null;
    if($pdo instanceof PDO)return $pdo;
    aims_flow_session_load_config();
    $dir=trim((string)(getenv('AIMS_TRACKING_DATA_DIR')?:''));
    if($dir==='')$dir=dirname(__DIR__).'/data';
    $pdo=new PDO('sqlite:'.$dir.'/tracking.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA foreign_keys=ON');
    $pdo->exec('PRAGMA busy_timeout=5000');
    return $pdo;
}

function aims_flow_session_bearer():string{
    $header=trim((string)($_SERVER['HTTP_AUTHORIZATION']??''));
    if(!preg_match('/^Bearer\s+(.+)$/i',$header,$match))return '';
    return trim($match[1]);
}

function aims_flow_session_normalize_plate(string $value):string{
    $value=mb_strtoupper(trim($value),'UTF-8');
    return preg_replace('/[^A-Z0-9]/u','',$value)?:'';
}

function aims_flow_session_request_data():array{
    static $data=null;
    if(is_array($data))return $data;

    $data=[];
    foreach($_GET as $key=>$value){
        if(is_string($key)&&is_scalar($value))$data[$key]=(string)$value;
    }
    foreach($_POST as $key=>$value){
        if(is_string($key)&&is_scalar($value))$data[$key]=(string)$value;
    }

    $contentType=strtolower((string)($_SERVER['CONTENT_TYPE']??''));
    if(!str_contains($contentType,'multipart/form-data')){
        $raw=file_get_contents('php://input')?:'';
        if($raw!==''){
            $json=json_decode($raw,true);
            if(is_array($json)){
                foreach($json as $key=>$value){
                    if(is_string($key)&&(is_scalar($value)||$value===null)){
                        $data[$key]=$value;
                    }
                }
            }
        }
    }
    return $data;
}

function aims_flow_session_plate_from_request():string{
    $data=aims_flow_session_request_data();
    $plate=aims_flow_session_normalize_plate((string)($data['plate']??''));
    if($plate!=='')return $plate;
    return aims_flow_session_normalize_plate((string)($data['vehicleLabel']??''));
}

function aims_flow_session_proxy(string $target):never{
    if(!is_file($target))aims_flow_session_json(['ok'=>false,'error'=>'proxy_target_missing'],500);

    $token=aims_flow_session_bearer();
    if(!preg_match('/^[a-f0-9]{64}$/',$token)){
        aims_flow_session_json(['ok'=>false,'error'=>'invalid_session'],401);
    }

    $pdo=aims_flow_session_db();
    $now=gmdate(DateTimeInterface::ATOM);
    $query=$pdo->prepare('SELECT s.token_hash,s.account_id,s.device_id,s.expires_at,
        a.flow_id,a.vehicle_id,a.enabled,a.onboarding_complete,v.plate
      FROM driver_sessions s
      JOIN driver_accounts a ON a.id=s.account_id
      LEFT JOIN vehicles v ON v.id=a.vehicle_id
      WHERE s.token_hash=:hash AND s.revoked_at IS NULL AND s.expires_at>:now
        AND a.enabled=1 LIMIT 1');
    $query->execute([':hash'=>hash('sha256',$token),':now'=>$now]);
    $session=$query->fetch(PDO::FETCH_ASSOC);
    if(!$session)aims_flow_session_json(['ok'=>false,'error'=>'invalid_session'],401);

    $assigned=aims_flow_session_normalize_plate((string)($session['plate']??''));
    if($assigned===''||((int)($session['onboarding_complete']??0))!==1){
        aims_flow_session_json(['ok'=>false,'error'=>'onboarding_required'],409);
    }

    $request=aims_flow_session_request_data();
    $requestPlate=aims_flow_session_normalize_plate((string)($request['plate']??''));
    $requestLabel=aims_flow_session_normalize_plate((string)($request['vehicleLabel']??''));
    if($requestPlate!==''&&$requestLabel!==''&&!hash_equals($requestPlate,$requestLabel)){
        aims_flow_session_json(['ok'=>false,'error'=>'vehicle_identity_conflict'],403);
    }
    $requested=$requestPlate!==''?$requestPlate:$requestLabel;
    if($requested!==''&&!hash_equals($assigned,$requested)){
        aims_flow_session_json(['ok'=>false,'error'=>'plate_forbidden'],403);
    }

    if (basename($target)==='driver_ops_v2.php'
        && in_array((string)($request['action']??''),['workday_start','workday_finish'],true)
        && preg_match('/^(\d{6})(?:-|$)/',(string)($request['workdayId']??''),$workdayOwner)
        && !hash_equals((string)$session['flow_id'],$workdayOwner[1])) {
        aims_flow_session_json(['ok'=>false,'error'=>'workday_owner_forbidden'],403);
    }

    if (basename($target)==='driver_ops_v2.php' && ($request['action']??'')==='safety_check') {
        $owner=trim((string)($request['flowId']??''));
        if (($owner!=='' && !hash_equals((string)$session['flow_id'],$owner)) ||
            (preg_match('/^(\d{6})-/',(string)($request['id']??''),$safetyOwner) &&
             !hash_equals((string)$session['flow_id'],$safetyOwner[1]))) {
            aims_flow_session_json(['ok'=>false,'error'=>'safety_owner_forbidden'],403);
        }
    }

    if (basename($target)==='ingest.php') {
        $owner=trim((string)($request['flowId']??''));
        if ($owner!=='' && !hash_equals((string)$session['flow_id'],$owner)) {
            aims_flow_session_json(['ok'=>false,'error'=>'point_owner_forbidden'],403);
        }
    }

    $assignedDevice=trim((string)($session['device_id']??''));
    $requestDevice=trim((string)($request['deviceId']??''));
    if($requestDevice!==''&&$assignedDevice!==''&&!hash_equals($assignedDevice,$requestDevice)){
        aims_flow_session_json(['ok'=>false,'error'=>'device_forbidden'],403);
    }

    $serverToken=trim((string)(getenv('AIMS_TRACKING_TOKEN')?:''));
    if($serverToken==='')aims_flow_session_json(['ok'=>false,'error'=>'server_not_configured'],503);

    $pdo->prepare('UPDATE driver_sessions SET last_seen_at=:now WHERE token_hash=:hash')
      ->execute([':now'=>$now,':hash'=>(string)$session['token_hash']]);

    $_SERVER['HTTP_AUTHORIZATION']='Bearer '.$serverToken;
    $_SERVER['AIMS_FLOW_DRIVER_ACCOUNT_ID']=(string)$session['account_id'];
    $_SERVER['AIMS_FLOW_DRIVER_FLOW_ID']=(string)$session['flow_id'];
    $_SERVER['AIMS_FLOW_DRIVER_PLATE']=$assigned;
    $_SERVER['AIMS_FLOW_DRIVER_DEVICE_ID']=$assignedDevice;

    require $target;
    exit;
}

