<?php
declare(strict_types=1);

/** Admin-only mileage accounting. Raw GPS, jobs and historical homes stay intact. */
function aims_mileage_schema(PDO $pdo): void {
    $pdo->exec('CREATE TABLE IF NOT EXISTS vehicle_home_locations (
      id INTEGER PRIMARY KEY AUTOINCREMENT, vehicle_id INTEGER NOT NULL,
      flow_id TEXT NOT NULL DEFAULT "", address TEXT NOT NULL,
      latitude REAL NOT NULL, longitude REAL NOT NULL, radius_m INTEGER NOT NULL DEFAULT 200,
      valid_from TEXT NOT NULL, valid_until TEXT, created_at TEXT NOT NULL,
      FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE,
      UNIQUE(vehicle_id,valid_from))');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_vehicle_home_period ON vehicle_home_locations(vehicle_id,valid_from)');
    $pdo->exec('CREATE TABLE IF NOT EXISTS flow_job_finance (
      job_id INTEGER PRIMARY KEY, planned_km REAL, revenue_eur_cents INTEGER,
      service_date TEXT, flow_id TEXT NOT NULL DEFAULT "", updated_at TEXT NOT NULL,
      FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE)');
    $pdo->exec('CREATE TABLE IF NOT EXISTS flow_mileage_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT, entity_type TEXT NOT NULL, entity_id INTEGER NOT NULL,
      before_json TEXT, after_json TEXT NOT NULL, created_at TEXT NOT NULL)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_points_mileage_time ON points(vehicle_id,julianday(captured_at),id)');
}

function aims_report_period(string $from, string $to): array {
    $tz=new DateTimeZone('Europe/Budapest');$utc=new DateTimeZone('UTC');
    $a=DateTimeImmutable::createFromFormat('!Y-m-d',$from,$tz);
    $b=DateTimeImmutable::createFromFormat('!Y-m-d',$to,$tz);
    if(!$a||!$b||$a->format('Y-m-d')!==$from||$b->format('Y-m-d')!==$to||$b<$a)
        throw new InvalidArgumentException('Adj meg érvényes kezdő és záró dátumot.');
    if((int)$a->diff($b)->days>365)throw new InvalidArgumentException('Egyszerre legfeljebb 366 nap kérhető le.');
    $end=$b->modify('+1 day');
    return ['month'=>$a->format('Y-m'),'from'=>$from,'to'=>$to,'tz'=>$tz,'utc'=>$utc,
      'startLocal'=>$a,'endLocal'=>$end,'startUtc'=>$a->setTimezone($utc),'endUtc'=>$end->setTimezone($utc),'customRange'=>true];
}

function aims_mileage_decimal(mixed $value, float $max, int $decimals=2): ?float {
    if($value!==null&&!is_scalar($value))throw new InvalidArgumentException('Egyetlen számértéket adj meg.');
    $text=str_replace(["\xc2\xa0",' '], '',trim((string)($value??'')));
    if($text==='')return null;
    $text=str_replace(',','.',$text);
    if(!preg_match('/^\d+(?:\.\d{1,'.$decimals.'})?$/D',$text)||!is_finite((float)$text)||(float)$text>$max)
        throw new InvalidArgumentException('Érvénytelen vagy túl nagy összeg / kilométer.');
    return (float)$text;
}

function aims_mileage_audit(PDO $pdo,string $kind,int $id,?array $before,array $after): void {
    $pdo->prepare('INSERT INTO flow_mileage_audit(entity_type,entity_id,before_json,after_json,created_at) VALUES(?,?,?,?,?)')
      ->execute([$kind,$id,$before===null?null:json_encode($before,JSON_UNESCAPED_UNICODE),json_encode($after,JSON_UNESCAPED_UNICODE),gmdate(DateTimeInterface::ATOM)]);
}

