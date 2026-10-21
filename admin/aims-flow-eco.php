<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();
require_once __DIR__.'/../inc/portal.php';

$trackingRoot=is_file(__DIR__.'/../api/aims-tracking/bootstrap.php')
    ? __DIR__.'/../api/aims-tracking'
    : __DIR__.'/../server/aims-tracking';
require_once $trackingRoot.'/bootstrap.php';
require_once $trackingRoot.'/eco_report_lib.php';

$pdo=aims_db();
$tz=new DateTimeZone('Europe/Budapest');
$today=new DateTimeImmutable('today',$tz);
$defaultFrom=$today->modify('first day of this month')->format('Y-m-d');
$defaultTo=$today->format('Y-m-d');
$from=trim((string)($_GET['from']??$defaultFrom));
$to=trim((string)($_GET['to']??$defaultTo));
$plate=aims_normalize_plate((string)($_GET['plate']??''));
$driver=trim((string)($_GET['driver']??''));
$error=null;

try{
    $report=aims_eco_build_report($pdo,$from,$to,$plate,$driver);
}catch(Throwable $exception){
    $error=$exception->getMessage();
    $from=$defaultFrom;$to=$defaultTo;$plate='';$driver='';
    $report=aims_eco_build_report($pdo,$from,$to);
}

if(($_GET['download']??'')==='csv'){
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="AIMS-FLOW-ECO-'.$from.'-'.$to.'.csv"');
    header('Cache-Control: private, no-store');
    echo aims_eco_csv($report);exit;
}

$allDrivers=[];
if(aims_eco_table_exists($pdo,'driver_accounts')){
    $allDrivers=$pdo->query('SELECT flow_id,driver_name FROM driver_accounts WHERE enabled=1 ORDER BY driver_name,flow_id')->fetchAll(PDO::FETCH_ASSOC);
}
$allVehicles=$pdo->query('SELECT plate,label FROM vehicles WHERE enabled=1 ORDER BY plate')->fetchAll(PDO::FETCH_ASSOC);
$graded=array_values(array_filter($report['rows'],static fn(array $row):bool=>$row['enoughData']));
$gradeCounts=['A'=>0,'B'=>0,'C'=>0,'D'=>0];
$totalDistance=0.0;$scoreSum=0.0;
foreach($graded as $row){
    if(isset($gradeCounts[$row['grade']]))$gradeCounts[$row['grade']]++;
    $totalDistance+=(float)$row['distanceKm'];
    $scoreSum+=(float)$row['score'];
}
$averageScore=$graded?$scoreSum/count($graded):0.0;

