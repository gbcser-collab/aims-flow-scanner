<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
require_once __DIR__.'/../inc/portal.php';
aims_require_admin();
aims_start_session();

$trackingRoot=is_file(__DIR__.'/../api/aims-tracking/bootstrap.php')
  ? __DIR__.'/../api/aims-tracking'
  : __DIR__.'/../server/aims-tracking';
require_once $trackingRoot.'/bootstrap.php';
require_once $trackingRoot.'/driver_auth_v2.php';

$pdo=aims_db();
aims_driver_auth_schema($pdo);
$csrf=aims_admin_csrf();

function flow_access_redirect():never{
  header('Location: aims-flow-driver-access.php',true,303);
  exit;
}

function flow_access_flash(bool $ok,string $message,array $credentials=[]):void{
  $_SESSION['flow_access_flash']=[
    'ok'=>$ok,
    'message'=>$message,
    'credentials'=>$credentials,
  ];
}

function flow_access_mail(string $email,string $name,string $flowId,string $pin):bool{
  $from=trim((string)(getenv('AIMS_FLOW_FROM_EMAIL')?:'Start@logistic-aims.hu'));
  $subject='AIMS FLOW belépési adatok';
  $driver=$name!==''?$name:'Kolléga';
  $body="Kedves {$driver}!\n\n"
      ."Az AIMS FLOW sofőralkalmazás belépési adatai:\n\n"
      ."FLOW ID: {$flowId}\n"
      ."PIN: {$pin}\n\n"
      ."A PIN öt számjegyből áll. A sikeres belépés után a telefon megjegyzi a munkamenetet. "
      ."A belépési adatokat ne add át másnak.\n\n"
      ."Logistic-A.I.M.S.";
  $headers=[
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'From: AIMS FLOW <'.$from.'>',
    'Reply-To: '.$from,
  ];
  return @mail($email,'=?UTF-8?B?'.base64_encode($subject).'?=',$body,implode("\r\n",$headers));
}

