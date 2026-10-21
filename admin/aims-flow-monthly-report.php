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
require_once $trackingRoot.'/monthly_report_lib.php';

$pdo=aims_db();
$tz=new DateTimeZone('Europe/Budapest');
$defaultMonth=(new DateTimeImmutable('first day of last month',$tz))->format('Y-m');
$month=trim((string)($_REQUEST['month']??$defaultMonth));
try{
  aims_monthly_period($month);
}catch(Throwable){
  $month=$defaultMonth;
}

$report=aims_monthly_build_report($pdo,$month);
$csrf=aims_admin_csrf();
$flash=null;

if(($_SERVER['REQUEST_METHOD']??'GET')==='POST'){
  $provided=trim((string)($_POST['csrf']??''));
  if($provided===''||!hash_equals($csrf,$provided)){
    http_response_code(403);exit('CSRF');
  }
  $recipient=trim((string)(getenv('AIMS_MONTHLY_REPORT_EMAIL')?:'office@logistic-aims.hu'));
  $reportLock=null;
  try{
    $reportLock=aims_monthly_acquire_lock($month);
    $paths=aims_monthly_store_report($report);
    $sent=aims_monthly_send_mail($report,$paths,$recipient);
    if($sent){
      $sentAt=gmdate(DateTimeInterface::ATOM);
      aims_monthly_record_run($pdo,$month,$recipient,'sent','A levelezőszerver küldésre átvette a riportot.',$paths,$sentAt);
      $flash=['ok'=>true,'message'=>'A havi riport átadva a levelezőszervernek, címzett: '.$recipient];
    }else{
      aims_monthly_record_run($pdo,$month,$recipient,'mail_failed','A levelezőszerver nem fogadta el küldésre a riportot.',$paths);
      $flash=['ok'=>false,'message'=>'A riport elkészült, de az e-mail-küldés nem igazolható.'];
    }
  }catch(Throwable $error){
    $flash=['ok'=>false,'message'=>'Riportküldési hiba: '.$error->getMessage()];
  }finally{
    if(is_resource($reportLock)){flock($reportLock,LOCK_UN);fclose($reportLock);}
  }
}

$download=trim((string)($_GET['download']??''));
if($download!==''){
  $filename='';$content='';
  if($download==='country'){
    $filename='AIMS-FLOW-orszagido-'.$month.'.csv';
    $content=aims_monthly_country_csv($report);
  }elseif($download==='attendance'){
    $filename='AIMS-FLOW-jelenleti-iv-'.$month.'.csv';
    $content=aims_monthly_attendance_csv($report);
  }elseif($download==='summary'){
    $filename='AIMS-FLOW-jelenleti-osszesito-'.$month.'.csv';
    $content=aims_monthly_attendance_summary_csv($report);
  }elseif(str_starts_with($download,'plate:')){
    $plate=aims_normalize_plate(substr($download,6));
    if($plate!==''){
      $filename='AIMS-FLOW-orszagido-'.$plate.'-'.$month.'.csv';
      $content=aims_monthly_country_csv($report,$plate);
    }
  }
  if($filename!==''&&$content!==''){
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="'.$filename.'"');
    header('Cache-Control: private, no-store');
    echo $content;exit;
  }
}