function aims_mileage_save_home(PDO $pdo,array $data): int {
    aims_mileage_schema($pdo);
    $vid=(int)($data['vehicle_id']??0);$flow=trim((string)($data['flow_id']??''));
    $address=trim((string)($data['address']??''));
    $lat=filter_var($data['latitude']??null,FILTER_VALIDATE_FLOAT);
    $lng=filter_var($data['longitude']??null,FILTER_VALIDATE_FLOAT);
    $radius=filter_var($data['radius_m']??200,FILTER_VALIDATE_INT);
    $period=aims_report_period((string)($data['valid_from']??''),(string)($data['valid_from']??''));
    $valid=$period['startUtc']->format(DateTimeInterface::ATOM);
    if($address===''||mb_strlen($address)>500||$lat===false||$lng===false||abs($lat)>90||abs($lng)>180||$radius===false||$radius<50||$radius>1000)
        throw new InvalidArgumentException('Pontos cím, térképi hely és 50–1000 méteres körzet szükséges.');
    $q=$pdo->prepare('SELECT id FROM vehicles WHERE id=?');$q->execute([$vid]);
    if(!$q->fetchColumn())throw new InvalidArgumentException('Ismeretlen rendszám.');
    if($flow!==''){
        $q=$pdo->prepare('SELECT id FROM driver_accounts WHERE flow_id=?');$q->execute([$flow]);
        if(!$q->fetchColumn())throw new InvalidArgumentException('Ismeretlen sofőr.');
    }
    $pdo->beginTransaction();
    try{
        $q=$pdo->prepare('SELECT * FROM vehicle_home_locations WHERE vehicle_id=? ORDER BY valid_from DESC LIMIT 1');$q->execute([$vid]);$old=$q->fetch(PDO::FETCH_ASSOC)?:null;
        if($old&&$valid===$old['valid_from']){
            $id=(int)$old['id'];
            $pdo->prepare('UPDATE vehicle_home_locations SET flow_id=?,address=?,latitude=?,longitude=?,radius_m=? WHERE id=?')->execute([$flow,$address,$lat,$lng,$radius,$id]);
            aims_mileage_audit($pdo,'home_correction',$id,$old,['flow_id'=>$flow,'address'=>$address,'latitude'=>$lat,'longitude'=>$lng,'radius_m'=>$radius,'valid_from'=>$valid]);
            $pdo->commit();return $id;
        }
        if($old&&$valid<$old['valid_from'])throw new InvalidArgumentException('Az új lakóhely kezdőnapja nem előzheti meg az utolsó mentett lakóhelyét.');
        $pdo->prepare('UPDATE vehicle_home_locations SET valid_until=? WHERE vehicle_id=? AND (valid_until IS NULL OR valid_until>?)')->execute([$valid,$vid,$valid]);
        $pdo->prepare('INSERT INTO vehicle_home_locations(vehicle_id,flow_id,address,latitude,longitude,radius_m,valid_from,created_at) VALUES(?,?,?,?,?,?,?,?)')
          ->execute([$vid,$flow,$address,$lat,$lng,$radius,$valid,gmdate(DateTimeInterface::ATOM)]);
        $id=(int)$pdo->lastInsertId();aims_mileage_audit($pdo,'home',$id,$old,['vehicle_id'=>$vid,'flow_id'=>$flow,'address'=>$address,'latitude'=>$lat,'longitude'=>$lng,'radius_m'=>$radius,'valid_from'=>$valid]);
        $pdo->commit();return $id;
    }catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();throw $e;}
}

