<?php
declare(strict_types=1);
require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();aims_start_session();aims_security_headers(true);
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';
require_once __DIR__.'/../api/aims-tracking/mileage_report_lib.php';

$pdo=aims_db();$tz=new DateTimeZone('Europe/Budapest');$utc=new DateTimeZone('UTC');
$home=strtoupper(trim((string)(getenv('AIMS_HOME_COUNTRY')?:'HU')));if(!preg_match('/^[A-Z]{2}$/',$home))$home='HU';
$rateEur=85.0;$today=new DateTimeImmutable('now',$tz);
$monthRaw=trim((string)($_GET['month']??$today->format('Y-m')));
if(!preg_match('/^\d{4}-\d{2}$/',$monthRaw))$monthRaw=$today->format('Y-m');
$monthStart=DateTimeImmutable::createFromFormat('!Y-m',$monthRaw,$tz)?:$today->modify('first day of this month')->setTime(0,0);
$monthEnd=$monthStart->modify('+1 month');$fromUtc=$monthStart->setTimezone($utc);$toUtc=$monthEnd->setTimezone($utc);
$from=trim((string)($_GET['from']??''));$to=trim((string)($_GET['to']??''));$custom=$from!==''||$to!=='';
if($custom){try{$period=aims_report_period($from,$to);$fromUtc=$period['startUtc'];$toUtc=$period['endUtc'];}catch(InvalidArgumentException $e){http_response_code(422);exit(htmlspecialchars($e->getMessage(),ENT_QUOTES,'UTF-8'));}}
$periodLabel=$custom?$from.'_'.$to:$monthRaw;
$nowUtc=new DateTimeImmutable('now',$utc);$rangeEnd=$toUtc<$nowUtc?$toUtc:$nowUtc;
$plate=aims_normalize_plate((string)($_GET['plate']??''));

$names=['HU'=>'Magyarország','SK'=>'Szlovákia','AT'=>'Ausztria','DE'=>'Németország','PL'=>'Lengyelország','CZ'=>'Csehország','SI'=>'Szlovénia','HR'=>'Horvátország','RO'=>'Románia','RS'=>'Szerbia','UA'=>'Ukrajna','LT'=>'Litvánia','LV'=>'Lettország','EE'=>'Észtország','IT'=>'Olaszország','FR'=>'Franciaország','NL'=>'Hollandia','BE'=>'Belgium','LU'=>'Luxemburg','CH'=>'Svájc','ES'=>'Spanyolország','PT'=>'Portugália','DK'=>'Dánia','SE'=>'Svédország','NO'=>'Norvégia','FI'=>'Finnország','BG'=>'Bulgária','GR'=>'Görögország'];
function fs_h($v):string{return htmlspecialchars((string)$v,ENT_QUOTES,'UTF-8');}
function fs_duration(int $s):string{$s=max(0,$s);$d=intdiv($s,86400);$s%=86400;$h=intdiv($s,3600);$m=intdiv($s%3600,60);$a=[];if($d)$a[]=$d.' nap';if($h||$d)$a[]=$h.' óra';$a[]=$m.' perc';return implode(' ',$a);}
function fs_country(string $c,array $names):string{return ($names[$c]??$c).' ('.$c.')';}
function fs_merge_intervals(array $a):array{
 usort($a,fn($x,$y)=>$x[0]<=>$y[0]);$out=[];
 foreach($a as $x){if(!$out){$out[]=$x;continue;}$i=count($out)-1;
   if($x[0]-$out[$i][1]<=7200)$out[$i][1]=max($out[$i][1],$x[1]);else$out[]=$x;
 }return $out;
}
function fs_eligible_days(array $intervals):int{
 $days=0;foreach(fs_merge_intervals($intervals) as [$a,$b]){$sec=max(0,$b-$a);if($sec<=0)continue;
   if($sec<86400){if($sec>=28800)$days++;continue;}
   $days+=intdiv($sec,86400);if(($sec%86400)>=28800)$days++;
 }return $days;
}

$columns=array_column($pdo->query('PRAGMA table_info(vehicles)')->fetchAll(PDO::FETCH_ASSOC),'name');
$driverSql=in_array('driver_name',$columns,true)?'v.driver_name':'NULL';
$emailSql=in_array('driver_email',$columns,true)?'v.driver_email':'NULL';
$vehicles=$pdo->query('SELECT v.id,v.plate,v.label,'.$driverSql.' AS driver_name,'.$emailSql.' AS driver_email FROM vehicles v WHERE enabled=1 ORDER BY plate')->fetchAll(PDO::FETCH_ASSOC)?:[];
$sql='SELECT s.*,v.plate,v.label,'.$driverSql.' AS driver_name,'.$emailSql.' AS driver_email FROM country_stays s JOIN vehicles v ON v.id=s.vehicle_id WHERE julianday(s.entered_at)<julianday(:end) AND julianday(COALESCE(s.exited_at,:end))>julianday(:start)';
$params=[':start'=>$fromUtc->format(DateTimeInterface::ATOM),':end'=>$toUtc->format(DateTimeInterface::ATOM)];
if($plate!==''){$sql.=' AND v.plate=:plate';$params[':plate']=$plate;}
$sql.=' ORDER BY v.plate,s.entered_at,s.id';
$q=$pdo->prepare($sql);$q->execute($params);$raw=$q->fetchAll(PDO::FETCH_ASSOC)?:[];

