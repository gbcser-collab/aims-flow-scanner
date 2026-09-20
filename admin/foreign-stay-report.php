<?php
require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

$pdo=aims_db();
$tz=new DateTimeZone('Europe/Budapest');
$utc=new DateTimeZone('UTC');
$home=strtoupper(trim((string)(getenv('AIMS_HOME_COUNTRY')?:'HU')));
if(!preg_match('/^[A-Z]{2}$/',$home))$home='HU';

$today=new DateTimeImmutable('now',$tz);
$defaultFrom=$today->modify('first day of this month')->format('Y-m-d');
$defaultTo=$today->format('Y-m-d');
$fromRaw=trim((string)($_GET['from']??$defaultFrom));
$toRaw=trim((string)($_GET['to']??$defaultTo));
$plateRaw=trim((string)($_GET['plate']??''));

function flow_report_date(string $value,string $fallback,DateTimeZone $tz):DateTimeImmutable{
    $d=DateTimeImmutable::createFromFormat('!Y-m-d',$value,$tz);
    return $d?:new DateTimeImmutable($fallback.' 00:00:00',$tz);
}
function flow_duration(int $seconds):string{
    $seconds=max(0,$seconds);
    $days=intdiv($seconds,86400);$seconds%=86400;
    $hours=intdiv($seconds,3600);$seconds%=3600;
    $minutes=intdiv($seconds,60);
    $parts=[];
    if($days)$parts[]=$days.' nap';
    if($hours||$days)$parts[]=$hours.' óra';
    $parts[]=$minutes.' perc';
    return implode(' ',$parts);
}

$fromLocal=flow_report_date($fromRaw,$defaultFrom,$tz);
$toLocal=flow_report_date($toRaw,$defaultTo,$tz)->modify('+1 day');
if($toLocal<=$fromLocal){$toLocal=$fromLocal->modify('+1 day');}
$fromUtc=$fromLocal->setTimezone($utc);
$toUtc=$toLocal->setTimezone($utc);
$nowUtc=new DateTimeImmutable('now',$utc);
$rangeEnd=$toUtc<$nowUtc?$toUtc:$nowUtc;
$plate=aims_normalize_plate($plateRaw);

$vehicles=$pdo->query('SELECT id,plate,label FROM vehicles WHERE enabled=1 ORDER BY plate')->fetchAll(PDO::FETCH_ASSOC);
$sql='SELECT s.*,v.plate,v.label FROM country_stays s JOIN vehicles v ON v.id=s.vehicle_id
      WHERE s.entered_at < :end AND COALESCE(s.exited_at,:end) > :start';
$params=[':start'=>$fromUtc->format(DateTimeInterface::ATOM),':end'=>$toUtc->format(DateTimeInterface::ATOM)];
if($plate!==''){
    $sql.=' AND v.plate=:plate';
    $params[':plate']=$plate;
}
$sql.=' ORDER BY s.entered_at ASC,s.id ASC';
$stmt=$pdo->prepare($sql);$stmt->execute($params);
$rawRows=$stmt->fetchAll(PDO::FETCH_ASSOC);

$names=[
'HU'=>'Magyarország','SK'=>'Szlovákia','AT'=>'Ausztria','DE'=>'Németország',
'PL'=>'Lengyelország','CZ'=>'Csehország','SI'=>'Szlovénia','HR'=>'Horvátország',
'RO'=>'Románia','RS'=>'Szerbia','UA'=>'Ukrajna','LT'=>'Litvánia','LV'=>'Lettország',
'EE'=>'Észtország','IT'=>'Olaszország','FR'=>'Franciaország','NL'=>'Hollandia',
'BE'=>'Belgium','LU'=>'Luxemburg','CH'=>'Svájc','ES'=>'Spanyolország',
'PT'=>'Portugália','DK'=>'Dánia','SE'=>'Svédország','NO'=>'Norvégia',
'FI'=>'Finnország','BG'=>'Bulgária','GR'=>'Görögország'
];

$rows=[];$foreignTotal=0;$byCountry=[];
foreach($rawRows as $row){
    try{$entered=new DateTimeImmutable((string)$row['entered_at']);}catch(Throwable){continue;}
    $exited=null;
    if(!empty($row['exited_at'])){try{$exited=new DateTimeImmutable((string)$row['exited_at']);}catch(Throwable){}}
    $start=$entered>$fromUtc?$entered:$fromUtc;
    $end=$exited??$rangeEnd;
    if($end>$rangeEnd)$end=$rangeEnd;
    if($end<=$start)continue;
    $seconds=$end->getTimestamp()-$start->getTimestamp();
    $country=strtoupper((string)$row['country_code']);
    $isForeign=$country!==$home;
    if($isForeign){
        $foreignTotal+=$seconds;
        $byCountry[$country]=($byCountry[$country]??0)+$seconds;
    }
    $row['_start']=$start;$row['_end']=$end;$row['_seconds']=$seconds;
    $row['_foreign']=$isForeign;$rows[]=$row;
}
arsort($byCountry);

