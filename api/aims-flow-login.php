[Reading 184 lines from start (total: 184 lines, 0 remaining)]

<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/aims-tracking/bootstrap.php';

aims_security_headers(true);
header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');


function flow_normalize_driver_code(string $value): string {
  return strtoupper(preg_replace('/[^A-Za-z0-9]/','',trim($value)) ?? '');
}

function flow_driver_code_format_valid(string $value): bool {
  return preg_match('/^(?=(?:.*[A-Z]){3})(?=(?:.*[0-9]){3})[A-Z0-9]{6}$/',$value)===1
    && preg_match_all('/[A-Z]/',$value)===3
    && preg_match_all('/[0-9]/',$value)===3;
}

function flow_vehicle_driver_code_valid(array $vehicle,string $code,string &$reason): bool {
  $reason='invalid';
  $hash=trim((string)($vehicle['driver_code_hash']??''));
  if($hash==='') return false;

  if(!password_verify($code,$hash)) return false;

  $isTemp=((int)($vehicle['driver_code_is_temp']??0))===1;
  if($isTemp){
    $expires=trim((string)($vehicle['driver_code_expires_at']??''));
    if($expires!==''){
      $ts=strtotime($expires);
      if($ts!==false && $ts<time()){
        $reason='temp_expired';
        return false;
      }
    }
    $reason='temp';
    return true;
  }

  $reason='ok';
  return true;
}

function flow_reply(array $data,int $status=200): never {
  http_response_code($status);
  echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
  exit;
}

if(($_SERVER['REQUEST_METHOD']??'')!=='POST'){
  flow_reply(['ok'=>false,'error'=>'method_not_allowed'],405);
}

$data=json_decode(file_get_contents('php://input')?:'',true);
if(!is_array($data)) flow_reply(['ok'=>false,'error'=>'invalid_json'],400);

$login=trim((string)($data['login']??''));
$password=(string)($data['password']??'');
$code=trim((string)($data['code']??''));
$pushDeviceId=trim((string)($data['pushDeviceId']??''));
$fcmToken=trim((string)($data['fcmToken']??''));
$pushPlatform=strtolower(trim((string)($data['pushPlatform']??'android')));
if($login===''||$password==='') flow_reply(['ok'=>false,'error'=>'missing_credentials'],422);

$key=aims_client_ip().'|'.portal_lower($login);
$rate=aims_rate_limit('flow-native-login',$key,6,900,false);
if(!$rate['allowed']) flow_reply(['ok'=>false,'error'=>'rate_limited'],429);

// Admin login remains separate and keeps TOTP.
$admin=false;
try{
  $state=aims_admin_state();
  $passOk=password_verify($password,(string)($state['password_hash']??''));
  $mfaOk=!empty($state['totp_secret'])
    && preg_match('/^[0-9]{6}$/',$code)
    && aims_totp_verify($state['totp_secret'],$code);
  $admin=$passOk&&$mfaOk;
}catch(Throwable $e){}