$byVehicle=[];$byCountry=[];$segments=[];
foreach($raw as $r){
 try{$enter=new DateTimeImmutable((string)$r['entered_at']);}catch(Throwable){continue;}
 $exit=null;if(!empty($r['exited_at']))try{$exit=new DateTimeImmutable((string)$r['exited_at']);}catch(Throwable){}
 $start=$enter>$fromUtc?$enter:$fromUtc;$end=$exit??$rangeEnd;if($end>$rangeEnd)$end=$rangeEnd;if($end<=$start)continue;
 $sec=$end->getTimestamp()-$start->getTimestamp();$cc=strtoupper((string)$r['country_code']);$vid=(int)$r['vehicle_id'];
 if(!isset($byVehicle[$vid]))$byVehicle[$vid]=['id'=>$vid,'plate'=>(string)$r['plate'],'label'=>(string)($r['label']??''),'driver'=>(string)($r['driver_name']??''),'email'=>(string)($r['driver_email']??''),'foreign_sec'=>0,'intervals'=>[],'countries'=>[]];
 $byVehicle[$vid]['countries'][$cc]=($byVehicle[$vid]['countries'][$cc]??0)+$sec;
 if($cc!==$home){$byVehicle[$vid]['foreign_sec']+=$sec;$byVehicle[$vid]['intervals'][]=[$start->getTimestamp(),$end->getTimestamp()];$byCountry[$cc]=($byCountry[$cc]??0)+$sec;}
 $segments[]=$r+['_start'=>$start,'_end'=>$end,'_sec'=>$sec,'_foreign'=>$cc!==$home];
}
foreach($byVehicle as &$v){$v['eligible_days']=fs_eligible_days($v['intervals']);$v['per_diem_eur']=$v['eligible_days']*$rateEur;}unset($v);
uasort($byVehicle,fn($a,$b)=>strcmp($a['plate'],$b['plate']));arsort($byCountry);
$totalForeign=array_sum(array_column($byVehicle,'foreign_sec'));$totalDays=array_sum(array_column($byVehicle,'eligible_days'));$totalEur=array_sum(array_column($byVehicle,'per_diem_eur'));