function aims_mileage_save_finance(PDO $pdo,int $jobId,array $data): void {
    aims_mileage_schema($pdo);
    $km=aims_mileage_decimal($data['planned_km']??'',1000000,2);
    $eur=aims_mileage_decimal($data['revenue_eur']??'',100000000,2);
    $date=trim((string)($data['service_date']??''));$flow=trim((string)($data['flow_id']??''));
    if($date!=='')aims_report_period($date,$date);
    if($flow!==''){
        $q=$pdo->prepare('SELECT id FROM driver_accounts WHERE flow_id=?');$q->execute([$flow]);
        if(!$q->fetchColumn())throw new InvalidArgumentException('Ismeretlen sofőr.');
    }
    $q=$pdo->prepare('SELECT id FROM jobs WHERE id=? AND status<>"deleted"');$q->execute([$jobId]);
    if(!$q->fetchColumn())throw new InvalidArgumentException('Ismeretlen vagy törölt fuvar.');
    $own=!$pdo->inTransaction();if($own)$pdo->beginTransaction();
    try{
        $q=$pdo->prepare('SELECT * FROM flow_job_finance WHERE job_id=?');$q->execute([$jobId]);$old=$q->fetch(PDO::FETCH_ASSOC)?:null;
        $cents=$eur===null?null:(int)round($eur*100);
        $pdo->prepare('INSERT INTO flow_job_finance(job_id,planned_km,revenue_eur_cents,service_date,flow_id,updated_at) VALUES(?,?,?,?,?,?)
          ON CONFLICT(job_id) DO UPDATE SET planned_km=excluded.planned_km,revenue_eur_cents=excluded.revenue_eur_cents,service_date=excluded.service_date,flow_id=excluded.flow_id,updated_at=excluded.updated_at')
          ->execute([$jobId,$km,$cents,$date?:null,$flow,gmdate(DateTimeInterface::ATOM)]);
        aims_mileage_audit($pdo,'finance',$jobId,$old,['planned_km'=>$km,'revenue_eur_cents'=>$cents,'service_date'=>$date?:null,'flow_id'=>$flow]);
        if($own)$pdo->commit();
    }catch(Throwable $e){if($own&&$pdo->inTransaction())$pdo->rollBack();throw $e;}
}

function aims_mileage_time(mixed $value): ?int {
    if(!is_string($value)||trim($value)==='')return null;
    try{return (new DateTimeImmutable($value))->getTimestamp();}catch(Throwable){return null;}
}

function aims_mileage_home_at(array $homes,int $time,string $flow): ?array {
    foreach($homes as $h)if($time>=($h['_from']??aims_mileage_time($h['valid_from']))&&($h['valid_until']===null||$time<($h['_until']??aims_mileage_time($h['valid_until'])))&&($h['flow_id']===''||$h['flow_id']===$flow))return $h;
    return null;
}

/** Split a measured GPS segment at local midnight and range boundaries. */
function aims_mileage_split(int $a,int $b,float $km,array $period): array {
    $start=max($a,$period['startUtc']->getTimestamp());$end=min($b,$period['endUtc']->getTimestamp());$parts=[];
    while($start<$end){
        $local=(new DateTimeImmutable('@'.$start))->setTimezone($period['tz']);
        $next=min($end,$local->modify('tomorrow')->setTime(0,0)->getTimestamp());
        $parts[$local->format('Y-m-d')]=($parts[$local->format('Y-m-d')]??0)+$km*($next-$start)/max(1,$b-$a);
        $start=$next;
    }
    return $parts;
}

function aims_mileage_row(string $date,array $vehicle,string $flow,array $names): array {
    return ['date'=>$date,'plate'=>$vehicle['plate'],'vehicleId'=>(int)$vehicle['id'],'flowId'=>$flow,
      'driverName'=>$names[$flow]??($flow===''?'Nem azonosított sofőr':$flow),'actualKm'=>0.0,'homeKm'=>0.0,'netKm'=>0.0,
      'plannedKm'=>0.0,'differenceKm'=>0.0,'grossDifferenceKm'=>0.0,'revenueCents'=>0,'costCents'=>0,'marginCents'=>null,
      'jobs'=>0,'missingKm'=>0,'missingRevenue'=>0,'gpsIssues'=>0,'gpsPoints'=>0,'unverifiedHomes'=>0,'missingHome'=>0,'notes'=>[]];
}

function aims_mileage_build_report(PDO $pdo,string $from,string $to,string $plate='',string $onlyFlow=''): array {
    aims_mileage_schema($pdo);require_once __DIR__.'/driver_auth_v2.php';aims_driver_auth_schema($pdo);
    $period=aims_report_period($from,$to);$start=$period['startUtc']->getTimestamp();$end=$period['endUtc']->getTimestamp();
    $scanStart=$start-172800;$scanEnd=min(time(),$end+172800);$names=[];
    foreach($pdo->query('SELECT flow_id,driver_name FROM driver_accounts')->fetchAll(PDO::FETCH_ASSOC) as $a)$names[$a['flow_id']]=$a['driver_name']?:$a['flow_id'];
    $query=$pdo->prepare('SELECT * FROM vehicles WHERE (?="" OR plate=?) ORDER BY plate');$query->execute([$plate,$plate]);
    $daily=[];$trips=[];$jobRows=[];$homeStatus=[];
    foreach($query->fetchAll(PDO::FETCH_ASSOC) as $vehicle){
        $vid=(int)$vehicle['id'];$rows=[];
        $ensure=function(string $date,string $flow)use(&$rows,$vehicle,$names):string{
            $key=$date.'|'.$flow;if(!isset($rows[$key]))$rows[$key]=aims_mileage_row($date,$vehicle,$flow,$names);return $key;
        };
        $q=$pdo->prepare('SELECT * FROM vehicle_home_locations WHERE vehicle_id=? ORDER BY valid_from DESC');$q->execute([$vid]);$homes=$q->fetchAll(PDO::FETCH_ASSOC);
        foreach($homes as &$h){$h['_from']=aims_mileage_time($h['valid_from']);$h['_until']=aims_mileage_time($h['valid_until']);}unset($h);
        $q=$pdo->prepare('SELECT * FROM driver_workdays WHERE vehicle_id=? AND julianday(started_at)<julianday(?) AND julianday(COALESCE(finished_at,?))>=julianday(?) ORDER BY started_at');
        $q->execute([$vid,gmdate('c',$scanEnd),gmdate('c',$scanEnd),gmdate('c',$scanStart)]);$workdays=$q->fetchAll(PDO::FETCH_ASSOC);
        foreach($workdays as &$w){$w['_start']=aims_mileage_time($w['started_at']);$w['_end']=aims_mileage_time($w['finished_at'])??min(time(),$scanEnd);}unset($w);
        $flowAt=function(int $t)use($workdays):string{
            $ids=[];foreach($workdays as $w)if($t>=$w['_start']&&$t<=$w['_end']&&preg_match('/^(\d{6})(?:-|$)/',$w['workday_key'],$m))$ids[$m[1]]=true;
            return count($ids)===1?(string)array_key_first($ids):'';
        };
        $q=$pdo->prepare('SELECT s.*,j.reference,j.status AS job_status FROM job_stops s JOIN jobs j ON j.id=s.job_id
          WHERE j.vehicle_id=? AND j.status<>"deleted" ORDER BY julianday(s.completed_at),s.id');$q->execute([$vid]);$stops=$q->fetchAll(PDO::FETCH_ASSOC);
        $events=[];$lastStops=[];
        foreach($stops as $s){
            $t=aims_mileage_time($s['completed_at']);if($t!==null){$s['_t']=$t;$events[]=$s;}
            if($s['stop_type']==='delivery'&&(!isset($lastStops[$s['job_id']])||(int)$s['stop_order']>(int)$lastStops[$s['job_id']]['stop_order']))$lastStops[$s['job_id']]=$s;
        }
        usort($events,static fn($a,$b)=>[$a['_t'],$a['id']]<=>[$b['_t'],$b['id']]);
        $q=$pdo->prepare('SELECT id,latitude,longitude,accuracy,speed_mps,device_id,flow_id,captured_at FROM points
          WHERE vehicle_id=? AND julianday(captured_at)>=julianday(?) AND julianday(captured_at)<=julianday(?) ORDER BY julianday(captured_at),id LIMIT 2000001');
        $q->execute([$vid,gmdate('c',$scanStart),gmdate('c',$scanEnd)]);
        $previous=null;$segments=[];$candidate=null;$inside=null;$used=[];$eventIndex=0;$count=0;$latest=null;$completionFlows=[];$coverage=[];$invalidSincePrevious=false;
        while($p=$q->fetch(PDO::FETCH_ASSOC)){
            if(++$count>2000000)throw new RuntimeException('Túl sok GPS-pont. Válassz rövidebb időszakot vagy egy rendszámot.');
            $t=aims_mileage_time($p['captured_at']);if($t===null)continue;$p['_t']=$t;
            $flow=trim((string)$p['flow_id']);if($flow==='')$flow=$flowAt($t);$p['_flow']=$flow;
            $date=(new DateTimeImmutable('@'.$t))->setTimezone($period['tz'])->format('Y-m-d');
            $inPeriod=$t>=$start&&$t<$end; $key=$inPeriod?$ensure($date,$flow):null;
            $valid=$p['accuracy']!==null&&is_numeric($p['accuracy'])&&(float)$p['accuracy']>=0&&(float)$p['accuracy']<=100
              &&abs((float)$p['latitude'])<=90&&abs((float)$p['longitude'])<=180;
            if(!$valid){if($key!==null)$rows[$key]['gpsIssues']++;if($candidate)$candidate['issues']++;$inside=null;$invalidSincePrevious=true;continue;}
            if($previous&&$t<=$previous['_t'])continue; // same timestamp / duplicate device fix: never add distance twice
            while(isset($events[$eventIndex])&&$events[$eventIndex]['_t']<=$t){
                $event=$events[$eventIndex++];$inside=null;$candidate=null;$segments=[];
                if($t-$event['_t']<=600&&$event['stop_type']==='delivery')$completionFlows[$event['job_id']]=$flow;
                if($event['stop_type']!=='delivery'||!isset($lastStops[$event['job_id']])||(int)$lastStops[$event['job_id']]['id']!==(int)$event['id'])continue;
                $blocked=false;foreach($stops as $s)if((int)$s['job_id']===(int)$event['job_id']&&($s['completed_at']===null||aims_mileage_time($s['completed_at'])>$event['_t'])){$blocked=true;break;}
                if($blocked||isset($used[$event['id']])||$t-$event['_t']>172800)continue;
                $anchor=$previous&&$event['_t']-$previous['_t']>=0&&$event['_t']-$previous['_t']<=600?$previous:$p;
                $anchorGood=$event['latitude']!==null&&$event['longitude']!==null&&abs($anchor['_t']-$event['_t'])<=600
                  &&aims_distance_m((float)$anchor['latitude'],(float)$anchor['longitude'],(float)$event['latitude'],(float)$event['longitude'])<=max(250,(float)$event['radius_m']+100);
                $candidate=['stop'=>$event,'start'=>$event['_t'],'flow'=>$flow,'anchorGood'=>$anchorGood,'issues'=>$invalidSincePrevious?1:0];
            }
            if($key!==null)$rows[$key]['gpsPoints']++;
            $latest=$p;
            foreach($workdays as $w){
                $wa=$w['_start'];$wb=$w['_end'];
                if($t>=$wa&&$t<=$wb){$coverage[$w['id']]['first']??=$t;$coverage[$w['id']]['last']=$t;}
            }
            if($previous){
                $dt=$t-$previous['_t'];$km=aims_distance_m((float)$previous['latitude'],(float)$previous['longitude'],(float)$p['latitude'],(float)$p['longitude'])/1000;
                $same=$previous['_flow']===$flow&&$previous['device_id']===$p['device_id'];
                $good=$same&&!$invalidSincePrevious&&$dt<=600&&$km/$dt*3600<=180;
                if(!$good){
                    $working=false;foreach($workdays as $w)if($w['_start']<$t&&$w['_end']>$previous['_t']){$working=true;break;}
                    // Overnight parking with tracking stopped must not invalidate
                    // the next working day; no distance is inferred for this gap.
                    if($working||$km>0.2||$invalidSincePrevious)foreach(aims_mileage_split($previous['_t'],$t,0,$period) as $day=>$_){$k=$ensure($day,$flow);$rows[$k]['gpsIssues']++;}
                    if($candidate)$candidate['issues']++;$inside=null;
                }else{
                    if($km*1000<=max(10,min(30,((float)$p['accuracy']+(float)$previous['accuracy'])/2))&&max((float)$p['speed_mps'],(float)$previous['speed_mps'])<1)$km=0;
                    if($candidate)$segments[]=['a'=>$previous['_t'],'b'=>$t,'km'=>$km,'flow'=>$flow];
                    foreach(aims_mileage_split($previous['_t'],$t,$km,$period) as $day=>$part){$k=$ensure($day,$flow);$rows[$k]['actualKm']+=$part;}
                }
            }
            $home=aims_mileage_home_at($homes,$t,$flow);
            if($candidate&&($candidate['flow']!==$flow||$t-$candidate['start']>172800)){$candidate=null;$inside=null;}
            $atHome=$home&&aims_distance_m((float)$p['latitude'],(float)$p['longitude'],(float)$home['latitude'],(float)$home['longitude'])<=(float)$home['radius_m']&&($p['speed_mps']!==null?(float)$p['speed_mps']<=2:(!$previous||($t>$previous['_t']&&aims_distance_m((float)$previous['latitude'],(float)$previous['longitude'],(float)$p['latitude'],(float)$p['longitude'])/($t-$previous['_t'])<=2)));
            if(!$atHome){$inside=null;}elseif($candidate){
                if(!$inside||(int)$inside['home']!==(int)$home['id'])$inside=['t'=>$t,'home'=>(int)$home['id']];
                if($t-$inside['t']>=120){
                    $stop=$candidate['stop'];$blocked=false;
                    foreach($stops as $s){
                        if($s['stop_type']!=='delivery'||($s['completed_at']!==null&&aims_mileage_time($s['completed_at'])<=$inside['t']))continue;
                        foreach($stops as $pickup)if($pickup['job_id']===$s['job_id']&&$pickup['stop_type']==='pickup'&&$pickup['completed_at']!==null&&aims_mileage_time($pickup['completed_at'])<=$inside['t']){$blocked=true;break 2;}
                    }
                    $outside=$stop['latitude']!==null&&$stop['longitude']!==null&&aims_distance_m((float)$stop['latitude'],(float)$stop['longitude'],(float)$home['latitude'],(float)$home['longitude'])>(float)$home['radius_m']+100;
                    if(!$blocked&&$outside&&$candidate['start']>=aims_mileage_time($home['valid_from'])){
                        $tripParts=[];$distance=0.0;
                        foreach($segments as $s){
                            $a=max($s['a'],$candidate['start']);$b=min($s['b'],$inside['t']);
                            if($b<=$a||$s['flow']!==$flow)continue;
                            $km=$s['km']*($b-$a)/($s['b']-$s['a']);$distance+=$km;
                            foreach(aims_mileage_split($a,$b,$km,$period) as $day=>$part)$tripParts[$day]=($tripParts[$day]??0)+$part;
                        }
                        $verified=$candidate['anchorGood']&&$candidate['issues']===0;
                        if($candidate['start']<$end&&$inside['t']>$start&&($onlyFlow===''||$flow===$onlyFlow)){
                            $trips[]=['plate'=>$vehicle['plate'],'flowId'=>$flow,'driverName'=>$names[$flow]??$flow,'reference'=>$stop['reference'],'stopId'=>(int)$stop['id'],
                              'homeId'=>(int)$home['id'],'start'=>$candidate['start'],'arrival'=>$inside['t'],'confirmed'=>$t,'km'=>$distance,'periodKm'=>array_sum($tripParts),'verified'=>$verified,
                              'reason'=>$verified?'GPS-szel megerősítve':'Hiányos GPS vagy nem igazolt lerakói indulás – nincs automatikus levonás'];
                        }
                        foreach($tripParts as $day=>$km){$k=$ensure($day,$flow);if($verified)$rows[$k]['homeKm']+=$km;else $rows[$k]['unverifiedHomes']++;}
                        $used[$stop['id']]=true;$candidate=null;$inside=null;$segments=[];
                    }
                }
            }
            $previous=$p;$invalidSincePrevious=false;
        }
        if($latest){$h=aims_mileage_home_at($homes,$latest['_t'],$latest['_flow']);$homeStatus[]=['plate'=>$vehicle['plate'],'atHome'=>$h!==null&&aims_distance_m((float)$latest['latitude'],(float)$latest['longitude'],(float)$h['latitude'],(float)$h['longitude'])<=(float)$h['radius_m'],'time'=>$latest['_t'],'fresh'=>time()-$latest['_t']<=900];}
        $q=$pdo->prepare('SELECT j.*,f.planned_km,f.revenue_eur_cents,f.service_date,f.flow_id AS finance_flow_id FROM jobs j LEFT JOIN flow_job_finance f ON f.job_id=j.id WHERE j.vehicle_id=? AND j.status<>"deleted"');$q->execute([$vid]);
        foreach($q->fetchAll(PDO::FETCH_ASSOC) as $job){
            $last=$lastStops[$job['id']]??null;$done=$last?aims_mileage_time($last['completed_at']):null;
            if($done!==null)foreach($stops as $stop)if((int)$stop['job_id']===(int)$job['id']&&($stop['completed_at']===null||aims_mileage_time($stop['completed_at'])>$done)){$done=null;break;}
            $service=$job['service_date']?:($done===null?'':(new DateTimeImmutable('@'.$done))->setTimezone($period['tz'])->format('Y-m-d'));
            if($service===''||$service<$from||$service>$to)continue;
            $flow=(string)($job['finance_flow_id']?:($done===null?'':$flowAt($done)));
            if($flow===''&&$done!==null)$flow=$completionFlows[$job['id']]??'';
            if($onlyFlow!==''&&$flow!==$onlyFlow)continue;
            $k=$ensure($service,$flow);$rows[$k]['jobs']++;
            $payload=json_decode((string)($job['order_payload_json']??''),true)?:[];
            $planned=$job['planned_km'];
            if($planned===null&&isset($payload['distance_km'])){try{$planned=aims_mileage_decimal($payload['distance_km'],1000000);}catch(Throwable){}}
            if($planned===null)$rows[$k]['missingKm']++;else $rows[$k]['plannedKm']+=(float)$planned;
            if($job['revenue_eur_cents']===null)$rows[$k]['missingRevenue']++;else $rows[$k]['revenueCents']+=(int)$job['revenue_eur_cents'];
            $jobRows[]=['id'=>(int)$job['id'],'reference'=>$job['reference'],'plate'=>$vehicle['plate'],'date'=>$service,'flowId'=>$flow,'plannedKm'=>$planned,'revenueCents'=>$job['revenue_eur_cents']];
        }
        foreach($workdays as $w){
            $a=aims_mileage_time($w['started_at']);$b=aims_mileage_time($w['finished_at'])??min(time(),$end);$flow='';if(preg_match('/^(\d{6})(?:-|$)/',$w['workday_key'],$m))$flow=$m[1];
            if($a===null||$b<=$a)continue;
            foreach(aims_mileage_split($a,$b,0,$period) as $day=>$_){$k=$ensure($day,$flow);if($rows[$k]['gpsPoints']<2)$rows[$k]['gpsIssues']++;}
            if($a>=$start&&$a<$end&&(($coverage[$w['id']]['first']??PHP_INT_MAX)>$a+600)){$k=$ensure((new DateTimeImmutable('@'.$a))->setTimezone($period['tz'])->format('Y-m-d'),$flow);$rows[$k]['gpsIssues']++;}
            if($b>$start&&$b<=$end&&(($coverage[$w['id']]['last']??0)<$b-600)){$k=$ensure((new DateTimeImmutable('@'.($b-1)))->setTimezone($period['tz'])->format('Y-m-d'),$flow);$rows[$k]['gpsIssues']++;}
            $day=(new DateTimeImmutable('@'.$a))->setTimezone($period['tz'])->format('Y-m-d');$lastDay=(new DateTimeImmutable('@'.$b))->setTimezone($period['tz'])->format('Y-m-d');
            if($a>=$start&&$b<$end&&$day===$lastDay&&$w['end_km']!==null&&$w['finished_at']!==null){
                $k=$ensure($day,$flow);$odo=(float)$w['end_km']-(float)$w['start_km'];
                $rows[$k]['odometerKm']=($rows[$k]['odometerKm']??0)+max(0,$odo);
            }
        }
        foreach($rows as $row){
            if($onlyFlow!==''&&$row['flowId']!==$onlyFlow)continue;
            $midday=(new DateTimeImmutable($row['date'].' 12:00:00',$period['tz']))->getTimestamp();
            if(aims_mileage_home_at($homes,$midday,$row['flowId'])===null)$row['missingHome']=1;
            if(isset($row['odometerKm'])&&abs($row['odometerKm']-$row['actualKm'])>max(5,$row['odometerKm']*.1)){$row['gpsIssues']++;$row['notes'][]='Km-óra és GPS eltérése';}
            if($row['jobs']>0&&$row['gpsPoints']<2)$row['gpsIssues']++;
            $row['homeKm']=min($row['homeKm'],$row['actualKm']);
            $row['netKm']=max(0,$row['actualKm']-$row['homeKm']);$row['differenceKm']=$row['netKm']-$row['plannedKm'];$row['grossDifferenceKm']=$row['actualKm']-$row['plannedKm'];
            $row['costCents']=(int)round($row['actualKm']*30); // All inclusive: no second fuel/toll charge.
            $row['marginCents']=$row['missingRevenue']===0&&$row['gpsIssues']===0?$row['revenueCents']-$row['costCents']:null;
            $daily[]=$row;
        }
    }
    usort($daily,static fn($a,$b)=>[$a['date'],$a['plate'],$a['flowId']]<=>[$b['date'],$b['plate'],$b['flowId']]);
    $summary=[];
    foreach($daily as $row){
        $key=$row['plate'];if(!isset($summary[$key]))$summary[$key]=aims_mileage_row('', ['plate'=>$key,'id'=>$row['vehicleId']], '',[]);
        foreach(['actualKm','homeKm','netKm','plannedKm','differenceKm','grossDifferenceKm','revenueCents','costCents','jobs','missingKm','missingRevenue','gpsIssues','gpsPoints','unverifiedHomes','missingHome'] as $field)$summary[$key][$field]+=$row[$field];
    }
    foreach($summary as &$row)$row['marginCents']=$row['missingRevenue']===0&&$row['gpsIssues']===0?$row['revenueCents']-$row['costCents']:null;unset($row);
    return ['period'=>$period,'daily'=>$daily,'summary'=>array_values($summary),'trips'=>$trips,'jobs'=>$jobRows,'homeStatus'=>$homeStatus,'costPerKm'=>0.30];
}

function aims_mileage_csv(array $report,string $kind='daily'): string {
    require_once __DIR__.'/monthly_report_lib.php';
    if($kind==='trips'){
        $rows=[];foreach($report['trips'] as $t)$rows[]=[(string)$t['plate'],(string)$t['flowId'],$t['driverName'],$t['reference'],
          (new DateTimeImmutable('@'.$t['start']))->setTimezone($report['period']['tz'])->format('Y-m-d H:i:s'),
          (new DateTimeImmutable('@'.$t['arrival']))->setTimezone($report['period']['tz'])->format('Y-m-d H:i:s'),round($t['km'],3),round($t['periodKm'],3),$t['verified']?'IGEN':'NEM',$t['reason']];
        return aims_monthly_csv(['Rendszám','FLOW ID','Sofőr','Utolsó lerakó referenciája','Lerakó lezárása','Hazaérkezés','Teljes hazaút GPS km','Időszaki hazaút GPS km','Levonva','Állapot'],$rows);
    }
    $rows=[];foreach($report[$kind==='summary'?'summary':'daily'] as $r)$rows[]=[$r['date'],$r['plate'],$r['flowId'],$r['driverName'],round($r['plannedKm'],3),round($r['actualKm'],3),round($r['homeKm'],3),round($r['netKm'],3),round($r['grossDifferenceKm'],3),round($r['differenceKm'],3),$r['revenueCents']/100,$r['costCents']/100,$r['marginCents']===null?'':$r['marginCents']/100,$r['missingKm'],$r['missingRevenue'],$r['gpsIssues'],$r['unverifiedHomes'],$r['missingHome']];
    return aims_monthly_csv(['Nap','Rendszám','FLOW ID','Sofőr','Megbízás km','Megtett GPS km','Levonható hazaút km','Korrigált km','Bruttó eltérés km','Korrigált eltérés km','Ismert nettó bevétel EUR','GPS-alapú önköltség EUR','Árrés EUR','Hiányzó megbízás km tételek','Hiányzó bevétel tételek','GPS-ellenőrzések','Nem levont hazautak','Lakóhely-beállítás hiányzik'],$rows);
}