if($admin){
  aims_rate_limit_clear('flow-native-login',$key);

  $adminPushRegistered=false;
  $adminPushError='missing_push_identity';
  if($fcmToken!==''||$pushDeviceId!==''){
    if(strlen($fcmToken)<40||strlen($fcmToken)>4096){
      $adminPushError='invalid_fcm_token';
    }elseif($pushDeviceId===''||strlen($pushDeviceId)>200){
      $adminPushError='invalid_device_id';
    }elseif(!in_array($pushPlatform,['android','ios'],true)){
      $adminPushError='invalid_platform';
    }else{
      try{
        $pdo=aims_db();
        $adminId=aims_ensure_default_admin($pdo);
        $now=gmdate(DateTimeInterface::ATOM);

        // A refreshed FCM token replaces the old token for the same admin phone.
        $disable=$pdo->prepare('UPDATE push_devices
          SET enabled=0,updated_at=:now
          WHERE admin_user_id=:admin AND device_id=:device AND fcm_token<>:token');
        $disable->execute([
          ':now'=>$now,
          ':admin'=>$adminId,
          ':device'=>$pushDeviceId,
          ':token'=>$fcmToken,
        ]);

        $push=$pdo->prepare('INSERT INTO push_devices
          (admin_user_id,platform,device_id,fcm_token,app_version,enabled,created_at,updated_at)
          VALUES (:admin,:platform,:device,:token,NULL,1,:created,:updated)
          ON CONFLICT(fcm_token) DO UPDATE SET
            admin_user_id=excluded.admin_user_id,
            platform=excluded.platform,
            device_id=excluded.device_id,
            enabled=1,
            updated_at=excluded.updated_at');
        $push->execute([
          ':admin'=>$adminId,
          ':platform'=>$pushPlatform,
          ':device'=>$pushDeviceId,
          ':token'=>$fcmToken,
          ':created'=>$now,
          ':updated'=>$now,
        ]);
        $adminPushRegistered=true;
        $adminPushError=null;
      }catch(Throwable $e){
        $adminPushError='push_storage_error';
        error_log('AIMS Flow admin push registration: '.$e->getMessage());
      }
    }
  }

  $adminSessionToken='';
  $adminSessionExpiresAt='';
  try{
    $pdo=aims_db();
    $adminId=aims_ensure_default_admin($pdo);
    $pdo->exec('CREATE TABLE IF NOT EXISTS admin_mobile_sessions (
      token_hash TEXT PRIMARY KEY,
      admin_user_id INTEGER NOT NULL,
      device_id TEXT NOT NULL DEFAULT "",
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      revoked_at TEXT,
      FOREIGN KEY(admin_user_id) REFERENCES admin_users(id) ON DELETE CASCADE
    )');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_admin_mobile_sessions_expiry ON admin_mobile_sessions(admin_user_id,expires_at)');
    $now=gmdate(DateTimeInterface::ATOM);
    $adminSessionExpiresAt=gmdate(DateTimeInterface::ATOM,time()+30*86400);
    $adminSessionToken=bin2hex(random_bytes(32));
    $sessionHash=hash('sha256',$adminSessionToken);
    $pdo->prepare('DELETE FROM admin_mobile_sessions WHERE expires_at<=:now OR revoked_at IS NOT NULL')->execute([':now'=>$now]);
    $session=$pdo->prepare('INSERT INTO admin_mobile_sessions (token_hash,admin_user_id,device_id,created_at,expires_at,revoked_at) VALUES (:hash,:admin,:device,:created,:expires,NULL)');
    $session->execute([':hash'=>$sessionHash,':admin'=>$adminId,':device'=>$pushDeviceId,':created'=>$now,':expires'=>$adminSessionExpiresAt]);
  }catch(Throwable $e){
    error_log('AIMS Flow admin mobile session: '.$e->getMessage());
  }

  aims_audit('flow_native_login',[
    'actor'=>'admin',
    'result'=>'ok',
    'detail'=>$adminPushRegistered?'push_registered':'push_not_registered',
  ]);
  flow_reply([
    'ok'=>true,
    'role'=>'admin',
    'displayName'=>'AIMS Admin',
    'plate'=>'',
    'forceCodeChange'=>false,
    'language'=>'hu',
    'adminPushRegistered'=>$adminPushRegistered,
    'adminPushError'=>$adminPushError,
    'adminSessionToken'=>$adminSessionToken,
    'adminSessionExpiresAt'=>$adminSessionExpiresAt,
    'serverPushConfigured'=>aims_push_config()!==null,
  ]);
}

$plate=aims_normalize_plate($login);
$driverCode=flow_normalize_driver_code($password);

if($plate!==''&&flow_driver_code_format_valid($driverCode)){
  $plateRate=aims_rate_limit('flow-driver-plate',$plate,12,3600,false);
  if(!$plateRate['allowed']) flow_reply(['ok'=>false,'error'=>'rate_limited'],429);

  try{
    $pdo=aims_db();
    $q=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate LIMIT 1');
    $q->execute([':plate'=>$plate]);
    $vehicle=$q->fetch(PDO::FETCH_ASSOC);
    $reason='invalid';

    if($vehicle&&!empty($vehicle['enabled'])&&flow_vehicle_driver_code_valid($vehicle,$driverCode,$reason)){
      aims_rate_limit_clear('flow-native-login',$key);
      aims_rate_limit_clear('flow-driver-plate',$plate);
      aims_audit('flow_native_login',['actor'=>'driver','detail'=>$plate,'result'=>'ok']);
      flow_reply([
        'ok'=>true,
        'role'=>'driver',
        'displayName'=>$vehicle['label']??$plate,
        'plate'=>$plate,
        'forceCodeChange'=>$reason==='temp',
        'language'=>in_array($vehicle['driver_language']??'hu',['hu','en','de'],true)?$vehicle['driver_language']:'hu',
      ]);
    }

    aims_rate_limit('flow-driver-plate',$plate,12,3600,true);
    if($reason==='temp_expired') flow_reply(['ok'=>false,'error'=>'temp_expired'],401);
  }catch(Throwable $e){}
}

aims_rate_limit('flow-native-login',$key,6,900,true);
usleep(250000);
flow_reply(['ok'=>false,'error'=>'invalid_credentials'],401);

