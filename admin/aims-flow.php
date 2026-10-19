<?php
require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();aims_start_session();
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';
$csrf=aims_admin_csrf();
$flowFlash=$_SESSION['aims_flow_dispatch_flash']??null;unset($_SESSION['aims_flow_dispatch_flash']);
$sourceJob=null;$sourceId=trim((string)($_GET['source']??''));
if($sourceId!==''){$sourceJob=portal_job_by_id($sourceId);}
$flowPdo=aims_db();
$flowPhoneCount=(int)$flowPdo->query('SELECT COUNT(*) FROM driver_push_devices WHERE enabled=1')->fetchColumn();
$flowActiveJobs=(int)$flowPdo->query('SELECT COUNT(*) FROM jobs WHERE status="active"')->fetchColumn();
$flowActiveJobRows=$flowPdo->query('SELECT j.id,j.reference,j.driver_seen_at,j.driver_accepted_at,j.updated_at,
    j.customer_tracking_token_hash,j.customer_tracking_expires_at,j.order_payload_json,v.plate,v.label
  FROM jobs j JOIN vehicles v ON v.id=j.vehicle_id
  WHERE j.status="active"
  ORDER BY j.id DESC LIMIT 100')->fetchAll(PDO::FETCH_ASSOC);
$flowRegistrationPoints=$flowPdo->query('SELECT id,company_name,address,stop_type,latitude,longitude,accuracy,confirmations,updated_at FROM registration_points ORDER BY updated_at DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
$flowPhones=$flowPdo->query('SELECT d.device_id,d.platform,d.updated_at,d.enabled,v.plate FROM driver_push_devices d JOIN vehicles v ON v.id=d.vehicle_id ORDER BY d.updated_at DESC LIMIT 50')->fetchAll(PDO::FETCH_ASSOC);
$flowDriverVehicles=$flowPdo->query('SELECT plate,label,enabled,created_at,driver_email,driver_language,driver_code_hash,driver_code_is_temp,driver_code_expires_at,driver_reset_status,driver_reset_requested_at FROM vehicles ORDER BY plate ASC')->fetchAll(PDO::FETCH_ASSOC);
$flowResetSnapshot=[];foreach($flowDriverVehicles as $rv){if(!empty($rv['enabled'])&&($rv['driver_reset_status']??'')==='pending')$flowResetSnapshot[]=['plate'=>(string)($rv['plate']??''),'requestedAt'=>(string)($rv['driver_reset_requested_at']??'')];}
usort($flowResetSnapshot,function($a,$b){$t=strcmp((string)($b['requestedAt']??''),(string)($a['requestedAt']??''));return $t!==0?$t:strcmp((string)($a['plate']??''),(string)($b['plate']??''));});
$flowResetSignature=hash('sha256',json_encode($flowResetSnapshot,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));

$flowOpsFlash=$_SESSION['aims_flow_ops_flash']??null;unset($_SESSION['aims_flow_ops_flash']);
$flowSince24h=gmdate(DateTimeInterface::ATOM,time()-86400);
$flowOpenWorkdays=(int)$flowPdo->query('SELECT COUNT(*) FROM driver_workdays WHERE finished_at IS NULL')->fetchColumn();
$flowOpenIssues=(int)$flowPdo->query('SELECT COUNT(*) FROM vehicle_issues WHERE status="open"')->fetchColumn();
$flowHoldCount=(int)$flowPdo->query('SELECT COUNT(*) FROM vehicle_operational_state WHERE hold=1')->fetchColumn();
$flowSafety24Stmt=$flowPdo->prepare('SELECT COUNT(*) FROM vehicle_safety_checks WHERE received_at>=:since');
$flowSafety24Stmt->execute([':since'=>$flowSince24h]);
$flowSafety24=(int)$flowSafety24Stmt->fetchColumn();

$flowWorkdayRows=$flowPdo->query('SELECT w.*,v.plate,v.label,j.reference
  FROM driver_workdays w
  JOIN vehicles v ON v.id=w.vehicle_id
  LEFT JOIN jobs j ON j.id=w.start_job_id
  ORDER BY w.started_at DESC LIMIT 100')->fetchAll(PDO::FETCH_ASSOC);

$flowSafetyRows=$flowPdo->query('SELECT c.*,v.plate,v.label,
  (SELECT id FROM vehicle_safety_photos p WHERE p.safety_check_id=c.id AND p.photo_type="oil" LIMIT 1) AS oil_photo_id,
  (SELECT id FROM vehicle_safety_photos p WHERE p.safety_check_id=c.id AND p.photo_type="coolant" LIMIT 1) AS coolant_photo_id,
  (SELECT id FROM vehicle_safety_photos p WHERE p.safety_check_id=c.id AND p.photo_type="tires" LIMIT 1) AS tires_photo_id,
  (SELECT id FROM vehicle_safety_photos p WHERE p.safety_check_id=c.id AND p.photo_type="odometer" LIMIT 1) AS odometer_photo_id
  FROM vehicle_safety_checks c
  JOIN vehicles v ON v.id=c.vehicle_id
  ORDER BY c.created_at DESC LIMIT 100')->fetchAll(PDO::FETCH_ASSOC);

$flowIssueRows=$flowPdo->query('SELECT i.*,v.plate,v.label,
  COALESCE(os.hold,0) AS vehicle_hold,COALESCE(os.hold_reason,"") AS hold_reason
  FROM vehicle_issues i
  JOIN vehicles v ON v.id=i.vehicle_id
  LEFT JOIN vehicle_operational_state os ON os.vehicle_id=i.vehicle_id
  ORDER BY CASE WHEN i.status="open" THEN 0 ELSE 1 END,i.urgent DESC,i.created_at DESC
  LIMIT 100')->fetchAll(PDO::FETCH_ASSOC);

$flowServiceRows=$flowPdo->query('SELECT s.*,v.plate,v.label,
  COALESCE(os.hold,0) AS vehicle_hold,
  (SELECT o.km FROM vehicle_odometer_log o WHERE o.vehicle_id=s.vehicle_id ORDER BY o.captured_at DESC,o.id DESC LIMIT 1) AS current_km
  FROM vehicle_service_items s
  JOIN vehicles v ON v.id=s.vehicle_id
  LEFT JOIN vehicle_operational_state os ON os.vehicle_id=s.vehicle_id
  WHERE s.enabled=1
  ORDER BY v.plate,s.due_km,s.due_date,s.id')->fetchAll(PDO::FETCH_ASSOC);
?><!doctype html><html lang="hu"><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow,noarchive"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="icon" href="../favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="48x48" href="../favicon-48x48.png"><link rel="apple-touch-icon" sizes="180x180" href="../apple-touch-icon.png"><title>AIMS Flow • Élő GPS és Scanner Admin</title><style>
:root{--g:#d9ad4e;--g2:#f2d77f;--bg:#08090b;--card:#0d0f11;--line:#29261f;--muted:#858078;--ok:#62dda0;--bad:#ff7d85;--amber:#efca69}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#eee;font:14px Arial,sans-serif}a{color:inherit;text-decoration:none}.wrap{width:min(1360px,calc(100% - 28px));margin:auto;padding:26px 0 70px}.head{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:18px}.ey{font-size:9px;letter-spacing:.14em;color:#8c7a4d;text-transform:uppercase}.head h1{margin:5px 0 0;font-size:28px}.head h1 span{color:var(--g2)}.nav{display:flex;gap:7px;flex-wrap:wrap}.nav a,.btn{border:1px solid var(--line);border-radius:999px;padding:9px 12px;font-size:10px;font-weight:800;background:#0c0e10;color:#eee;cursor:pointer}.nav a.active,.btn.gold{border:0;background:linear-gradient(135deg,#f1d77e,#b9852d);color:#090909}.statusbar{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:14px 0}.metric,.panel{border:1px solid var(--line);background:linear-gradient(180deg,#0f1113,#0a0b0d);border-radius:18px;padding:16px}.metric small,.panel small{font-size:8px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}.metric b{display:block;font-size:28px;color:var(--g2);margin-top:7px}.panel{margin-top:12px}.panelhead{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px}.panel h2{margin:3px 0 0;font-size:18px}.live{display:grid;grid-template-columns:1.25fr .75fr;gap:12px}.table{overflow:auto;border:1px solid #1e2022;border-radius:13px}table{width:100%;border-collapse:collapse;min-width:900px}th,td{text-align:left;padding:11px;border-bottom:1px solid #1d1f21;vertical-align:top}th{color:#827d72;font-size:8px;text-transform:uppercase;letter-spacing:.11em}.chip{display:inline-flex;align-items:center;gap:6px;padding:5px 8px;border:1px solid #333;border-radius:999px;font-size:8px;font-weight:900;text-transform:uppercase}.chip.ok{color:var(--ok);border-color:#28563e}.chip.bad{color:var(--bad);border-color:#603038}.chip.wait{color:var(--amber);border-color:#5b4e29}.mono{font:11px ui-monospace,SFMono-Regular,Consolas,monospace;color:#bcc3cb}.muted{color:#777;line-height:1.45;font-size:11px}.routebox{min-height:320px;display:flex;flex-direction:column;gap:10px}.routebox svg{width:100%;height:230px;border:1px solid #202327;border-radius:14px;background:radial-gradient(circle at 50% 50%,#111820,#090b0e 70%)}.route-meta{display:grid;grid-template-columns:1fr 1fr;gap:8px}.route-meta div{border:1px solid #202327;border-radius:11px;padding:9px}.route-meta small{display:block}.route-meta b{display:block;margin-top:4px}.actions{display:flex;gap:6px;flex-wrap:wrap}.actions button,.actions a{border:1px solid #34322a;background:#111315;color:#eee;border-radius:8px;padding:7px 9px;font-size:9px;font-weight:900;cursor:pointer}.actions .approve{background:linear-gradient(135deg,#f1d77e,#b9852d);color:#090909;border:0}.actions .danger{color:#ffadb1;border-color:#633}.actions .map{color:#a8d4ff;border-color:#31526a}.notice{border:1px solid #4f4529;background:#15130d;color:#d8c58e;border-radius:12px;padding:11px 13px;margin:10px 0}.error{border-color:#633;background:#1b1011;color:#ffb2b6}.success{border-color:#28563e;background:#0c1711;color:#9de4b9}.empty{padding:20px;color:#666;text-align:center}.dispatchgrid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}.dispatchgrid label{display:grid;gap:6px;color:#aaa;font-size:10px;font-weight:800}.dispatchgrid label.full{grid-column:1/-1}.dispatchgrid input{width:100%;min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px}.dispatchcheck{display:flex!important;grid-column:1/-1;align-items:center;gap:8px}.dispatchcheck input{width:auto;min-height:auto}.dispatchsend{grid-column:1/-1;border:0;border-radius:12px;min-height:50px;background:linear-gradient(135deg,#f1d77e,#b9852d);color:#090909;font-weight:1000;cursor:pointer}.spin{display:inline-block;width:10px;height:10px;border:2px solid #555;border-top-color:var(--g2);border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}@media(max-width:950px){.live{grid-template-columns:1fr}.statusbar{grid-template-columns:1fr 1fr}.head{align-items:flex-start;flex-direction:column}}@media(max-width:520px){.statusbar{grid-template-columns:1fr}.wrap{width:min(100% - 18px,1360px)}.head h1{font-size:23px}}
</style></head><body><div class="wrap"><div class="head"><div><div class="ey">LOGISTIC-A.I.M.S. • 2FA SECURE ADMIN</div><h1>AIMS Flow <span>Live Control</span></h1></div><div class="nav"><a href="index.php">Analytics</a><a href="partners.php">Partnerek</a><a href="freights.php">Fuvarok</a><a class="active" href="aims-flow.php">AIMS Flow / GPS</a><a href="foreign-stay-report.php">Riport lekérése</a><a href="automation.php">E-mail bot</a><a href="logout.php">Kilépés</a></div></div>
<div id="apiNotice" class="notice">A modul a telefonról beérkező <b>valós GPS-pontokat</b>, Flow-fuvarokat és Scanner-adatokat kezeli. Nincs demo/szimulált járműmozgás.</div>
<?php if(is_array($flowFlash)):?><div class="notice <?=!empty($flowFlash['ok'])?'success':'error'?>"><?=portal_h($flowFlash['message']??'')?><?php if(!empty($flowFlash['trackingUrl'])):?><div style="margin-top:10px"><input id="customerTrackingUrl" readonly value="<?=portal_h($flowFlash['trackingUrl'])?>" onclick="this.select()" style="width:100%;min-height:42px;border:1px solid #3c4b50;background:#07090b;color:#fff;padding:8px 10px"><button class="btn gold" type="button" style="margin-top:7px" onclick="navigator.clipboard&&navigator.clipboard.writeText(document.getElementById('customerTrackingUrl').value)">MEGBÍZÓI LINK MÁSOLÁSA</button></div><?php endif;?></div><?php endif;?>
<?php if(is_array($flowOpsFlash)):?><div class="notice <?=!empty($flowOpsFlash['ok'])?'success':'error'?>"><?=portal_h($flowOpsFlash['message']??'')?></div><?php endif;?>
<section class="panel"><div class="panelhead"><div><small>FLOW DISPATCH • FIREBASE PUSH</small><h2>Fuvar küldése a sofőr AIMS Flow appjába</h2></div><span class="chip ok"><?=$flowPhoneCount?> aktív mobil</span></div>
<form class="dispatchgrid" method="post" action="aims-flow-dispatch.php">
<input type="hidden" name="csrf" value="<?=portal_h($csrf)?>">
<label>Rendszám<input name="plate" required placeholder="pl. SIP-115"></label>
<label>Referencia<input name="reference" required value="<?=portal_h($sourceJob['reference']??'')?>" placeholder="pl. AIMS-240918"></label>
<label>Megbízó neve<input name="customer_name" value="<?=portal_h($sourceJob['customer']??$sourceJob['customer_name']??'')?>" placeholder="Megbízó / ügyfél"></label>
<label>Megbízó e-mail<input name="customer_email" type="email" value="<?=portal_h($sourceJob['customer_email']??'')?>" placeholder="dispatch@customer.eu"></label>
<label class="full">Felrakó cég<input name="pickup_company" value="<?=portal_h($sourceJob['pickup_company']??'')?>" placeholder="Felrakó cég neve"></label>
<label class="full">Felrakó pontos cím<input name="pickup_address" required value="<?=portal_h(!empty($sourceJob['pickup_address'])?$sourceJob['pickup_address']:trim(($sourceJob['pickup_country']??'').' '.($sourceJob['pickup_city']??'')))?>" placeholder="Ország, irányítószám, város, utca, házszám"></label>
<label class="full">Felrakó kapcsolattartó telefon<input name="pickup_phone" type="tel" inputmode="tel" value="<?=portal_h($sourceJob['pickup_phone']??'')?>" placeholder="+36 30 123 4567"></label>
<label class="full">Lerakó cég<input name="delivery_company" value="<?=portal_h($sourceJob['delivery_company']??'')?>" placeholder="Lerakó cég neve"></label>
<label class="full">Lerakó pontos cím<input name="delivery_address" required value="<?=portal_h(!empty($sourceJob['delivery_address'])?$sourceJob['delivery_address']:trim(($sourceJob['delivery_country']??'').' '.($sourceJob['delivery_city']??'')))?>" placeholder="Ország, irányítószám, város, utca, házszám"></label>
<label class="full">Lerakó kapcsolattartó telefon<input name="delivery_phone" type="tel" inputmode="tel" value="<?=portal_h($sourceJob['delivery_phone']??'')?>" placeholder="+36 30 123 4567"></label>
<label class="dispatchcheck"><input type="checkbox" name="partial_load" value="1"> Részrakomány / több stopos fuvar</label>
<button class="dispatchsend" type="submit">FUVAR KÜLDÉSE A FLOW-BA + PUSH →</button>
</form>
<p class="muted">Első küldéskor a rendszám automatikusan bekerül a Flow járművei közé. Ha az adott telefon már regisztrálta a rendszámot és az FCM tokent, a push azonnal megérkezik; visszaigazolásig a szerver ismételni tudja.</p></section>
<section class="panel"><div class="panelhead"><div><small>AKTÍV FLOW-FUVAROK • TÖRLÉS</small><h2>Aktív munkák</h2></div><span class="chip <?=$flowActiveJobs?'wait':'ok'?>"><?=$flowActiveJobs?> aktív</span></div>
<div class="table"><table><thead><tr><th>Fuvar</th><th>Jármű</th><th>Látta</th><th>Elfogadta</th><th>Frissült</th><th>Művelet</th></tr></thead><tbody>
<?php if(!$flowActiveJobRows):?><tr><td colspan="6" class="empty">Nincs aktív Flow-fuvar.</td></tr>
<?php else:foreach($flowActiveJobRows as $fj):?><tr>
<td><b><?=portal_h($fj['reference'])?></b><div class="muted">#<?=intval($fj['id'])?></div></td>
<td><b><?=portal_h(trim((string)$fj['label'])!==''?$fj['label']:$fj['plate'])?></b></td>
<td><?=$fj['driver_seen_at']?'<span class="chip ok">LÁTTA</span>':'<span class="chip wait">NEM LÁTTA</span>'?></td>
<td><?=$fj['driver_accepted_at']?'<span class="chip ok">ELFOGADTA</span>':'<span class="chip wait">NINCS ELFOGADVA</span>'?></td>
<td><?=portal_h($fj['updated_at'])?></td>
<td>
<?php $trackingActive=!empty($fj['customer_tracking_token_hash'])&&!empty($fj['customer_tracking_expires_at'])&&strtotime((string)$fj['customer_tracking_expires_at'])>time();$od=[];if(!empty($fj['order_payload_json'])){$tmp=json_decode((string)$fj['order_payload_json'],true);if(is_array($tmp))$od=$tmp;}$customerEmail=trim((string)($od['customer_email']??''));?>
<div class="actions">
<form method="post" action="aims-flow-customer-link.php"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="job_id" value="<?=intval($fj['id'])?>"><input type="hidden" name="action" value="create"><button class="map" type="submit"><?= $trackingActive?'LINK ÚJRAGENERÁLÁSA':'MEGBÍZÓI LINK' ?></button></form>
<?php if($customerEmail!==''):?><form method="post" action="aims-flow-customer-link.php"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="job_id" value="<?=intval($fj['id'])?>"><input type="hidden" name="action" value="create"><input type="hidden" name="send_email" value="1"><button class="approve" type="submit">LINK + E-MAIL</button></form><?php endif;?>
<?php if($trackingActive):?><form method="post" action="aims-flow-customer-link.php" onsubmit="return confirm('Biztosan visszavonod a megbízói követőlinket?');"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="job_id" value="<?=intval($fj['id'])?>"><input type="hidden" name="action" value="revoke"><button class="danger" type="submit">LINK VISSZAVONÁSA</button></form><?php endif;?>
<form method="post" action="aims-flow-job-delete.php" onsubmit="return confirm('Biztosan törlöd ezt a Flow-fuvart? A sofőr alkalmazásából eltűnik, az auditnyom megmarad.');"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="job_id" value="<?=intval($fj['id'])?>"><button class="danger" type="submit">TÖRLÉS</button></form>
</div>
<?php if($trackingActive):?><div class="muted" style="margin-top:6px">Megbízói link aktív: <?=portal_h($fj['customer_tracking_expires_at'])?></div><?php endif;?>
</td>
</tr><?php endforeach;endif;?></tbody></table></div>
<p class="muted">A törlés soft delete: a fuvar eltűnik a sofőr aktív munkái közül, de az audit és a korábbi adatok megmaradnak.</p></section>
<section class="panel"><div class="panelhead"><div><small>SOFŐR ↔ FŐNÖKSÉG • ÉLŐ ÜZENET</small><h2>Azonnali üzenetváltás</h2></div><span class="chip ok" id="flowMsgState">ÉLŐ</span></div>
<div class="dispatchgrid">
<label>Rendszám<select id="flowMsgPlate" style="width:100%;min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px">
<option value="">Összes jármű</option>
<?php foreach($flowDriverVehicles as $v):?><option value="<?=portal_h($v['plate'])?>"><?=portal_h($v['plate'])?></option><?php endforeach;?>
</select></label>
<label class="full">Üzenet a sofőrnek<textarea id="flowMsgText" rows="3" maxlength="1000" placeholder="Írd ide az üzenetet…" style="width:100%;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:12px;resize:vertical"></textarea></label>
<button class="dispatchsend" type="button" id="flowMsgSend">ÜZENET KÜLDÉSE + PUSH →</button>
</div>
<div id="flowMsgList" style="margin-top:14px;display:grid;gap:7px"><div class="empty">Üzenetek betöltése…</div></div>
<p class="muted">A sofőr üzenete az admin telefonjára pushként is megérkezik. Ha ez az oldal nyitva van, a beszélgetés automatikusan frissül. Az admin válasza pushként megy vissza a sofőr AIMS Flow appjába.</p></section>
<section class="panel" id="flow-operations"><div class="panelhead"><div><small>FLOW OFFICE • OPERATÍV KONTROLL</small><h2>Munkanap · Safety · Service Guard · járműhiba</h2></div><span class="chip ok">SOFŐR → IRODA</span></div>
<p class="muted">Ez a napi operatív FLOW felület. A sofőrapp munkanap-, kilométer-, Safety Check-, Service Guard- és hibajelzései ide érkeznek; ez nem AIMS CONTROL rendszeradmin.</p>
<div class="statusbar">
  <div class="metric"><small>Aktív munkanap</small><b><?=$flowOpenWorkdays?></b></div>
  <div class="metric"><small>Safety Check 24h</small><b><?=$flowSafety24?></b></div>
  <div class="metric"><small>Nyitott járműhiba</small><b><?=$flowOpenIssues?></b></div>
  <div class="metric"><small>Jármű HOLD</small><b><?=$flowHoldCount?></b></div>
</div></section>

<section class="panel"><div class="panelhead"><div><small>MUNKA / PIHENŐ • KM</small><h2>Sofőr munkanapok</h2></div><span class="chip <?=$flowOpenWorkdays?'wait':'ok'?>"><?=$flowOpenWorkdays?> aktív</span></div>
<div class="table"><table><thead><tr><th>Jármű</th><th>Fuvar</th><th>Kezdés</th><th>Vége</th><th>Munkaidő</th><th>Kezdő km</th><th>Záró km</th><th>Nap km</th><th>Állapot</th></tr></thead><tbody>
<?php if(!$flowWorkdayRows):?><tr><td colspan="9" class="empty">Még nincs rögzített FLOW munkanap.</td></tr>
<?php else:foreach($flowWorkdayRows as $wd):
$wdStart=strtotime((string)$wd['started_at']);$wdEnd=!empty($wd['finished_at'])?strtotime((string)$wd['finished_at']):time();$wdSec=($wdStart!==false&&$wdEnd!==false)?max(0,$wdEnd-$wdStart):0;$wdDur=sprintf('%02d:%02d',intdiv($wdSec,3600),intdiv($wdSec%3600,60));$wdKm=($wd['end_km']!==null)?((int)$wd['end_km']-(int)$wd['start_km']):null;?>
<tr>
<td><b><?=portal_h(trim((string)$wd['label'])!==''?$wd['label']:$wd['plate'])?></b><div class="muted"><?=portal_h($wd['plate'])?></div></td>
<td><?=portal_h($wd['reference']??'—')?></td>
<td><?=portal_h($wd['started_at'])?></td>
<td><?=portal_h($wd['finished_at']??'—')?></td>
<td><b><?=$wdDur?></b></td>
<td><?=number_format((int)$wd['start_km'],0,',',' ')?> km</td>
<td><?=$wd['end_km']!==null?number_format((int)$wd['end_km'],0,',',' ').' km':'—'?></td>
<td><?=$wdKm!==null?number_format($wdKm,0,',',' ').' km':'—'?></td>
<td><?=$wd['finished_at']?'<span class="chip ok">PIHENŐ / LEZÁRVA</span>':'<span class="chip wait">MUNKÁBAN</span>'?></td>
</tr><?php endforeach;endif;?></tbody></table></div></section>

<section class="panel"><div class="panelhead"><div><small>FLOW SAFETY • KÖTELEZŐ FOTÓK</small><h2>Járműellenőrzések</h2></div><span class="chip ok"><?=count($flowSafetyRows)?> rekord</span></div>
<div class="table"><table><thead><tr><th>Jármű</th><th>Idő</th><th>Km</th><th>Eredmény</th><th>Olaj</th><th>Hűtőfolyadék</th><th>Kerék</th><th>Km-fotó</th></tr></thead><tbody>
<?php if(!$flowSafetyRows):?><tr><td colspan="8" class="empty">Még nincs beérkezett Safety Check.</td></tr>
<?php else:foreach($flowSafetyRows as $sc):$scStatus=json_decode((string)$sc['statuses_json'],true);if(!is_array($scStatus))$scStatus=[];?>
<tr>
<td><b><?=portal_h(trim((string)$sc['label'])!==''?$sc['label']:$sc['plate'])?></b><div class="muted"><?=portal_h($sc['plate'])?></div></td>
<td><?=portal_h($sc['created_at'])?></td>
<td><?=number_format((int)$sc['km'],0,',',' ')?> km</td>
<td><?=!empty($sc['has_problem'])?'<span class="chip bad">PROBLÉMA</span>':'<span class="chip ok">RENDBEN</span>'?><div class="muted"><?=portal_h(implode(' · ',array_map(fn($k,$v)=>$k.':'.$v,array_keys($scStatus),array_values($scStatus))))?></div></td>
<?php foreach(['oil_photo_id','coolant_photo_id','tires_photo_id','odometer_photo_id'] as $photoKey):?>
<td><?php if(!empty($sc[$photoKey])):?><a class="btn" target="_blank" rel="noopener" href="aims-flow-safety-photo.php?id=<?=intval($sc[$photoKey])?>">FOTÓ ↗</a><?php else:?><span class="chip bad">HIÁNYZIK</span><?php endif;?></td>
<?php endforeach;?>
</tr><?php endforeach;endif;?></tbody></table></div>
<p class="muted">A fotók nem publikus fájllinkek: csak bejelentkezett admin tudja megnyitni őket.</p></section>

<section class="panel"><div class="panelhead"><div><small>SERVICE GUARD • KM / DÁTUM</small><h2>Szervizfigyelés</h2></div><span class="chip <?=count($flowServiceRows)?'wait':'ok'?>"><?=count($flowServiceRows)?> aktív tétel</span></div>
<div class="table"><table><thead><tr><th>Jármű</th><th>Tétel</th><th>Aktuális km</th><th>Esedékes km</th><th>Dátum</th><th>Állapot</th><th>Utolsó szerviz</th><th>Művelet</th></tr></thead><tbody>
<?php if(!$flowServiceRows):?><tr><td colspan="8" class="empty">Még nincs Service Guard tétel. Alul tudsz létrehozni.</td></tr>
<?php else:foreach($flowServiceRows as $svc):
$svcRemain=($svc['due_km']!==null&&$svc['current_km']!==null)?((int)$svc['due_km']-(int)$svc['current_km']):null;
$svcDateDays=null;if(!empty($svc['due_date'])){$ts=strtotime((string)$svc['due_date']);if($ts!==false)$svcDateDays=(int)floor(($ts-strtotime(gmdate('Y-m-d')))/86400);}
$svcBad=($svcRemain!==null&&$svcRemain<=0)||($svcDateDays!==null&&$svcDateDays<0);
$svcWait=!$svcBad&&(($svcRemain!==null&&$svcRemain<=(int)$svc['warning_km'])||($svcDateDays!==null&&$svcDateDays<=(int)$svc['warning_days']));
?>
<tr>
<td><b><?=portal_h($svc['plate'])?></b><?php if(!empty($svc['vehicle_hold'])):?><div><span class="chip bad">HOLD</span></div><?php endif;?></td>
<td><b><?=portal_h($svc['title'])?></b><div class="muted"><?=portal_h($svc['notes']??'')?></div></td>
<td><?=$svc['current_km']!==null?number_format((int)$svc['current_km'],0,',',' ').' km':'—'?></td>
<td><?=$svc['due_km']!==null?number_format((int)$svc['due_km'],0,',',' ').' km':'—'?><?php if($svcRemain!==null):?><div class="muted"><?=$svcRemain<0?number_format(abs($svcRemain),0,',',' ').' km túllépés':number_format($svcRemain,0,',',' ').' km maradt'?></div><?php endif;?></td>
<td><?=portal_h($svc['due_date']??'—')?></td>
<td><?=$svcBad?'<span class="chip bad">LEJÁRT</span>':($svcWait?'<span class="chip wait">KÖZELEG</span>':'<span class="chip ok">RENDBEN</span>')?></td>
<td><?=portal_h($svc['last_done_at']??'—')?><?php if($svc['last_done_km']!==null):?><div class="muted"><?=number_format((int)$svc['last_done_km'],0,',',' ')?> km</div><?php endif;?></td>
<td><form method="post" action="aims-flow-operations.php" class="actions"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="service_complete"><input type="hidden" name="service_id" value="<?=intval($svc['id'])?>"><input name="completed_km" inputmode="numeric" placeholder="km" style="width:92px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:8px;padding:7px"><button class="approve" type="submit">SZERVIZ KÉSZ</button></form></td>
</tr><?php endforeach;endif;?></tbody></table></div>

<form class="dispatchgrid" method="post" action="aims-flow-operations.php" style="margin-top:14px">
<input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="service_save">
<label>Jármű<select name="plate" required style="width:100%;min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px"><?php foreach($flowDriverVehicles as $v):if(empty($v['enabled']))continue;?><option value="<?=portal_h($v['plate'])?>"><?=portal_h($v['plate'])?></option><?php endforeach;?></select></label>
<label>Típus<select name="service_type" style="width:100%;min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px"><option value="oil">Olajcsere</option><option value="tires">Gumi / kerék</option><option value="brakes">Fék</option><option value="timing">Vezérlés</option><option value="inspection">Műszaki</option><option value="insurance">Biztosítás / assistance</option><option value="custom">Egyéb</option></select></label>
<label class="full">Tétel neve<input name="title" required placeholder="pl. Motorolaj + szűrő"></label>
<label>Esedékes km<input name="due_km" inputmode="numeric" placeholder="205000"></label>
<label>Esedékes dátum<input name="due_date" type="date"></label>
<label>Figyelmeztetés km-rel előtte<input name="warning_km" inputmode="numeric" value="2000"></label>
<label>Figyelmeztetés nappal előtte<input name="warning_days" inputmode="numeric" value="30"></label>
<label>Ismétlődés km<input name="interval_km" inputmode="numeric" placeholder="15000"></label>
<label>Ismétlődés nap<input name="interval_days" inputmode="numeric" placeholder="365"></label>
<label class="full">Megjegyzés<input name="notes" placeholder="pl. 5W-30, gyári szűrő"></label>
<button class="dispatchsend" type="submit">SERVICE GUARD TÉTEL MENTÉSE</button>
</form></section>

<section class="panel"><div class="panelhead"><div><small>JÁRMŰHIBA • HOLD</small><h2>Nyitott hibák és irodai feloldás</h2></div><span class="chip <?=$flowOpenIssues?'bad':'ok'?>"><?=$flowOpenIssues?> nyitott</span></div>
<div class="table"><table><thead><tr><th>Jármű</th><th>Hiba</th><th>Üzenet</th><th>Idő</th><th>Állapot</th><th>HOLD</th><th>Művelet</th></tr></thead><tbody>
<?php if(!$flowIssueRows):?><tr><td colspan="7" class="empty">Nincs járműhiba.</td></tr>
<?php else:foreach($flowIssueRows as $issue):?>
<tr>
<td><b><?=portal_h($issue['plate'])?></b></td>
<td><b><?=portal_h($issue['category'])?></b><?php if(!empty($issue['urgent'])):?><div><span class="chip bad">KRITIKUS</span></div><?php endif;?></td>
<td><?=portal_h($issue['message'])?></td>
<td><?=portal_h($issue['created_at'])?></td>
<td><?=$issue['status']==='open'?'<span class="chip bad">NYITOTT</span>':'<span class="chip ok">LEZÁRVA</span>'?></td>
<td><?=!empty($issue['vehicle_hold'])?'<span class="chip bad">HOLD</span>':'<span class="chip ok">MEHET</span>'?><?php if(!empty($issue['hold_reason'])):?><div class="muted"><?=portal_h($issue['hold_reason'])?></div><?php endif;?></td>
<td><?php if($issue['status']==='open'):?><form method="post" action="aims-flow-operations.php" style="display:grid;gap:6px;min-width:190px"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="issue_resolve"><input type="hidden" name="issue_id" value="<?=intval($issue['id'])?>"><input name="resolved_note" placeholder="Megoldás / megjegyzés" style="border:1px solid #333;background:#090b0d;color:#fff;border-radius:8px;padding:7px"><label class="muted"><input type="checkbox" name="release_hold" value="1"> HOLD feloldása, ha nincs más kritikus hiba</label><button class="btn gold" type="submit">HIBA LEZÁRÁSA</button></form><?php else:?><span class="muted"><?=portal_h($issue['resolved_note']??'')?></span><?php endif;?></td>
</tr><?php endforeach;endif;?></tbody></table></div>

<div class="dispatchgrid" style="margin-top:14px">
<form method="post" action="aims-flow-operations.php" style="display:grid;gap:8px"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="vehicle_hold"><select name="plate" required style="min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px"><?php foreach($flowDriverVehicles as $v):if(empty($v['enabled']))continue;?><option value="<?=portal_h($v['plate'])?>"><?=portal_h($v['plate'])?></option><?php endforeach;?></select><input name="hold_reason" required placeholder="HOLD oka" style="min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px"><button class="btn danger" type="submit">JÁRMŰ HOLD</button></form>
<form method="post" action="aims-flow-operations.php" style="display:grid;gap:8px"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="action" value="vehicle_release"><select name="plate" required style="min-height:45px;border:1px solid #333;background:#090b0d;color:#fff;border-radius:10px;padding:0 12px"><?php foreach($flowDriverVehicles as $v):if(empty($v['enabled']))continue;?><option value="<?=portal_h($v['plate'])?>"><?=portal_h($v['plate'])?></option><?php endforeach;?></select><div class="muted">Csak akkor oldd fel, ha a jármű biztonságosan használható.</div><button class="btn approve" type="submit">HOLD FELOLDÁSA</button></form>
</div></section>

<div class="statusbar"><div class="metric"><small>Aktív fuvar GPS</small><b id="mActive">—</b></div><div class="metric"><small>Aktív Flow-fuvar</small><b><?=$flowActiveJobs?></b></div><div class="metric"><small>Flow mobilok</small><b><?=$flowPhoneCount?></b></div><div class="metric"><small>CMR szinkron 24h</small><b id="mCmr">—</b></div></div>
<section class="panel"><div class="panelhead"><div><small>REGISTRATION POINT LEARNING</small><h2>Tanult regisztrációs GPS-pontok</h2></div><span class="chip ok"><?=count($flowRegistrationPoints)?> ismert pont</span></div>
<div class="table"><table><thead><tr><th>Cég</th><th>Típus</th><th>Cím</th><th>GPS</th><th>Megerősítés</th><th>Utolsó tanulás</th><th></th></tr></thead><tbody>
<?php if(!$flowRegistrationPoints):?><tr><td colspan="7" class="empty">Még nincs tanult regisztrációs pont. Az első sofőr regisztrációs gombnyomása automatikusan létrehozza.</td></tr>
<?php else:foreach($flowRegistrationPoints as $rp):?><tr>
<td><b><?=portal_h($rp['company_name']?:'Ismeretlen telephely')?></b></td>
<td><span class="chip <?=$rp['stop_type']==='pickup'?'ok':'wait'?>"><?=$rp['stop_type']==='pickup'?'FELRAKÓ':'LERAKÓ'?></span></td>
<td><?=portal_h($rp['address'])?></td>
<td class="mono"><?=number_format((float)$rp['latitude'],6,'.','')?>, <?=number_format((float)$rp['longitude'],6,'.','')?><?php if($rp['accuracy']!==null):?><div class="muted">±<?=number_format((float)$rp['accuracy'],0)?> m</div><?php endif;?></td>
<td><b><?=intval($rp['confirmations'])?>×</b></td>
<td><?=portal_h($rp['updated_at'])?></td>
<td><a class="btn" target="_blank" rel="noopener" href="https://www.google.com/maps?q=<?=rawurlencode($rp['latitude'].','.$rp['longitude'])?>">Térkép ↗</a></td>
</tr><?php endforeach;endif;?></tbody></table></div>
<p class="muted">A Flow a sofőr <b>BEJELENTKEZTEM A REGISZTRÁCIÓN</b> gombnyomásakor tanulja meg a pontot. Ugyanazon telephely következő fuvarjainál ezt a GPS-pontot ajánlja fel regisztrációs navigációként.</p></section>
<div class="live"><section class="panel"><div class="panelhead"><div><small>VALÓS GPS</small><h2>Aktív és friss fuvarok</h2></div><button class="btn gold" id="refreshBtn">Frissítés</button></div><div class="table"><table><thead><tr><th>Jármű</th><th>Státusz</th><th>Utolsó hely</th><th>Sebesség</th><th>Pontosság</th><th>Távolság</th><th>Pontok</th><th>Frissült</th><th></th></tr></thead><tbody id="trackingRows"><tr><td colspan="9" class="empty">Betöltés…</td></tr></tbody></table></div></section>
<section class="panel routebox"><div><small>ÚTVONAL-NÉZET</small><h2 id="routeTitle">Válassz járművet</h2></div><svg id="routeSvg" viewBox="0 0 600 230" preserveAspectRatio="none" aria-label="GPS útvonal"><text x="300" y="118" fill="#666" text-anchor="middle" font-size="13">Nincs kiválasztott útvonal</text></svg><div class="route-meta"><div><small>Koordináta</small><b id="rCoord">—</b></div><div><small>Sebesség</small><b id="rSpeed">—</b></div><div><small>Pontosság</small><b id="rAcc">—</b></div><div><small>GPS pont</small><b id="rPoints">—</b></div></div><div class="actions"><a id="mapLink" class="map" target="_blank" rel="noopener" href="#">Megnyitás Google Mapsen ↗</a></div></section></div>
<section class="panel"><div class="panelhead"><div><small>SOFŐR BELÉPÉS • RENDSZÁM + 6 KARAKTER</small><h2>Sofőr hozzáférések</h2></div></div><div class="table"><table><thead><tr><th>Rendszám</th><th>E-mail</th><th>Nyelv</th><th>Hozzáférés</th><th>Reset</th><th>Művelet</th></tr></thead><tbody><?php if(!$flowDriverVehicles):?><tr><td colspan="6" class="empty">Még nincs Flow-jármű. Appos regisztráció jóváhagyásakor automatikusan létrejön.</td></tr><?php else:foreach($flowDriverVehicles as $v):$hasCode=!empty($v['driver_code_hash']);$isTemp=!empty($v['driver_code_is_temp']);$resetPending=($v['driver_reset_status']??'')==='pending';?><tr><td><b><?=portal_h($v['plate'])?></b></td><td><?=portal_h($v['driver_email']??'—')?></td><td><span class="chip"><?=portal_h(strtoupper($v['driver_language']??'HU'))?></span></td><td><?php if(!$hasCode):?><span class="chip bad">NINCS KÓD</span><?php elseif($isTemp):?><span class="chip wait">TEMP</span><div class="muted"><?=portal_h($v['driver_code_expires_at']??'')?></div><?php else:?><span class="chip ok">AKTÍV</span><?php endif;?></td><td><?=$resetPending?'<span class="chip wait">JÓVÁHAGYÁSRA VÁR</span>':'<span class="chip">—</span>'?><?php if($resetPending):?><div class="muted"><?=portal_h($v['driver_reset_requested_at']??'')?></div><?php endif;?></td><td><form method="post" action="aims-flow-driver-auth.php"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="plate" value="<?=portal_h($v['plate'])?>"><input type="hidden" name="act" value="<?=$resetPending?'approve_reset':'issue_temp'?>"><button class="<?=$resetPending?'approve':''?>"><?=$resetPending?'RESET JÓVÁHAGYÁSA':'ÚJ TEMP KÓD'?></button></form></td></tr><?php endforeach;endif;?></tbody></table></div><p class="muted">A tényleges kód soha nem jelenik meg az adminban és nincs nyersen eltárolva. Jóváhagyás után e-mailben megy ki a regisztrált címre.</p></section>
<section class="panel"><div class="panelhead"><div><small>FLOW MOBILKAPCSOLAT • NINCS ESZKÖZ-JÓVÁHAGYÁS</small><h2>Pushra regisztrált telefonok</h2></div></div><div class="table"><table><thead><tr><th>Rendszám</th><th>Platform</th><th>Push</th><th>Utolsó regisztráció</th><th>Eszközazonosító</th></tr></thead><tbody><?php if(!$flowPhones):?><tr><td colspan="5" class="empty">Még nincs telefon regisztrálva. Telepítsd az új AIMS Flow APK-t, add meg a rendszámot, és a telefon automatikusan megjelenik itt.</td></tr><?php else:foreach($flowPhones as $p):?><tr><td><b><?=portal_h($p['plate'])?></b></td><td><?=portal_h($p['platform'])?></td><td><span class="chip <?=!empty($p['enabled'])?'ok':'bad'?>"><?=!empty($p['enabled'])?'AKTÍV':'LETILTVA'?></span></td><td><?=portal_h($p['updated_at'])?></td><td class="mono"><?=portal_h(substr((string)$p['device_id'],0,32))?></td></tr><?php endforeach;endif;?></tbody></table></div></section>
<section class="panel"><div class="panelhead"><div><small>SMART SCANNER</small><h2>Legutóbbi CMR szinkronok</h2></div></div><div class="table"><table><thead><tr><th>CMR</th><th>Jármű</th><th>Állapot</th><th>Idő</th><th>GPS-bélyeg</th><th>Minőség</th><th>Művelet</th></tr></thead><tbody id="cmrRows"><tr><td colspan="7" class="empty">Betöltés…</td></tr></tbody></table></div></section>
</div><script>
const CSRF=<?=json_encode($csrf,JSON_UNESCAPED_SLASHES)?>;let vehicles=[],devices=[],documents=[],selectedTrip='',resetSignature=<?=json_encode($flowResetSignature,JSON_UNESCAPED_SLASHES)?>;let flowMessages=[];const $=id=>document.getElementById(id);const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function flowMessageApi(opt={}){const plate=$('flowMsgPlate')?.value||'';const qs=plate?'?plate='+encodeURIComponent(plate):'';const o={credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json',...(opt.headers||{})},...opt};if(o.method&&o.method!=='GET'){o.headers['Content-Type']='application/json';o.headers['X-AIMS-CSRF']=CSRF}const r=await fetch('aims-flow-messages.php'+qs,o);let j={};try{j=await r.json()}catch(e){}if(!r.ok)throw new Error(j.error||('HTTP '+r.status));return j}
function renderFlowMessages(){const box=$('flowMsgList');if(!box)return;const plate=$('flowMsgPlate')?.value||'';const rows=flowMessages.filter(m=>!plate||String(m.plate||'')===plate);if(!rows.length){box.innerHTML='<div class="empty">Még nincs üzenetváltás.</div>';return}box.innerHTML=rows.slice(-60).map(m=>{const driver=m.sender==='driver';return '<div style="display:flex;justify-content:'+(driver?'flex-start':'flex-end')+'"><div style="max-width:min(720px,88%);border:1px solid '+(driver?'#31526a':'#5b4e29')+';background:'+(driver?'#0d1720':'#17140d')+';border-radius:12px;padding:9px 11px"><div style="font-size:9px;font-weight:900;color:'+(driver?'#a8d4ff':'#f2d77f')+'">'+esc(m.label||m.plate||'')+' · '+(driver?'SOFŐR':'FŐNÖKSÉG')+' · '+dt(m.createdAt)+'</div><div style="margin-top:4px;white-space:pre-wrap">'+esc(m.body||'')+'</div></div></div>'}).join('')}
async function refreshFlowMessages(){const state=$('flowMsgState');try{const j=await flowMessageApi();flowMessages=Array.isArray(j.messages)?j.messages:[];renderFlowMessages();if(state){state.textContent='ÉLŐ';state.className='chip ok'}}catch(e){if(state){state.textContent='HIBA';state.className='chip bad'}}}
async function sendFlowMessage(){const plate=$('flowMsgPlate')?.value||'',text=$('flowMsgText')?.value.trim()||'';if(!plate){alert('Válassz rendszámot.');return}if(!text)return;const b=$('flowMsgSend');b.disabled=true;try{await flowMessageApi({method:'POST',body:JSON.stringify({plate,message:text})});$('flowMsgText').value='';await refreshFlowMessages()}catch(e){alert('Az üzenet nem ment el: '+e.message)}finally{b.disabled=false}}
async function pollDriverResets(){try{const r=await fetch('aims-flow-reset-poll.php',{credentials:'same-origin',cache:'no-store'});if(!r.ok)return;const j=await r.json();if(!j||j.ok!==true||!j.signature)return;if(resetSignature===null){resetSignature=j.signature;return}if(j.signature===resetSignature)return;const tag=(document.activeElement?.tagName||'').toLowerCase();if(['input','textarea','select'].includes(tag))return;location.reload()}catch(e){}}
function dt(v){if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleString('hu-HU',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'});}function kmh(v){return Math.max(0,Number(v||0)*3.6).toFixed(0)+' km/h'}
async function api(path,opt={}){const o={credentials:'same-origin',headers:{'Accept':'application/json',...(opt.headers||{})},...opt};if(o.method&&o.method!=='GET')o.headers['X-AIMS-CSRF']=CSRF;if(o.body&&!o.headers['Content-Type'])o.headers['Content-Type']='application/json';const r=await fetch('../api'+path,o);let j={};try{j=await r.json()}catch(e){}if(r.status===401){location.href='index.php?session=expired';throw new Error('admin_auth_required')}if(!r.ok)throw new Error(j.error||('HTTP '+r.status));return j}
function chip(state){const s=String(state||'').toLowerCase();const c=s==='approved'||s==='emailed'||s==='uploaded'?'ok':s==='revoked'||s==='failed'?'bad':'wait';return `<span class="chip ${c}">${esc(s||'—')}</span>`}
function renderTracking(){const body=$('trackingRows');$('mActive').textContent=vehicles.filter(v=>v.active).length;if(!vehicles.length){body.innerHTML='<tr><td colspan="9" class="empty">Még nincs beérkezett GPS-adat.</td></tr>';drawRoute(null);return}body.innerHTML=vehicles.map(v=>{const p=v.latest||{};const mock=p.isMocked?' ⚠ MOCK':'';return `<tr><td><b>${esc(v.plate||'—')}</b><div class="muted">${esc(v.reference||v.tripId||'')}</div></td><td>${v.active?'<span class="chip ok">ÉLŐ</span>':'<span class="chip wait">LEZÁRVA</span>'}${mock?'<div class="muted" style="color:#ff9e9e">'+mock+'</div>':''}</td><td class="mono">${Number(p.latitude||0).toFixed(6)}, ${Number(p.longitude||0).toFixed(6)}</td><td>${kmh(p.speedMps)}</td><td>±${Number(p.accuracy||0).toFixed(0)} m</td><td>${Number(v.distanceKm||0).toFixed(2)} km</td><td>${Number(v.pointCount||0)}</td><td>${dt(v.updatedAt)}</td><td><div class="actions"><button onclick="selectTrip('${esc(v.tripId)}')">Útvonal</button><a class="map" target="_blank" rel="noopener" href="https://www.google.com/maps?q=${encodeURIComponent(p.latitude+','+p.longitude)}">Térkép ↗</a></div></td></tr>`}).join('');if(!selectedTrip||!vehicles.some(v=>v.tripId===selectedTrip))selectedTrip=vehicles[0].tripId;drawRoute(vehicles.find(v=>v.tripId===selectedTrip))}
function selectTrip(id){selectedTrip=id;drawRoute(vehicles.find(v=>v.tripId===id))}
function drawRoute(v){const svg=$('routeSvg');if(!v||!v.latest){$('routeTitle').textContent='Válassz járművet';svg.innerHTML='<text x="300" y="118" fill="#666" text-anchor="middle" font-size="13">Nincs kiválasztott útvonal</text>';return}const pts=(v.recentPoints||[]).filter(p=>Number.isFinite(Number(p.latitude))&&Number.isFinite(Number(p.longitude)));$('routeTitle').textContent=(v.plate||'Jármű')+' • '+(v.active?'ÉLŐ GPS':'lezárt fuvar');$('rCoord').textContent=Number(v.latest.latitude).toFixed(6)+', '+Number(v.latest.longitude).toFixed(6);$('rSpeed').textContent=kmh(v.latest.speedMps);$('rAcc').textContent='±'+Number(v.latest.accuracy||0).toFixed(0)+' m';$('rPoints').textContent=(v.pointCount||0)+' pont';$('mapLink').href='https://www.google.com/maps?q='+encodeURIComponent(v.latest.latitude+','+v.latest.longitude);if(pts.length<2){svg.innerHTML='<circle cx="300" cy="115" r="7" fill="#f2d77f"/><text x="300" y="145" fill="#777" text-anchor="middle" font-size="12">1 GPS pont érkezett</text>';return}const lats=pts.map(p=>+p.latitude),lngs=pts.map(p=>+p.longitude);let minLa=Math.min(...lats),maxLa=Math.max(...lats),minLo=Math.min(...lngs),maxLo=Math.max(...lngs);if(maxLa===minLa){maxLa+=.0001;minLa-=.0001}if(maxLo===minLo){maxLo+=.0001;minLo-=.0001}const xy=pts.map(p=>[24+((+p.longitude-minLo)/(maxLo-minLo))*552,206-((+p.latitude-minLa)/(maxLa-minLa))*182]);const d=xy.map((q,i)=>(i?'L':'M')+q[0].toFixed(1)+' '+q[1].toFixed(1)).join(' ');const a=xy[0],b=xy[xy.length-1];svg.innerHTML=`<path d="${d}" fill="none" stroke="#d9ad4e" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${a[0]}" cy="${a[1]}" r="6" fill="#62dda0"/><circle cx="${b[0]}" cy="${b[1]}" r="7" fill="#f2d77f"/><text x="18" y="20" fill="#6f7780" font-size="10">UTOLSÓ ${pts.length} GPS PONT • sematikus útvonal</text>`}
function renderCmr(){const b=$('cmrRows'),now=Date.now();$('mCmr').textContent=documents.filter(d=>{const t=new Date(d.received_at||d.created_at).getTime();return Number.isFinite(t)&&t>now-86400000}).length;if(!documents.length){b.innerHTML='<tr><td colspan="7" class="empty">Még nincs szinkronizált CMR.</td></tr>';return}b.innerHTML=documents.map(d=>{const c=d.cmr||{},loc=d.location||{};const hasLoc=Number.isFinite(Number(loc.latitude))&&Number.isFinite(Number(loc.longitude));return `<tr><td><b>${esc(c.cmrNumber||'—')}</b><div class="muted">${esc(c.consignee||c.deliveryPlace||'')}</div></td><td><b>${esc(c.plate||'—')}</b></td><td>${chip(d.state)}</td><td>${dt(d.received_at||d.created_at)}</td><td>${hasLoc?`<a class="mono" target="_blank" rel="noopener" href="https://www.google.com/maps?q=${encodeURIComponent(loc.latitude+','+loc.longitude)}">${Number(loc.latitude).toFixed(5)}, ${Number(loc.longitude).toFixed(5)} ↗</a>`:'<span class="muted">nincs</span>'}</td><td>${d.quality_score==null?'—':esc(d.quality_score)+'/100'}</td><td><div class="actions">${d.email_error?`<button onclick="cmrAction('${esc(d.id)}','retry-email')">E-mail újra</button>`:''}${d.emailed_at&&!d.approved_at?`<button class="approve" onclick="cmrAction('${esc(d.id)}','approve')">Jóváhagyás</button>`:''}</div></td></tr>`}).join('')}
async function cmrAction(id,act){await api('/admin/cmr/'+encodeURIComponent(id)+'/'+act,{method:'POST',body:'{}'});await refreshAll()}
async function refreshAll(){const n=$('apiNotice');$('refreshBtn').innerHTML='<span class="spin"></span> Frissítés';try{const [t,c]=await Promise.all([api('/admin/tracking/live'),api('/admin/cmr?limit=80')]);vehicles=Array.isArray(t.vehicles)?t.vehicles:[];documents=Array.isArray(c.documents)?c.documents:[];renderTracking();renderCmr();n.className='notice';n.innerHTML='A modul a telefonról beérkező <b>valós GPS-pontokat</b>, Flow-fuvarokat és Scanner-adatokat kezeli. Nincs demo/szimulált járműmozgás.'}catch(e){n.className='notice error';n.textContent='A Flow API nem érhető el: '+e.message}finally{$('refreshBtn').textContent='Frissítés'}}
$('refreshBtn').addEventListener('click',refreshAll);refreshAll();setInterval(refreshAll,15000);pollDriverResets();setInterval(pollDriverResets,5000);if($('flowMsgSend'))$('flowMsgSend').addEventListener('click',sendFlowMessage);if($('flowMsgPlate'))$('flowMsgPlate').addEventListener('change',refreshFlowMessages);refreshFlowMessages();setInterval(refreshFlowMessages,3000);
</script></body></html>