<?php
declare(strict_types=1);

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');

const DEFAULT_MAIL_TO = 'office@logistic-aims.hu';
const RETENTION_DAYS = 15;

function envv(string $name, string $default = ''): string {
    $v = getenv($name);
    return $v === false ? $default : trim((string)$v);
}
function json_response(array $payload, int $status = 200): never {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
function body_json(): array {
    $raw = file_get_contents('php://input') ?: '';
    if ($raw === '') return [];
    try { $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR); }
    catch (Throwable $e) { json_response(['error' => 'invalid_json'], 400); }
    return is_array($decoded) ? $decoded : [];
}
function request_path(): string {
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
    $script = $_SERVER['SCRIPT_NAME'] ?? '';
    if ($script !== '' && str_starts_with($path, $script)) $path = substr($path, strlen($script));
    elseif (preg_match('#/api(?:/index\.php)?(?<rest>/.*)?$#', $path, $m)) $path = $m['rest'] ?? '/';
    $path = '/' . ltrim($path, '/');
    return rtrim($path, '/') ?: '/';
}
function bearer_token(): string {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    return preg_match('/^Bearer\s+(.+)$/i', $header, $m) ? trim($m[1]) : '';
}
function require_device_auth(): void {
    $expected = envv('AIMS_DEVICE_TOKEN');
    if ($expected === '') json_response(['error' => 'device_auth_not_configured'], 503);
    $got = bearer_token();
    if ($got === '' || !hash_equals($expected, $got)) json_response(['error' => 'unauthorized_device'], 401);
}
function start_admin_session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
    session_name('AIMSADMIN');
    session_set_cookie_params(['lifetime'=>0,'path'=>'/','secure'=>$secure,'httponly'=>true,'samesite'=>'Strict']);
    session_start();
}
function require_admin(): void {
    start_admin_session();
    if (!empty($_SESSION['aims_admin']) && $_SESSION['aims_admin'] === true) return;
    $token = envv('AIMS_ADMIN_TOKEN');
    if ($token !== '' && bearer_token() !== '' && hash_equals($token, bearer_token())) return;
    json_response(['error' => 'admin_auth_required'], 401);
}
function storage_dir(): string {
    $custom = envv('AIMS_STORAGE_DIR');
    $dir = $custom !== '' ? $custom : dirname(__DIR__) . '/storage';
    if (!is_dir($dir) && !mkdir($dir, 0700, true) && !is_dir($dir)) json_response(['error'=>'storage_unavailable'],500);
    return rtrim($dir, '/');
}
function db_path(): string { return storage_dir() . '/aims-db.json'; }
function empty_db(): array { return ['documents'=>[], 'audit'=>[]]; }
function normalize_db(mixed $db): array {
    if (!is_array($db)) return empty_db();
    if (!isset($db['documents']) || !is_array($db['documents'])) $db['documents'] = [];
    if (!isset($db['audit']) || !is_array($db['audit'])) $db['audit'] = [];
    return $db;
}
function db_read(): array {
    $path = db_path();
    if (!is_file($path)) return empty_db();
    $fp = fopen($path, 'rb');
    if (!$fp) throw new RuntimeException('db_open_failed');
    try {
        flock($fp, LOCK_SH);
        $raw = stream_get_contents($fp) ?: '';
        flock($fp, LOCK_UN);
    } finally { fclose($fp); }
    if (trim($raw) === '') return empty_db();
    try { return normalize_db(json_decode($raw, true, 512, JSON_THROW_ON_ERROR)); }
    catch (Throwable $e) { throw new RuntimeException('db_corrupt'); }
}
function db_mutate(callable $fn): mixed {
    $path = db_path();
    $fp = fopen($path, 'c+b');
    if (!$fp) throw new RuntimeException('db_open_failed');
    try {
        if (!flock($fp, LOCK_EX)) throw new RuntimeException('db_lock_failed');
        rewind($fp);
        $raw = stream_get_contents($fp) ?: '';
        $db = trim($raw) === '' ? empty_db() : normalize_db(json_decode($raw, true, 512, JSON_THROW_ON_ERROR));
        [$db, $result] = $fn($db);
        $encoded = json_encode($db, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        if ($encoded === false) throw new RuntimeException('db_encode_failed');
        rewind($fp); ftruncate($fp, 0);
        if (fwrite($fp, $encoded) === false) throw new RuntimeException('db_write_failed');
        fflush($fp); flock($fp, LOCK_UN);
        @chmod($path, 0600);
        return $result;
    } finally { fclose($fp); }
}
function now_iso(): string { return gmdate('c'); }
function random_id(): string { return 'cmr_' . bin2hex(random_bytes(12)); }
function audit(string $action, ?string $documentId=null, ?string $actor=null, array $meta=[]): void {
    db_mutate(function(array $db) use($action,$documentId,$actor,$meta) {
        $db['audit'][]=['at'=>now_iso(),'action'=>$action,'documentId'=>$documentId,'actor'=>$actor,'meta'=>$meta];
        if (count($db['audit']) > 5000) $db['audit'] = array_slice($db['audit'], -5000);
        return [$db, null];
    });
}
function cmr_row(string $serverId='', string $localId=''): ?array {
    $docs = db_read()['documents'];
    if ($serverId !== '' && isset($docs[$serverId]) && is_array($docs[$serverId])) return $docs[$serverId];
    if ($localId !== '') {
        foreach ($docs as $row) if (is_array($row) && ($row['local_id'] ?? '') === $localId) return $row;
    }
    return null;
}
function public_state(array $row): array {
    return ['serverDocumentId'=>$row['id'],'localId'=>$row['local_id'],'state'=>$row['state'],'uploadedAt'=>$row['received_at'],'emailedAt'=>$row['emailed_at']??null,'approvedAt'=>$row['approved_at']??null,'deleteAfter'=>$row['delete_after']??null];
}
function save_image(array $image, string $id): string {
    $base64=(string)($image['base64']??'');
    if ($base64==='') json_response(['error'=>'image_missing'],422);
    $bytes=base64_decode($base64,true);
    if ($bytes===false || strlen($bytes)<128) json_response(['error'=>'invalid_image'],422);
    if (strlen($bytes)>15*1024*1024) json_response(['error'=>'image_too_large'],413);
    if (substr($bytes,0,2)!=="\xFF\xD8") json_response(['error'=>'image_not_jpeg'],422);
    $dir=storage_dir().'/cmr'; if(!is_dir($dir)) mkdir($dir,0700,true);
    $path=$dir.'/'.$id.'.jpg';
    if(file_put_contents($path,$bytes,LOCK_EX)===false) json_response(['error'=>'image_write_failed'],500);
    @chmod($path,0600); return $path;
}
function cmr_summary(array $cmr): string {
    $pairs=['CMR'=>$cmr['cmrNumber']??null,'Feladó'=>$cmr['shipper']??null,'Címzett'=>$cmr['consignee']??null,'Felrakóhely'=>$cmr['loadingPlace']??null,'Lerakóhely'=>$cmr['deliveryPlace']??null,'Dátum'=>$cmr['date']??null,'Rendszám'=>$cmr['plate']??null,'Darabszám'=>$cmr['packageCount']??null,'Bruttó tömeg'=>isset($cmr['grossWeightKg'])?($cmr['grossWeightKg'].' kg'):null,'Áru'=>$cmr['goodsDescription']??null];
    $lines=[]; foreach($pairs as $k=>$v) $lines[]=$k.': '.(($v===null||$v==='')?'—':(string)$v); return implode("\r\n",$lines);
}
function send_cmr_mail(array $row,array $payload): array {
    $to=envv('AIMS_MAIL_TO',DEFAULT_MAIL_TO); $from=envv('AIMS_MAIL_FROM',DEFAULT_MAIL_TO);
    $cmr=is_array($payload['cmr']??null)?$payload['cmr']:[]; $plate=trim((string)($cmr['plate']??'')); $cmrNo=trim((string)($cmr['cmrNumber']??''));
    $subject='AIMS Flow CMR'.($cmrNo!==''?' #'.$cmrNo:'').($plate!==''?' • '.$plate:'');
    $location=is_array($payload['location']??null)?$payload['location']:[]; $locText='—';
    if(isset($location['latitude'],$location['longitude'])){$lat=(float)$location['latitude'];$lng=(float)$location['longitude'];$locText=sprintf('%.6f, %.6f | https://www.google.com/maps?q=%.6f,%.6f',$lat,$lng,$lat,$lng);}
    $text="AIMS Flow automatikus CMR\r\n\r\n".cmr_summary($cmr)."\r\n\r\n".'Készítés ideje: '.((string)($payload['createdAt']??'—'))."\r\n".'Szerver fogadás: '.$row['received_at']."\r\n".'Készülék: '.$row['device_id']."\r\n".'Hely: '.$locText."\r\n".'Minőség: '.((string)($payload['qualityScore']??'—'))."/100\r\n".'Szerver CMR ID: '.$row['id']."\r\n";
    $boundary='=_AIMS_'.bin2hex(random_bytes(12)); $filename='CMR-'.($cmrNo!==''?preg_replace('/[^A-Za-z0-9_-]/','_',$cmrNo):$row['id']).'.jpg';
    $bytes=file_get_contents($row['image_path']); if($bytes===false)return[false,'attachment_read_failed'];
    $headers=['From: Logistic-A.I.M.S. <'.$from.'>','Reply-To: '.$from,'MIME-Version: 1.0','Content-Type: multipart/mixed; boundary="'.$boundary.'"','X-AIMS-Source: AIMS-Flow'];
    $body='--'.$boundary."\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n".$text."\r\n".'--'.$boundary."\r\n".'Content-Type: image/jpeg; name="'.$filename.'"'."\r\n".'Content-Disposition: attachment; filename="'.$filename.'"'."\r\nContent-Transfer-Encoding: base64\r\n\r\n".chunk_split(base64_encode($bytes))."\r\n".'--'.$boundary."--\r\n";
    if(strtolower(envv('AIMS_MAIL_MODE'))==='log'){$outbox=storage_dir().'/outbox';if(!is_dir($outbox))mkdir($outbox,0700,true);$eml='To: '.$to."\r\nSubject: ".$subject."\r\n".implode("\r\n",$headers)."\r\n\r\n".$body;$ok=file_put_contents($outbox.'/'.$row['id'].'.eml',$eml,LOCK_EX)!==false;return[$ok,$ok?null:'mail_log_write_failed'];}
    $ok=@mail($to,'=?UTF-8?B?'.base64_encode($subject).'?=',$body,implode("\r\n",$headers)); return[$ok,$ok?null:'php_mail_failed'];
}

$method=strtoupper($_SERVER['REQUEST_METHOD']??'GET'); $path=request_path();
try {
    if($method==='GET' && $path==='/health'){ db_read(); json_response(['ok'=>true,'service'=>'aims-flow-cmr','time'=>now_iso()]); }

    if($method==='POST' && $path==='/cmr/sync'){
        require_device_auth(); $payload=body_json(); $localId=trim((string)($payload['localId']??'')); $deviceId=trim((string)($payload['deviceId']??''));
        if($localId===''||$deviceId==='')json_response(['error'=>'localId_and_deviceId_required'],422);
        $db=db_read(); foreach($db['documents'] as $row){if(($row['local_id']??'')===$localId&&($row['device_id']??'')===$deviceId)json_response(public_state($row));}
        $id=random_id(); $received=now_iso(); $pathSaved=save_image(is_array($payload['image']??null)?$payload['image']:[],$id); $createdAt=trim((string)($payload['createdAt']??''))?:$received;
        $row=['id'=>$id,'local_id'=>$localId,'device_id'=>$deviceId,'created_at'=>$createdAt,'received_at'=>$received,'updated_at'=>$received,'state'=>'uploaded','image_path'=>$pathSaved,'cmr_json'=>json_encode($payload['cmr']??[],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),'quality_score'=>isset($payload['qualityScore'])?(int)$payload['qualityScore']:null,'emailed_at'=>null,'email_error'=>null,'approved_at'=>null,'delete_after'=>null,'approved_by'=>null];
        $inserted=db_mutate(function(array $db) use($row,$localId,$deviceId){foreach($db['documents'] as $existing){if(($existing['local_id']??'')===$localId&&($existing['device_id']??'')===$deviceId)return[$db,$existing];}$db['documents'][$row['id']]=$row;return[$db,$row];});
        if(($inserted['id']??'')!==$id){@unlink($pathSaved);json_response(public_state($inserted));}
        audit('cmr_uploaded',$id,$deviceId,['localId'=>$localId]); [$mailOk,$mailError]=send_cmr_mail($row,$payload);
        if($mailOk){$emailed=now_iso();$row=db_mutate(function(array $db)use($id,$emailed){$r=$db['documents'][$id];$r['state']='emailed';$r['emailed_at']=$emailed;$r['email_error']=null;$r['updated_at']=$emailed;$db['documents'][$id]=$r;return[$db,$r];});audit('cmr_emailed',$id,'system',['to'=>envv('AIMS_MAIL_TO',DEFAULT_MAIL_TO)]);}
        else{$row=db_mutate(function(array $db)use($id,$mailError){$r=$db['documents'][$id];$r['email_error']=$mailError;$r['updated_at']=now_iso();$db['documents'][$id]=$r;return[$db,$r];});audit('cmr_email_failed',$id,'system',['error'=>$mailError]);}
        json_response(public_state($row),201);
    }

    if($method==='GET' && $path==='/cmr/status'){require_device_auth();$row=cmr_row(trim((string)($_GET['serverDocumentId']??'')),trim((string)($_GET['localId']??'')));if(!$row)json_response(['error'=>'not_found'],404);json_response(public_state($row));}

    if($method==='POST' && $path==='/admin/login'){start_admin_session();$payload=body_json();$hash=envv('AIMS_ADMIN_PASSWORD_HASH');if($hash==='')json_response(['error'=>'admin_login_not_configured'],503);if(!password_verify((string)($payload['password']??''),$hash)){usleep(350000);audit('admin_login_failed',null,$_SERVER['REMOTE_ADDR']??'unknown');json_response(['error'=>'invalid_credentials'],401);}session_regenerate_id(true);$_SESSION['aims_admin']=true;$_SESSION['aims_admin_at']=time();audit('admin_login',null,$_SERVER['REMOTE_ADDR']??'unknown');json_response(['ok'=>true]);}
    if($method==='POST' && $path==='/admin/logout'){start_admin_session();$_SESSION=[];session_destroy();json_response(['ok'=>true]);}

    if($method==='GET' && $path==='/admin/cmr'){require_admin();$limit=max(1,min(200,(int)($_GET['limit']??100)));$docs=array_values(db_read()['documents']);usort($docs,fn($a,$b)=>strcmp((string)($b['received_at']??''),(string)($a['received_at']??'')));$docs=array_slice($docs,0,$limit);$rows=[];foreach($docs as $row){$row['cmr']=json_decode($row['cmr_json']??'{}',true)?:[];unset($row['cmr_json'],$row['image_path']);$rows[]=$row;}json_response(['documents'=>$rows]);}

    if($method==='POST' && preg_match('#^/admin/cmr/([^/]+)/approve$#',$path,$m)){require_admin();$id=rawurldecode($m[1]);$row=cmr_row($id,'');if(!$row)json_response(['error'=>'not_found'],404);if(empty($row['emailed_at']))json_response(['error'=>'cannot_approve_before_email'],409);if(!empty($row['approved_at']))json_response(public_state($row));$approved=new DateTimeImmutable('now',new DateTimeZone('UTC'));$deleteAfter=$approved->modify('+'.RETENTION_DAYS.' days');$row=db_mutate(function(array $db)use($id,$approved,$deleteAfter){$r=$db['documents'][$id];$r['state']='approved';$r['approved_at']=$approved->format(DATE_ATOM);$r['delete_after']=$deleteAfter->format(DATE_ATOM);$r['approved_by']='admin';$r['updated_at']=now_iso();$db['documents'][$id]=$r;return[$db,$r];});audit('cmr_approved',$id,'admin',['deleteAfter'=>$deleteAfter->format(DATE_ATOM)]);json_response(public_state($row));}

    if($method==='POST' && preg_match('#^/admin/cmr/([^/]+)/retry-email$#',$path,$m)){require_admin();$id=rawurldecode($m[1]);$row=cmr_row($id,'');if(!$row)json_response(['error'=>'not_found'],404);$payload=['cmr'=>json_decode($row['cmr_json']??'{}',true)?:[],'createdAt'=>$row['created_at'],'qualityScore'=>$row['quality_score']];[$mailOk,$mailError]=send_cmr_mail($row,$payload);if(!$mailOk){db_mutate(function(array $db)use($id,$mailError){$r=$db['documents'][$id];$r['email_error']=$mailError;$r['updated_at']=now_iso();$db['documents'][$id]=$r;return[$db,$r];});json_response(['error'=>'mail_failed','detail'=>$mailError],502);} $emailed=now_iso();$row=db_mutate(function(array $db)use($id,$emailed){$r=$db['documents'][$id];$r['state']='emailed';$r['emailed_at']=$emailed;$r['email_error']=null;$r['updated_at']=$emailed;$db['documents'][$id]=$r;return[$db,$r];});audit('cmr_emailed_retry',$id,'admin');json_response(public_state($row));}

    json_response(['error'=>'route_not_found','path'=>$path],404);
} catch(Throwable $e){error_log('[AIMS API] '.$e->getMessage());json_response(['error'=>'server_error'],500);}