if(($_GET['format']??'')==='csv'){
 header('Content-Type: text/csv; charset=utf-8');header('Content-Disposition: attachment; filename="AIMS-kulfoldi-tartozkodas-'.$monthRaw.'.csv"');
 echo "\xEF\xBB\xBF";$o=fopen('php://output','w');fputcsv($o,['Hónap','Rendszám','Sofőr','Külföldi idő (óra)','Elszámolható nap','Tarifa EUR/nap','Kalkulált EUR'],';');
 foreach($byVehicle as $v)fputcsv($o,[$periodLabel,$v['plate'],$v['driver'],round($v['foreign_sec']/3600,2),$v['eligible_days'],number_format($rateEur,2,'.',''),number_format($v['per_diem_eur'],2,'.','')],';');
 fclose($o);exit;
}
?><!doctype html><html lang="hu"><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow,noarchive"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>AIMS • Külföldi tartózkodás és napidíj</title><style>
.report-filter{display:grid;grid-template-columns:1fr 1.2fr auto auto;gap:9px;align-items:end}.report-filter label{display:grid;gap:5px;font-size:9px;color:#94a4b0}.report-filter input,.report-filter select{min-height:42px;padding:0 10px}.report-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:12px 0}.report-kpi{border:1px solid #203142;border-radius:12px;background:linear-gradient(145deg,#102131,#0b1721);padding:14px}.report-kpi small{display:block;color:#8293a2;font-size:9px}.report-kpi b{display:block;font-size:25px;margin-top:6px}.report-note{border:1px solid #5a4b27;background:#15150f;border-radius:12px;padding:13px;color:#d7c58f;line-height:1.5}.country-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.country-card{border:1px solid #203142;border-radius:10px;background:#0b1822;padding:11px}.country-card b{display:block}.country-card span{color:#8293a2;font-size:9px}.right{text-align:right}@media(max-width:900px){.report-filter{grid-template-columns:1fr 1fr}.report-kpis,.country-grid{grid-template-columns:1fr 1fr}}@media(max-width:600px){.report-filter,.report-kpis,.country-grid{grid-template-columns:1fr}}
</style><link rel="stylesheet" href="admin-content.css?v=20261022"><link rel="stylesheet" href="admin-shell.css?v=20261022"><script src="aims-admin-shell.js?v=20261022-v40" defer></script><link rel="stylesheet" href="admin-refresh.css?v=20261022"></head><body class="aims-unified"><?php require_once __DIR__.'/admin-shell-static.php'; aims_render_admin_shell(); ?><main class="wrap">
<header class="head"><div><small>AIMS FLEET • HAVI RIPORT</small><h1>Külföldi tartózkodás és napidíj</h1><div class="muted">GPS-adatokból megállapított országváltások alapján • autónként • választható időszakra</div></div></header>
<form class="panel report-filter" method="get"><label>Hónap<input type="month" name="month" value="<?=fs_h($monthRaw)?>" onchange="this.form.elements.from.value='';this.form.elements.to.value=''"></label><label>Kezdőnap<input type="date" name="from" value="<?=fs_h($from)?>"></label><label>Zárónap, beleértve<input type="date" name="to" value="<?=fs_h($to)?>"></label><label>Jármű<select name="plate"><option value="">Összes jármű</option><?php foreach($vehicles as $v):$vp=aims_normalize_plate((string)$v['plate']);?><option value="<?=fs_h($vp)?>" <?=$vp===$plate?'selected':''?>><?=fs_h($v['plate'].' '.($v['driver_name']?'• '.$v['driver_name']:''))?></option><?php endforeach;?></select></label><button class="gold" type="submit">RIPORT</button><a class="btn" href="?<?=fs_h(http_build_query(['month'=>$monthRaw,'from'=>$from,'to'=>$to,'plate'=>$plate,'format'=>'csv']))?>">CSV LETÖLTÉSE</a></form>
<section class="report-kpis"><div class="report-kpi"><small>Összes külföldi idő</small><b><?=fs_h(fs_duration((int)$totalForeign))?></b></div><div class="report-kpi"><small>Elszámolható nap</small><b><?=$totalDays?></b></div><div class="report-kpi"><small>Fuvarozói tarifa</small><b>85 EUR / nap</b></div><div class="report-kpi"><small>Kalkulált összeg</small><b><?=number_format((float)$totalEur,0,',',' ')?> EUR</b></div></section>
<div class="report-note"><b>Magyar szabály:</b> nemzetközi közúti árufuvarozásban gépkocsivezetőnél az igazolás nélkül elszámolható költség napi <b>85 EUR-nak megfelelő forintösszeg</b>. Ez nem országonként eltérő tarifa. A rendszer országonként a tényleges GPS-tartózkodást bontja, a 85 EUR-os összeget pedig a külföldi kiküldetés elszámolható napjaira számolja. A GPS-riport operációs kalkuláció; bérszámfejtésnél az elrendelt kiküldetés tényleges indulási/érkezési adata az irányadó.</div>
<section class="panel"><div class="panelhead"><div><small>IDŐSZAKI BONTÁS</small><h2>Autónként / sofőrönként</h2></div></div><div class="table"><table><thead><tr><th>Jármű</th><th>Sofőr</th><th>Külföldi idő</th><th>Elszámolható nap</th><th>85 EUR/nap</th><th class="right">Kalkulált összeg</th></tr></thead><tbody>
<?php if(!$byVehicle):?><tr><td colspan="6" class="empty">Nincs országonkénti tartózkodási adat a kiválasztott időszakban.</td></tr><?php else:foreach($byVehicle as $v):?><tr><td><b><?=fs_h($v['plate'])?></b><div class="muted"><?=fs_h($v['label'])?></div></td><td><?=fs_h($v['driver']?:'—')?></td><td><?=fs_h(fs_duration((int)$v['foreign_sec']))?></td><td><b><?=$v['eligible_days']?></b></td><td>85 EUR</td><td class="right"><b><?=number_format((float)$v['per_diem_eur'],0,',',' ')?> EUR</b></td></tr><?php endforeach;endif;?></tbody></table></div></section>
<section class="panel"><div class="panelhead"><div><small>ORSZÁGONKÉNT</small><h2>Tényleges külföldi tartózkodás</h2></div></div><?php if(!$byCountry):?><div class="empty">Nincs külföldi tartózkodás.</div><?php else:?><div class="country-grid"><?php foreach($byCountry as $cc=>$sec):?><div class="country-card"><b><?=fs_h(fs_country($cc,$names))?></b><span><?=fs_h(fs_duration((int)$sec))?> • <?=number_format($sec/3600,1,',',' ')?> óra</span></div><?php endforeach;?></div><?php endif;?></section>
<details class="aims-advanced"><summary><span><b>Részletes határnapló</b><small>Belépés, kilépés, országváltások</small></span><strong><?=count($segments)?> szakasz</strong></summary><div class="aims-advanced-body"><div class="table"><table><thead><tr><th>Jármű</th><th>Ország</th><th>Belépés</th><th>Kilépés</th><th>Idő</th></tr></thead><tbody><?php foreach($segments as $s):$cc=strtoupper((string)$s['country_code']);?><tr><td><b><?=fs_h($s['plate'])?></b></td><td><?=fs_h(fs_country($cc,$names))?></td><td><?=fs_h($s['_start']->setTimezone($tz)->format('Y-m-d H:i'))?></td><td><?=fs_h($s['_end']->setTimezone($tz)->format('Y-m-d H:i'))?></td><td><?=fs_h(fs_duration((int)$s['_sec']))?></td></tr><?php endforeach;?></tbody></table></div></div></details>
</main></body></html>