$run=aims_monthly_run_state($pdo,$month);
$vehicles=[];$countrySeconds=0;
foreach($report['countryRows'] as $row){
  $vehicles[$row['plate']]=true;
  $countrySeconds+=(int)$row['seconds'];
}
$driverCount=count($report['attendanceSummary']);
$countryCount=count(array_unique(array_map(static fn($row)=>$row['countryCode'],$report['countryRows'])));
$totalDuration=aims_monthly_duration_parts($countrySeconds);
$names=aims_monthly_country_names();
?>
<!doctype html><html lang="hu"><head><meta charset="utf-8">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIMS FLOW • Havi ország- és jelenléti riport</title>
<style>
:root{--bg:#090b0d;--panel:#111417;--line:#2a3036;--text:#f4f6f8;--muted:#89939c;--blue:#1478ff;--green:#3ddc97;--warn:#f0b957;--bad:#ff7078}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px Arial,sans-serif}a{color:inherit;text-decoration:none}.wrap{width:min(1440px,calc(100% - 28px));margin:auto;padding:24px 0 70px}.head{display:flex;justify-content:space-between;gap:16px;align-items:center;flex-wrap:wrap}.ey{font-size:9px;letter-spacing:.14em;color:#7f8b95;text-transform:uppercase}.head h1{margin:5px 0 0;font-size:28px}.actions{display:flex;gap:8px;flex-wrap:wrap}.btn,button{border:1px solid var(--line);background:#171b1f;color:#fff;padding:10px 13px;border-radius:10px;font-weight:900;cursor:pointer}.btn.primary,button.primary{background:var(--blue);border-color:var(--blue)}.panel,.metric{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:16px}.filter{display:grid;grid-template-columns:minmax(180px,260px) auto 1fr;gap:10px;align-items:end;margin-top:18px}.filter label{display:grid;gap:6px;color:var(--muted);font-size:10px;font-weight:900;text-transform:uppercase}.filter input{height:44px;border:1px solid var(--line);background:#090b0d;color:#fff;border-radius:10px;padding:0 12px}.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:12px 0}.metric small{display:block;color:var(--muted);font-size:9px;text-transform:uppercase;letter-spacing:.08em}.metric b{display:block;font-size:24px;margin-top:7px}.notice{padding:12px 14px;border:1px solid;border-radius:12px;margin-top:12px}.notice.ok{background:#0e251b;border-color:#2b684c}.notice.bad{background:#2b1114;border-color:#783139}.section-head{display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap;margin:22px 0 8px}.section-head h2{margin:0}.table{overflow:auto;border:1px solid var(--line);border-radius:12px}table{width:100%;border-collapse:collapse;min-width:980px}th,td{text-align:left;padding:10px;border-bottom:1px solid #262b30;vertical-align:top}th{font-size:9px;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}.chip{display:inline-block;border:1px solid #3b444d;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900}.chip.ok{color:var(--green)}.chip.warn{color:var(--warn)}.chip.bad{color:var(--bad)}.muted{color:var(--muted);font-size:11px}.mono{font-family:ui-monospace,Consolas,monospace}@media(max-width:900px){.metrics{grid-template-columns:1fr 1fr}.filter{grid-template-columns:1fr}}@media(max-width:520px){.metrics{grid-template-columns:1fr}.wrap{width:min(100% - 18px,1440px)}}
</style></head><body><div class="wrap">
<div class="head"><div><div class="ey">AIMS FLOW • AUTOMATIKUS HAVI KONTROLL</div><h1>Országidő és jelenléti ív</h1></div><div class="actions"><a class="btn primary" href="aims-flow-eco.php">ECO MÓD</a><a class="btn" href="foreign-stay-report.php">Határnapló</a><a class="btn" href="aims-flow.php">← FLOW ADMIN</a></div></div>

<form class="panel filter" method="get">
<label>Riport hónapja<input type="month" name="month" value="<?=portal_h($month)?>"></label>
<button class="primary" type="submit">HÓNAP BETÖLTÉSE</button>
<div class="actions"><a class="btn" href="?month=<?=urlencode($month)?>&download=country">ORSZÁGIDŐ CSV</a><a class="btn" href="?month=<?=urlencode($month)?>&download=attendance">JELENLÉTI ÍV CSV</a><a class="btn" href="?month=<?=urlencode($month)?>&download=summary">SOFŐR ÖSSZESÍTŐ CSV</a></div>
</form>

<?php if($flash):?><div class="notice <?=$flash['ok']?'ok':'bad'?>"><?=portal_h($flash['message'])?></div><?php endif;?>

<div class="metrics">
<div class="metric"><small>Rendszám</small><b><?=count($vehicles)?></b></div>
<div class="metric"><small>Sofőr</small><b><?=$driverCount?></b></div>
<div class="metric"><small>Érintett ország</small><b><?=$countryCount?></b></div>
<div class="metric"><small>Összes országidő</small><b><?=portal_h($totalDuration['formatted'])?></b></div>
</div>

<section class="panel">
<div class="section-head"><div><h2>Automatikus e-mail</h2><div class="muted">Címzett: <?=portal_h((string)(getenv('AIMS_MONTHLY_REPORT_EMAIL')?:'office@logistic-aims.hu'))?></div></div>
<form method="post"><input type="hidden" name="csrf" value="<?=portal_h($csrf)?>"><input type="hidden" name="month" value="<?=portal_h($month)?>"><button class="primary" type="submit">E-MAIL KÜLDÉSE / ÚJRAKÜLDÉSE</button></form></div>
<?php if($run):?><div class="muted">Utolsó állapot: <b><?=portal_h((string)$run['status'])?></b> · <?=portal_h((string)($run['sent_at']?:$run['generated_at']))?> · <?=portal_h((string)($run['detail']??''))?></div><?php else:?><div class="muted">Ehhez a hónaphoz még nincs rögzített automatikus küldés.</div><?php endif;?>
</section>

<div class="section-head"><h2>Rendszámonkénti országidő</h2><div class="muted">A határátlépés csak 5 km új országbeli mozgás után válik véglegessé.</div></div>
<div class="table"><table><thead><tr><th>Rendszám</th><th>Ország</th><th>Nap</th><th>Óra</th><th>Perc</th><th>Összesen</th><th>Letöltés</th></tr></thead><tbody>
<?php if(!$report['countryRows']):?><tr><td colspan="7" class="muted">Nincs országidő-adat ebben a hónapban.</td></tr><?php else:foreach($report['countryRows'] as $row):$d=$row['duration'];?>
<tr><td><b><?=portal_h($row['plate'])?></b></td><td><?=portal_h($row['countryName'])?> <span class="muted">(<?=portal_h($row['countryCode'])?>)</span></td><td><?=$d['days']?></td><td><?=$d['hours']?></td><td><?=$d['minutes']?></td><td><b><?=portal_h($d['formatted'])?></b></td><td><a class="btn" href="?month=<?=urlencode($month)?>&download=plate:<?=urlencode($row['plate'])?>">CSV</a></td></tr>
<?php endforeach;endif;?></tbody></table></div>

<div class="section-head"><h2>Sofőr havi jelenléti összesítő</h2><div class="muted">A nettó FLOW-idő a rögzített pihenő levonása utáni idő. A korábbi hiányzó pihenő és a nyitott munkanap külön jelölést kap.</div></div>
<div class="table"><table><thead><tr><th>FLOW ID</th><th>Sofőr</th><th>Rendszám</th><th>Munkanap</th><th>Bruttó</th><th>Rögzített pihenő</th><th>Nettó FLOW-idő</th><th>Havi norma</th><th>Eltérés</th><th>Max. hét</th><th>4 havi átlag</th><th>Állapot</th></tr></thead><tbody>
<?php if(!$report['attendanceSummary']):?><tr><td colspan="12" class="muted">Nincs rögzített munkanap ebben a hónapban.</td></tr><?php else:foreach($report['attendanceSummary'] as $row):
$status=(string)$row['status'];$class=str_contains($status,'KRITIKUS')?'bad':(($row['incompleteRest']||$row['openWorkday']||str_contains($status,'FELETT'))?'warn':'ok');?>
<tr><td class="mono"><?=portal_h($row['flowId']?:'—')?></td><td><b><?=portal_h($row['driverName'])?></b><div class="muted"><?=portal_h($row['email'])?></div></td><td><?=portal_h($row['plates'])?></td><td><?=$row['days']?></td><td><?=portal_h($row['grossDuration']['hhmm'])?></td><td><?=portal_h($row['restDuration']['hhmm'])?></td><td><b><?=portal_h($row['duration']['hhmm'])?></b></td><td><?=number_format((float)$row['normHours'],2,',','')?> óra</td><td><?=number_format((float)$row['differenceHours'],2,',','')?> óra</td><td><?=number_format((float)$row['maxWeeklyHours'],2,',','')?> óra</td><td><?=$row['average4MonthWeeklyHours']===null?'—':number_format((float)$row['average4MonthWeeklyHours'],2,',','').' óra/hét'?></td><td><span class="chip <?=$class?>"><?=portal_h($status)?></span></td></tr>
<?php endforeach;endif;?></tbody></table></div>

<div class="section-head"><h2>Napi jelenléti bontás</h2><div class="muted">Az átfedő munkanapokat egyszer számítjuk; a járműváltás nem növeli a munkanapok számát.</div></div>
<div class="table"><table><thead><tr><th>Dátum</th><th>Sofőr</th><th>Rendszám</th><th>Kezdés</th><th>Vége</th><th>Bruttó</th><th>Rögzített pihenő</th><th>Nettó FLOW-idő</th><th>Állapot</th></tr></thead><tbody>
<?php if(!$report['attendanceRows']):?><tr><td colspan="9">Nincs rögzített munkanap.</td></tr><?php else:foreach($report['attendanceRows'] as $row):?>
<tr><td><?=portal_h($row['date'])?></td><td><?=portal_h($row['driverName'])?></td><td><?=portal_h($row['plate'])?></td><td><?=portal_h($row['firstStart']->format('H:i'))?></td><td><?=portal_h($row['lastEnd']->format('H:i'))?></td><td><?=portal_h($row['grossDuration']['hhmm'])?></td><td><?=portal_h($row['restDuration']['hhmm'])?></td><td><b><?=portal_h($row['duration']['hhmm'])?></b></td><td><?=portal_h($row['dailyStatus'])?></td></tr>
<?php endforeach;endif;?></tbody></table></div>

<p class="muted" style="margin-top:14px">A rendszer a közúti munkavállalóknál figyeli a heti 60 órás ellenőrzési küszöböt és a négyhavi, heti 48 órás átlagot. Az eredmény irodai kontrolljelzés, nem automatikus bérszámfejtési vagy jogi döntés.</p>
</div></body></html>