if(($_SERVER['REQUEST_METHOD']??'')==='POST'){
  $provided=trim((string)($_POST['csrf']??''));
  if($provided===''||!hash_equals($csrf,$provided)){
    http_response_code(403);exit('CSRF');
  }

  $action=trim((string)($_POST['action']??''));
  $now=gmdate(DateTimeInterface::ATOM);

  if($action==='create'){
    $email=mb_strtolower(trim((string)($_POST['email']??'')),'UTF-8');
    $name=trim((string)($_POST['driver_name']??''));
    $plate=aims_normalize_plate((string)($_POST['plate']??''));
    if(!filter_var($email,FILTER_VALIDATE_EMAIL)){
      flow_access_flash(false,'Érvényes e-mail-cím szükséges.');flow_access_redirect();
    }
    if($name!==''&&(mb_strlen($name,'UTF-8')<2||mb_strlen($name,'UTF-8')>80)){
      flow_access_flash(false,'A sofőr neve hibás.');flow_access_redirect();
    }

    $vehicleId=null;
    if($plate!==''){
      $q=$pdo->prepare('SELECT id,enabled FROM vehicles WHERE plate=:plate LIMIT 1');
      $q->execute([':plate'=>$plate]);$vehicle=$q->fetch(PDO::FETCH_ASSOC);
      if(!$vehicle){
        $adminId=aims_ensure_default_admin($pdo);
        $insert=$pdo->prepare('INSERT INTO vehicles
          (plate,label,admin_user_id,enabled,created_at)
          VALUES (:plate,:label,:admin,1,:created)');
        $insert->execute([
          ':plate'=>$plate,':label'=>$plate,':admin'=>$adminId,':created'=>$now,
        ]);
        $vehicleId=(int)$pdo->lastInsertId();
      }else{
        if((int)$vehicle['enabled']!==1){
          flow_access_flash(false,'A megadott jármű le van tiltva.');flow_access_redirect();
        }
        $vehicleId=(int)$vehicle['id'];
      }
    }

    $flowId=aims_driver_generate_unique_flow_id($pdo);
    $pin=aims_driver_generate_pin();
    try{
      $stmt=$pdo->prepare('INSERT INTO driver_accounts
        (flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at)
        VALUES (:flow,:pin,:email,:name,:vehicle,:onboarding,1,:created,:updated)');
      $stmt->execute([
        ':flow'=>$flowId,
        ':pin'=>password_hash($pin,PASSWORD_DEFAULT),
        ':email'=>$email,
        ':name'=>$name,
        ':vehicle'=>$vehicleId,
        ':onboarding'=>($vehicleId!==null&&$name!=='')?1:0,
        ':created'=>$now,
        ':updated'=>$now,
      ]);
    }catch(Throwable $error){
      flow_access_flash(false,'A hozzáférés nem hozható létre: '.$error->getMessage());
      flow_access_redirect();
    }

    $mailed=flow_access_mail($email,$name,$flowId,$pin);
    aims_audit('flow_driver_account_created',[
      'actor'=>'admin','detail'=>$flowId.'|'.$email,'result'=>$mailed?'emailed':'mail_failed',
    ]);
    flow_access_flash(
      true,
      $mailed
        ? 'A FLOW ID és a PIN elküldve e-mailben.'
        : 'A hozzáférés elkészült, de az e-mail-küldés nem igazolható.',
      ['flowId'=>$flowId,'pin'=>$pin,'email'=>$email,'mailed'=>$mailed]
    );
    flow_access_redirect();
  }

  $accountId=max(0,(int)($_POST['account_id']??0));
  $accountQuery=$pdo->prepare('SELECT * FROM driver_accounts WHERE id=:id LIMIT 1');
  $accountQuery->execute([':id'=>$accountId]);
  $account=$accountQuery->fetch(PDO::FETCH_ASSOC);
  if(!$account){flow_access_flash(false,'A sofőr-hozzáférés nem található.');flow_access_redirect();}

  if($action==='reissue_pin'){
    $pin=aims_driver_generate_pin();
    $pdo->beginTransaction();
    try{
      $pdo->prepare('UPDATE driver_accounts SET pin_hash=:pin,updated_at=:updated WHERE id=:id')
        ->execute([':pin'=>password_hash($pin,PASSWORD_DEFAULT),':updated'=>$now,':id'=>$accountId]);
      $pdo->prepare('UPDATE driver_sessions SET revoked_at=:now WHERE account_id=:account AND revoked_at IS NULL')
        ->execute([':now'=>$now,':account'=>$accountId]);
      $pdo->commit();
    }catch(Throwable $error){if($pdo->inTransaction())$pdo->rollBack();throw $error;}
    $mailed=flow_access_mail((string)$account['email'],(string)$account['driver_name'],(string)$account['flow_id'],$pin);
    aims_audit('flow_driver_pin_reissued',['actor'=>'admin','detail'=>(string)$account['flow_id'],'result'=>$mailed?'emailed':'mail_failed']);
    flow_access_flash(true,$mailed?'Új PIN elküldve e-mailben.':'Új PIN elkészült; az e-mail-küldés nem igazolható.',[
      'flowId'=>(string)$account['flow_id'],'pin'=>$pin,'email'=>(string)$account['email'],'mailed'=>$mailed,
    ]);
    flow_access_redirect();
  }

  if($action==='toggle'){
    $enabled=((int)$account['enabled'])===1?0:1;
    $pdo->prepare('UPDATE driver_accounts SET enabled=:enabled,updated_at=:updated WHERE id=:id')
      ->execute([':enabled'=>$enabled,':updated'=>$now,':id'=>$accountId]);
    if($enabled===0){
      $pdo->prepare('UPDATE driver_sessions SET revoked_at=:now WHERE account_id=:account AND revoked_at IS NULL')
        ->execute([':now'=>$now,':account'=>$accountId]);
    }
    flow_access_flash(true,$enabled===1?'Sofőr-hozzáférés engedélyezve.':'Sofőr-hozzáférés letiltva.');
    flow_access_redirect();
  }

  if($action==='revoke_sessions'){
    $stmt=$pdo->prepare('UPDATE driver_sessions SET revoked_at=:now WHERE account_id=:account AND revoked_at IS NULL');
    $stmt->execute([':now'=>$now,':account'=>$accountId]);
    flow_access_flash(true,$stmt->rowCount().' aktív munkamenet visszavonva.');
    flow_access_redirect();
  }

  flow_access_flash(false,'Ismeretlen művelet.');flow_access_redirect();
}

$flash=$_SESSION['flow_access_flash']??null;unset($_SESSION['flow_access_flash']);
$rows=$pdo->query('SELECT a.*,v.plate,v.label,
  (SELECT COUNT(*) FROM driver_sessions s WHERE s.account_id=a.id AND s.revoked_at IS NULL AND s.expires_at>CURRENT_TIMESTAMP) AS active_sessions
  FROM driver_accounts a LEFT JOIN vehicles v ON v.id=a.vehicle_id
  ORDER BY a.enabled DESC,a.created_at DESC')->fetchAll(PDO::FETCH_ASSOC);
?>
<!doctype html><html lang="hu"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AIMS FLOW • Sofőr-hozzáférések</title>
<style>
:root{--bg:#080a0c;--panel:#111417;--line:#2a2e32;--text:#f3f4f5;--muted:#8a939a;--blue:#1478ff;--ok:#48c78e;--bad:#ff6b72;--warn:#e7b95c}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:Arial,sans-serif}.wrap{max-width:1180px;margin:auto;padding:22px}.head{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-bottom:18px}.head h1{margin:0;font-size:28px}.head a,.btn,button{border:1px solid var(--line);background:#171b1f;color:#fff;border-radius:10px;padding:10px 13px;text-decoration:none;font-weight:900;cursor:pointer}.primary{background:var(--blue);border-color:var(--blue)}.danger{background:#321316;border-color:#743039}.panel{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:16px;margin-bottom:14px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.grid label{font-size:10px;color:var(--muted);font-weight:900;text-transform:uppercase;letter-spacing:.08em}.grid input{display:block;width:100%;margin-top:6px;min-height:46px;border:1px solid var(--line);background:#090b0d;color:#fff;border-radius:10px;padding:0 12px}.full{grid-column:1/-1}.notice{border-radius:12px;padding:12px 14px;margin-bottom:14px;border:1px solid}.success{background:#0d241a;border-color:#286548}.error{background:#2b1114;border-color:#783139}.credentials{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}.credential{background:#060708;border:1px solid #3a3f44;border-radius:12px;padding:12px}.credential small{display:block;color:var(--muted);font-size:9px}.credential b{display:block;font-size:22px;margin-top:5px;letter-spacing:.08em}.table{overflow:auto}table{width:100%;border-collapse:collapse;min-width:980px}th,td{text-align:left;border-bottom:1px solid #25292d;padding:11px 9px;vertical-align:top}th{color:var(--muted);font-size:9px;text-transform:uppercase;letter-spacing:.08em}.chip{display:inline-block;border:1px solid #394048;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900}.chip.ok{color:var(--ok)}.chip.bad{color:var(--bad)}.chip.warn{color:var(--warn)}.actions{display:flex;gap:6px;flex-wrap:wrap}.muted{color:var(--muted);font-size:11px}@media(max-width:780px){.grid,.credentials{grid-template-columns:1fr}.head{align-items:flex-start;flex-direction:column}.wrap{padding:14px}}
</style></head><body><div class="wrap">
<div class="head"><div><div class="muted">LOGISTIC-A.I.M.S.</div><h1>AIMS FLOW • Sofőr-hozzáférések</h1></div><div class="actions"><a href="aims-flow.php">← FLOW ADMIN</a><a href="logout.php">KILÉPÉS</a></div></div>
<?php if(is_array($flash)):?><div class="notice <?=!empty($flash['ok'])?'success':'error'?>"><?=portal_h($flash['message']??'')?>
<?php if(!empty($flash['credentials'])):$cr=$flash['credentials'];?><div class="credentials"><div class="credential"><small>FLOW ID</small><b><?=portal_h($cr['flowId'])?></b></div><div class="credential"><small>EGYSZERI PIN</small><b><?=portal_h($cr['pin'])?></b></div><div class="credential"><small>E-MAIL</small><b style="font-size:14px;letter-spacing:0"><?=portal_h($cr['email'])?></b><div class="muted"><?=!empty($cr['mailed'])?'Kiküldve':'Kézzel is add át, mert a kiküldés nem igazolt.'?></div></div></div><p class="muted">A PIN csak ebben az üzenetben látható. Az adatbázisban kizárólag a hash kerül tárolásra.</p><?php endif;?></div><?php endif;?>
<section class="panel"><h2>Új kolléga meghívása</h2><p class="muted">A rendszer automatikusan létrehozza a 6 jegyű FLOW ID-t és az 5 jegyű PIN-t, majd e-mailben elküldi.</p><form method="post" class="grid"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="create"><label>E-mail<input required type="email" name="email" placeholder="sofor@ceg.hu"></label><label>Sofőr neve<input name="driver_name" placeholder="Megadható később is"></label><label>Rendszám<input name="plate" placeholder="Megadható az első belépéskor"></label><div class="full"><button class="primary" type="submit">FLOW ID + PIN LÉTREHOZÁSA</button></div></form></section>
<section class="panel"><h2>Aktív és korábbi hozzáférések</h2><div class="table"><table><thead><tr><th>FLOW ID</th><th>Sofőr</th><th>E-mail</th><th>Jármű</th><th>Onboarding</th><th>Session</th><th>Utolsó belépés</th><th>Állapot</th><th>Művelet</th></tr></thead><tbody>
<?php if(!$rows):?><tr><td colspan="9">Még nincs FLOW ID-val rendelkező sofőr.</td></tr><?php else:foreach($rows as $row):?>
<tr><td><b style="font-size:16px;letter-spacing:.08em"><?=portal_h($row['flow_id'])?></b></td><td><?=portal_h($row['driver_name']?:'—')?></td><td><?=portal_h($row['email'])?></td><td><?=portal_h($row['plate']?:'—')?></td><td><?=!empty($row['onboarding_complete'])?'<span class="chip ok">KÉSZ</span>':'<span class="chip warn">ELSŐ BELÉPÉS</span>'?></td><td><span class="chip"><?=intval($row['active_sessions'])?> aktív</span></td><td><?=portal_h($row['last_login_at']?:'—')?></td><td><?=!empty($row['enabled'])?'<span class="chip ok">AKTÍV</span>':'<span class="chip bad">LETILTVA</span>'?></td><td><div class="actions"><form method="post"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="reissue_pin"><input type="hidden" name="account_id" value="<?=intval($row['id'])?>"><button type="submit">ÚJ PIN</button></form><form method="post"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="revoke_sessions"><input type="hidden" name="account_id" value="<?=intval($row['id'])?>"><button type="submit">SESSION TÖRLÉS</button></form><form method="post"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="toggle"><input type="hidden" name="account_id" value="<?=intval($row['id'])?>"><button class="<?=!empty($row['enabled'])?'danger':''?>" type="submit"><?=!empty($row['enabled'])?'LETILTÁS':'ENGEDÉLYEZÉS'?></button></form></div></td></tr>
<?php endforeach;endif;?></tbody></table></div></section>
</div></body></html>