function eco_h(mixed $value):string{return portal_h((string)$value);}
function eco_num(float $value,int $decimals=1):string{return number_format($value,$decimals,',',' ');}
function eco_grade_class(string $grade):string{return match($grade){'A'=>'grade-a','B'=>'grade-b','C'=>'grade-c','D'=>'grade-d',default=>'grade-na'};}
?><!doctype html><html lang="hu"><head><meta charset="utf-8">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIMS FLOW • ECO MÓD</title>
<style>
:root{--bg:#0b0c0e;--panel:#121417;--panel2:#181b1f;--line:#30343a;--text:#f2f4f6;--muted:#929aa3;--gold:#d9ad4e;--green:#55d995;--yellow:#e9c55f;--orange:#e69651;--red:#ef6b73}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px Arial,sans-serif}a{color:inherit;text-decoration:none}.wrap{width:min(1500px,calc(100% - 28px));margin:auto;padding:24px 0 70px}.head{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap}.ey{font-size:9px;letter-spacing:.15em;text-transform:uppercase;color:var(--gold)}h1{margin:6px 0 0;font-size:30px}.sub{color:var(--muted);margin-top:7px;max-width:850px;line-height:1.55}.actions{display:flex;gap:8px;flex-wrap:wrap}.btn,button{border:1px solid var(--line);background:var(--panel2);color:#fff;border-radius:10px;padding:10px 13px;font-weight:900;cursor:pointer}.btn.gold,button.gold{background:linear-gradient(135deg,#f1d77e,#b9852d);border:0;color:#0b0c0e}.panel,.metric{border:1px solid var(--line);background:var(--panel);border-radius:16px;padding:16px}.filter{display:grid;grid-template-columns:repeat(4,minmax(160px,1fr)) auto;gap:10px;align-items:end;margin-top:18px}.filter label{display:grid;gap:6px;color:var(--muted);font-size:9px;font-weight:900;text-transform:uppercase;letter-spacing:.08em}.filter input,.filter select{height:44px;border:1px solid var(--line);background:#0c0e10;color:#fff;border-radius:10px;padding:0 11px}.metrics{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin:12px 0}.metric small{display:block;color:var(--muted);font-size:9px;text-transform:uppercase;letter-spacing:.08em}.metric b{display:block;font-size:24px;margin-top:7px}.grade-a{color:var(--green)}.grade-b{color:var(--yellow)}.grade-c{color:var(--orange)}.grade-d{color:var(--red)}.grade-na{color:var(--muted)}.legend{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.legend article{border:1px solid var(--line);background:var(--panel2);border-radius:14px;padding:14px}.legend strong{font-size:24px}.legend p{margin:7px 0 0;color:var(--muted);line-height:1.45}.section-head{display:flex;justify-content:space-between;align-items:end;gap:12px;flex-wrap:wrap;margin:22px 0 8px}.section-head h2{margin:0}.table{overflow:auto;border:1px solid var(--line);border-radius:13px;background:var(--panel)}table{width:100%;border-collapse:collapse;min-width:1180px}th,td{text-align:left;padding:10px;border-bottom:1px solid #292d32;vertical-align:top}th{font-size:8px;text-transform:uppercase;letter-spacing:.09em;color:var(--muted)}.grade{display:inline-flex;align-items:center;justify-content:center;width:38px;height:38px;border:1px solid currentColor;border-radius:50%;font-size:20px;font-weight:900}.score{font-size:19px;font-weight:900}.chip{display:inline-block;border:1px solid #3c4249;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900}.muted{color:var(--muted);font-size:11px}.warning{border-color:#6b5429;background:#211b10}.error{border-color:#783238;background:#2c1215}.note{line-height:1.55}.mono{font-family:ui-monospace,Consolas,monospace}.event-critical{color:var(--red)}.event-warning{color:var(--yellow)}
@media(max-width:1100px){.filter{grid-template-columns:1fr 1fr}.metrics{grid-template-columns:1fr 1fr}.legend{grid-template-columns:1fr 1fr}}@media(max-width:600px){.filter,.metrics,.legend{grid-template-columns:1fr}.wrap{width:min(100% - 18px,1500px)}}
</style></head><body><div class="wrap">
<div class="head"><div><div class="ey">AIMS FLOW • REJTETT ADMIN FUNKCIÓ</div><h1>ECO MÓD</h1><div class="sub">Sofőr és rendszám szerinti vezetési stílus. A minősítés a FLOW munkanap alatt rögzített, minőségszűrt GPS-sebességmintákból készül; a sofőralkalmazásban nem jelenik meg.</div></div><div class="actions"><a class="btn" href="aims-flow-monthly-report.php">HAVI RIPORT</a><a class="btn" href="aims-flow.php">← FLOW ADMIN</a></div></div>

<form class="panel filter" method="get">
<label>Kezdő dátum<input type="date" name="from" value="<?=eco_h($from)?>"></label>
<label>Záró dátum<input type="date" name="to" value="<?=eco_h($to)?>"></label>
<label>Sofőr<select name="driver"><option value="">Összes sofőr</option><?php foreach($allDrivers as $item):$fid=trim((string)$item['flow_id']);?><option value="<?=eco_h($fid)?>" <?=$fid===$driver?'selected':''?>><?=eco_h((string)$item['driver_name'])?> · <?=eco_h($fid)?></option><?php endforeach;?></select></label>
<label>Rendszám<select name="plate"><option value="">Összes rendszám</option><?php foreach($allVehicles as $item):$vp=aims_normalize_plate((string)$item['plate']);?><option value="<?=eco_h($vp)?>" <?=$vp===$plate?'selected':''?>><?=eco_h((string)$item['plate'])?></option><?php endforeach;?></select></label>
<button class="gold" type="submit">ELEMZÉS</button>
</form>
<?php if($error):?><div class="panel error" style="margin-top:12px"><?=eco_h($error)?></div><?php endif;?>

<div class="metrics">
<div class="metric"><small>Értékelhető páros</small><b><?=count($graded)?></b></div>
<div class="metric"><small>Átlagpontszám</small><b><?=eco_num($averageScore,1)?></b></div>
<div class="metric"><small>Elemzett távolság</small><b><?=eco_num($totalDistance,0)?> km</b></div>
<div class="metric"><small>A / B minősítés</small><b class="grade-a"><?=($gradeCounts['A']+$gradeCounts['B'])?></b></div>
<div class="metric"><small>C / D minősítés</small><b class="grade-d"><?=($gradeCounts['C']+$gradeCounts['D'])?></b></div>
</div>

<section class="panel warning note"><b>Admin-kontroll:</b> az ECO osztályzat vezetői jelzés és coaching-adat. Nem használható önmagában automatikus szankcióhoz, bérdöntéshez vagy munkajogi következményhez. A rövid, 50 km alatti vagy 45 percnél kevesebb mozgást tartalmazó minta nem kap osztályzatot.</section>

<div class="section-head"><h2>A–D skála</h2><a class="btn gold" href="?<?=http_build_query(['from'=>$from,'to'=>$to,'driver'=>$driver,'plate'=>$plate,'download'=>'csv'])?>">CSV LETÖLTÉSE</a></div>
<div class="legend">
<article><strong class="grade-a">A · 90–100</strong><p>Kímélő, egyenletes vezetés. Legfeljebb 4 hirtelen esemény / 100 km és gyakorlatilag nincs súlyos esemény.</p></article>
<article><strong class="grade-b">B · 75–89</strong><p>Jó vezetési minta kisebb kilengésekkel. Legfeljebb 10 hirtelen esemény / 100 km.</p></article>
<article><strong class="grade-c">C · 55–74</strong><p>Fejlesztendő. Gyakori erősebb gyorsítás vagy fékezés, de még nem tartósan szélsőséges.</p></article>
<article><strong class="grade-d">D · 0–54</strong><p>Erősen egyenetlen minta, sok vagy súlyos gyorsítási és fékezési eseménnyel.</p></article>
</div>

<div class="section-head"><h2>Sofőr–rendszám összesítés</h2><div class="muted">Az eseményszámok 100 km-re vetítve jelennek meg.</div></div>
<div class="table"><table><thead><tr><th>Minősítés</th><th>Sofőr</th><th>Rendszám</th><th>Pont</th><th>Távolság</th><th>Mozgás</th><th>Egyenletes</th><th>Gyorsítás</th><th>Súlyos gyorsítás</th><th>Fékezés</th><th>Súlyos fékezés</th><th>Max. gyorsulás / lassulás</th></tr></thead><tbody>
<?php if(!$report['rows']):?><tr><td colspan="12" class="muted">A kiválasztott időszakban nincs értékelhető FLOW munkanap és GPS-adat.</td></tr><?php else:foreach($report['rows'] as $row):?>
<tr>
<td><span class="grade <?=eco_grade_class((string)$row['grade'])?>"><?=eco_h($row['grade'])?></span><div class="muted" style="margin-top:6px"><?=eco_h($row['label'])?></div></td>
<td><b><?=eco_h($row['driverName'])?></b><div class="muted mono"><?=eco_h($row['flowId']?:'—')?></div></td>
<td><b><?=eco_h($row['plate'])?></b></td>
<td><span class="score"><?=eco_num((float)$row['score'],1)?></span></td>
<td><?=eco_num((float)$row['distanceKm'],1)?> km</td>
<td><?=eco_num((float)$row['movingHours'],1)?> óra</td>
<td><?=eco_num((float)$row['smoothRatio']*100,1)?>%</td>
<td><?=eco_num((float)$row['hardAccelRate'],2)?></td>
<td class="event-critical"><?=eco_num((float)$row['severeAccelRate'],2)?></td>
<td><?=eco_num((float)$row['hardBrakeRate'],2)?></td>
<td class="event-critical"><?=eco_num((float)$row['severeBrakeRate'],2)?></td>
<td>+<?=eco_num((float)$row['maxAccel'],2)?> / −<?=eco_num((float)$row['maxBrake'],2)?> m/s²</td>
</tr><?php endforeach;endif;?></tbody></table></div>

<div class="section-head"><h2>Legutóbbi gyorsítási és fékezési események</h2><div class="muted">Legfeljebb 3000 esemény kerül a lekérdezésbe.</div></div>
<div class="table"><table style="min-width:980px"><thead><tr><th>Időpont</th><th>Sofőr</th><th>Rendszám</th><th>Esemény</th><th>Gyorsulás</th><th>Sebességváltozás</th><th>Hely</th></tr></thead><tbody>
<?php if(!$report['events']):?><tr><td colspan="7" class="muted">Nincs küszöbértéket elérő esemény.</td></tr><?php else:foreach(array_slice($report['events'],0,300) as $event):$class=$event['severity']==='critical'?'event-critical':'event-warning';?>
<tr><td><?=eco_h($event['capturedAt']->setTimezone($tz)->format('Y-m-d H:i:s'))?></td><td><b><?=eco_h($event['driverName'])?></b><div class="muted mono"><?=eco_h($event['flowId']?:'—')?></div></td><td><?=eco_h($event['plate'])?></td><td class="<?=$class?>"><b><?=eco_h($event['type'])?></b></td><td><?=eco_num((float)$event['accelerationMps2'],2)?> m/s²</td><td><?=eco_num((float)$event['beforeKmh'],0)?> → <?=eco_num((float)$event['afterKmh'],0)?> km/h</td><td class="mono"><?=eco_num((float)$event['latitude'],5)?>, <?=eco_num((float)$event['longitude'],5)?></td></tr>
<?php endforeach;endif;?></tbody></table></div>

<p class="muted note" style="margin-top:14px">A rendszer nem állapít meg sebességtúllépést, üzemanyag-fogyasztást vagy hibás vezetést. Ehhez hiteles útszakasz-sebességhatár, jármű-CAN/FMS adat és emberi ellenőrzés szükséges. Az ECO MÓD jelenleg a gyorsítások, fékezések és az egyenletes haladás mintáját elemzi.</p>
</div></body></html>