function country_label(string $code,array $names):string{
    return ($names[$code]??$code).' ('.$code.')';
}
?><!doctype html><html lang="hu"><head><meta charset="utf-8">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIMS Flow • Külföldi tartózkodás</title>
<style>
:root{--g:#d9ad4e;--g2:#f2d77f;--bg:#08090b;--card:#0d0f11;--line:#29261f;--muted:#858078;--ok:#62dda0;--bad:#ff7d85}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#eee;font:14px Arial,sans-serif}
a{color:inherit;text-decoration:none}.wrap{width:min(1360px,calc(100% - 28px));margin:auto;padding:26px 0 70px}
.head{display:flex;justify-content:space-between;gap:14px;align-items:center;flex-wrap:wrap}.ey{font-size:9px;letter-spacing:.14em;color:#8c7a4d;text-transform:uppercase}
h1{margin:5px 0 0;font-size:28px}h1 span{color:var(--g2)}.btn{border:1px solid var(--line);padding:10px 13px;background:#0c0e10;color:#eee;font-weight:800;cursor:pointer}
.btn.gold{border:0;background:linear-gradient(135deg,#f1d77e,#b9852d);color:#090909}.panel,.metric{border:1px solid var(--line);background:linear-gradient(180deg,#0f1113,#0a0b0d);padding:16px}
.filter{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-top:18px}.filter label{display:grid;gap:6px;font-size:10px;color:#aaa;font-weight:800}
.filter input,.filter select{min-height:44px;background:#090b0d;color:#fff;border:1px solid #333;padding:0 11px}
.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:12px 0}.metric small{font-size:8px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}
.metric b{display:block;font-size:25px;color:var(--g2);margin-top:7px}.table{overflow:auto;border:1px solid #1e2022;margin-top:12px}
table{width:100%;border-collapse:collapse;min-width:950px}th,td{text-align:left;padding:11px;border-bottom:1px solid #1d1f21;vertical-align:top}
th{color:#827d72;font-size:8px;text-transform:uppercase;letter-spacing:.11em}.chip{display:inline-block;padding:5px 8px;border:1px solid #333;font-size:8px;font-weight:900}
.chip.foreign{color:var(--g2);border-color:#66562c}.chip.home{color:var(--ok);border-color:#28563e}.muted{color:#777;font-size:11px}.mono{font:11px ui-monospace,Consolas,monospace}
@media(max-width:900px){.filter{grid-template-columns:1fr 1fr}.metrics{grid-template-columns:1fr}}@media(max-width:520px){.filter{grid-template-columns:1fr}}
</style></head><body><div class="wrap">
<div class="head"><div><div class="ey">AIMS FLOW • RIPORT LEKÉRÉSE</div><h1>Külföldi <span>tartózkodás</span></h1></div>
<a class="btn" href="aims-flow.php">← Vissza a Flow adminhoz</a></div>

<form class="panel filter" method="get">
<label>Időszak kezdete<input type="date" name="from" value="<?=portal_h($fromLocal->format('Y-m-d'))?>"></label>
<label>Időszak vége<input type="date" name="to" value="<?=portal_h($toLocal->modify('-1 day')->format('Y-m-d'))?>"></label>
<label>Jármű<select name="plate"><option value="">Összes jármű</option>
<?php foreach($vehicles as $v):$vp=aims_normalize_plate((string)$v['plate']);?>
<option value="<?=portal_h($vp)?>" <?=$vp===$plate?'selected':''?>><?=portal_h((string)$v['plate'])?></option>
<?php endforeach;?></select></label>
<label style="align-self:end"><button class="btn gold" type="submit">RIPORT LEKÉRÉSE</button></label>
</form>
<div class="metrics">
<div class="metric"><small>Összes külföldi idő</small><b><?=portal_h(flow_duration($foreignTotal))?></b></div>
<div class="metric"><small>Hazai ország</small><b><?=portal_h(country_label($home,$names))?></b></div>
<div class="metric"><small>Rögzített szakasz</small><b><?=count($rows)?></b></div>
</div>

<section class="panel">
<h2>Országonkénti összesítés</h2>
<?php if(!$byCountry):?><p class="muted">A kiválasztott időszakban nincs rögzített külföldi tartózkodás.</p>
<?php else:?><div class="table"><table><thead><tr><th>Ország</th><th>Idő</th></tr></thead><tbody>
<?php foreach($byCountry as $code=>$seconds):?><tr><td><b><?=portal_h(country_label($code,$names))?></b></td><td><?=portal_h(flow_duration($seconds))?></td></tr><?php endforeach;?>
</tbody></table></div><?php endif;?>
</section>

<section class="panel">
<h2>Határnapló és tartózkodási szakaszok</h2>
<div class="table"><table><thead><tr><th>Jármű</th><th>Ország</th><th>Belépés</th><th>Kilépés</th><th>Időtartam</th><th>Állapot</th><th>Átmenet</th></tr></thead><tbody>
<?php if(!$rows):?><tr><td colspan="7" class="muted">Nincs adat a kiválasztott időszakra.</td></tr>
<?php else:foreach($rows as $r):
$start=$r['_start']->setTimezone($tz);$end=$r['_end']->setTimezone($tz);
$country=strtoupper((string)$r['country_code']);$open=empty($r['exited_at']);
?>
<tr>
<td><b><?=portal_h((string)$r['plate'])?></b></td>
<td><span class="chip <?=$r['_foreign']?'foreign':'home'?>"><?=portal_h(country_label($country,$names))?></span></td>
<td><?=portal_h($start->format('Y-m-d H:i:s'))?></td>
<td><?=$open?'<span class="muted">jelenleg is ott</span>':portal_h($end->format('Y-m-d H:i:s'))?></td>
<td><b><?=portal_h(flow_duration((int)$r['_seconds']))?></b></td>
<td><?=$open?'<span class="chip foreign">NYITOTT</span>':'<span class="chip home">LEZÁRT</span>'?></td>
<td class="mono"><?=portal_h((string)($r['transition_from']??'—'))?> → <?=portal_h($country)?></td>
</tr>
<?php endforeach;endif;?>
</tbody></table></div>
<p class="muted">A határátlépést a rendszer több egymást követő ország-megfigyelés után erősíti meg, így a határ menti GPS/geocoder ingadozás nem hoz létre rövid, hamis országváltásokat.</p>
</section>
</div></body></html>