<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

if(($_SERVER['REQUEST_METHOD']??'')!=='POST'){
  http_response_code(405);exit;
}

$expected=aims_admin_csrf();
$provided=trim((string)($_POST['csrf']??''));
if($provided===''||!hash_equals($expected,$provided)){
  http_response_code(403);exit('CSRF');
}

$pdo=aims_db();
$action=trim((string)($_POST['action']??''));
$now=gmdate(DateTimeInterface::ATOM);

function flow_ops_flash(bool $ok,string $message):never{
  $_SESSION['aims_flow_ops_flash']=['ok'=>$ok,'message'=>$message];
  header('Location: aims-flow.php#flow-operations',true,303);
  exit;
}

function flow_ops_vehicle_admin(PDO $pdo,string $plate):array{
  $plate=aims_normalize_plate($plate);
  if($plate==='')flow_ops_flash(false,'Hiányzó vagy hibás rendszám.');
  $stmt=$pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate AND enabled=1 LIMIT 1');
  $stmt->execute([':plate'=>$plate]);
  $vehicle=$stmt->fetch(PDO::FETCH_ASSOC);
  if(!$vehicle)flow_ops_flash(false,'A jármű nincs regisztrálva a FLOW-ban.');
  return $vehicle;
}

function flow_ops_nullable_int(mixed $value,int $min,int $max):?int{
  $raw=trim((string)$value);
  if($raw==='')return null;
  if(!ctype_digit($raw))return null;
  $v=(int)$raw;
  return ($v>=$min&&$v<=$max)?$v:null;
}

if($action==='notifications_read_all'){
  $stmt=$pdo->prepare('UPDATE notifications SET read_at=:now WHERE read_at IS NULL');
  $stmt->execute([':now'=>$now]);
  flow_ops_flash(true,$stmt->rowCount().' értesítés olvasottnak jelölve.');
}

if($action==='notification_read'){
  $id=max(1,(int)($_POST['notification_id']??0));
  $stmt=$pdo->prepare('UPDATE notifications SET read_at=:now WHERE id=:id AND read_at IS NULL');
  $stmt->execute([':now'=>$now,':id'=>$id]);
  flow_ops_flash(true,'Teendő elolvasva.');
}

if($action==='service_save'){
  $vehicle=flow_ops_vehicle_admin($pdo,(string)($_POST['plate']??''));
  $id=max(0,(int)($_POST['service_id']??0));
  $type=preg_replace('/[^a-z0-9_-]/','',strtolower(trim((string)($_POST['service_type']??'custom'))))?:'custom';
  $title=trim((string)($_POST['title']??''));
  if($title==='')flow_ops_flash(false,'A szerviztétel neve kötelező.');
  $dueKm=flow_ops_nullable_int($_POST['due_km']??'',0,5000000);
  $dueDate=trim((string)($_POST['due_date']??''));
  if($dueDate!==''&&strtotime($dueDate)===false)flow_ops_flash(false,'Hibás esedékességi dátum.');
  $warningKm=flow_ops_nullable_int($_POST['warning_km']??'',0,500000)??2000;
  $warningDays=flow_ops_nullable_int($_POST['warning_days']??'',0,3650)??30;
  $intervalKm=flow_ops_nullable_int($_POST['interval_km']??'',1,1000000);
  $intervalDays=flow_ops_nullable_int($_POST['interval_days']??'',1,3650);
  $notes=mb_substr(trim((string)($_POST['notes']??'')),0,1000);

  if($id>0){
    $stmt=$pdo->prepare('UPDATE vehicle_service_items SET
      service_type=:type,title=:title,due_km=:due_km,due_date=:due_date,
      warning_km=:warning_km,warning_days=:warning_days,
      interval_km=:interval_km,interval_days=:interval_days,
      notes=:notes,enabled=1,updated_at=:updated
      WHERE id=:id AND vehicle_id=:vehicle');
    $stmt->execute([
      ':type'=>$type,':title'=>$title,':due_km'=>$dueKm,':due_date'=>$dueDate!==''?$dueDate:null,
      ':warning_km'=>$warningKm,':warning_days'=>$warningDays,
      ':interval_km'=>$intervalKm,':interval_days'=>$intervalDays,
      ':notes'=>$notes,':updated'=>$now,':id'=>$id,':vehicle'=>(int)$vehicle['id'],
    ]);
    if($stmt->rowCount()===0)flow_ops_flash(false,'A szerviztétel nem található ennél a járműnél.');
  }else{
    $stmt=$pdo->prepare('INSERT INTO vehicle_service_items
      (vehicle_id,service_type,title,due_km,due_date,warning_km,warning_days,
       interval_km,interval_days,notes,enabled,created_at,updated_at)
      VALUES (:vehicle,:type,:title,:due_km,:due_date,:warning_km,:warning_days,
       :interval_km,:interval_days,:notes,1,:created,:updated)');
    $stmt->execute([
      ':vehicle'=>(int)$vehicle['id'],':type'=>$type,':title'=>$title,
      ':due_km'=>$dueKm,':due_date'=>$dueDate!==''?$dueDate:null,
      ':warning_km'=>$warningKm,':warning_days'=>$warningDays,
      ':interval_km'=>$intervalKm,':interval_days'=>$intervalDays,
      ':notes'=>$notes,':created'=>$now,':updated'=>$now,
    ]);
  }
  flow_ops_flash(true,'Service Guard tétel mentve.');
}

if($action==='service_complete'){
  $id=max(1,(int)($_POST['service_id']??0));
  $completedKm=flow_ops_nullable_int($_POST['completed_km']??'',0,5000000);
  $stmt=$pdo->prepare('SELECT * FROM vehicle_service_items WHERE id=:id LIMIT 1');
  $stmt->execute([':id'=>$id]);
  $item=$stmt->fetch(PDO::FETCH_ASSOC);
  if(!$item)flow_ops_flash(false,'A szerviztétel nem található.');

  if($completedKm===null){
    $q=$pdo->prepare('SELECT km FROM vehicle_odometer_log WHERE vehicle_id=:vehicle ORDER BY captured_at DESC,id DESC LIMIT 1');
    $q->execute([':vehicle'=>(int)$item['vehicle_id']]);
    $v=$q->fetchColumn();
    $completedKm=$v===false?null:(int)$v;
  }

  $nextKm=null;
  if($completedKm!==null && $item['interval_km']!==null){
    $nextKm=$completedKm+(int)$item['interval_km'];
  }
  $nextDate=null;
  if($item['interval_days']!==null){
    $nextDate=gmdate('Y-m-d',time()+((int)$item['interval_days']*86400));
  }

  $update=$pdo->prepare('UPDATE vehicle_service_items SET
    last_done_km=:done_km,last_done_at=:done_at,due_km=:due_km,due_date=:due_date,updated_at=:updated
    WHERE id=:id');
  $update->execute([
    ':done_km'=>$completedKm,':done_at'=>$now,':due_km'=>$nextKm,
    ':due_date'=>$nextDate,':updated'=>$now,':id'=>$id,
  ]);
  flow_ops_flash(true,'Szerviz elvégezve, következő esedékesség frissítve.');
}

if($action==='issue_resolve'){
  $id=max(1,(int)($_POST['issue_id']??0));
  $note=mb_substr(trim((string)($_POST['resolved_note']??'')),0,1000);
  $stmt=$pdo->prepare('SELECT * FROM vehicle_issues WHERE id=:id LIMIT 1');
  $stmt->execute([':id'=>$id]);
  $issue=$stmt->fetch(PDO::FETCH_ASSOC);
  if(!$issue)flow_ops_flash(false,'A hibajegy nem található.');

  $update=$pdo->prepare('UPDATE vehicle_issues SET status="resolved",resolved_at=:at,resolved_note=:note WHERE id=:id');
  $update->execute([':at'=>$now,':note'=>$note,':id'=>$id]);

  if(!empty($_POST['release_hold'])){
    $count=$pdo->prepare('SELECT COUNT(*) FROM vehicle_issues WHERE vehicle_id=:vehicle AND status="open" AND urgent=1');
    $count->execute([':vehicle'=>(int)$issue['vehicle_id']]);
    if((int)$count->fetchColumn()===0){
      $release=$pdo->prepare('INSERT INTO vehicle_operational_state
        (vehicle_id,hold,hold_reason,hold_source,updated_at)
        VALUES (:vehicle,0,"","office",:updated)
        ON CONFLICT(vehicle_id) DO UPDATE SET hold=0,hold_reason="",hold_source="office",updated_at=excluded.updated_at');
      $release->execute([':vehicle'=>(int)$issue['vehicle_id'],':updated'=>$now]);
      flow_ops_flash(true,'Hibajegy lezárva és a jármű HOLD feloldva.');
    }
    flow_ops_flash(true,'Hibajegy lezárva. Másik kritikus nyitott hiba miatt a HOLD megmaradt.');
  }
  flow_ops_flash(true,'Hibajegy lezárva.');
}

if($action==='vehicle_hold'||$action==='vehicle_release'){
  $vehicle=flow_ops_vehicle_admin($pdo,(string)($_POST['plate']??''));
  $hold=$action==='vehicle_hold'?1:0;
  $reason=$hold?mb_substr(trim((string)($_POST['hold_reason']??'Irodai HOLD')),0,500):'';
  $stmt=$pdo->prepare('INSERT INTO vehicle_operational_state
    (vehicle_id,hold,hold_reason,hold_source,updated_at)
    VALUES (:vehicle,:hold,:reason,"office",:updated)
    ON CONFLICT(vehicle_id) DO UPDATE SET
      hold=excluded.hold,hold_reason=excluded.hold_reason,
      hold_source=excluded.hold_source,updated_at=excluded.updated_at');
  $stmt->execute([
    ':vehicle'=>(int)$vehicle['id'],':hold'=>$hold,':reason'=>$reason,':updated'=>$now,
  ]);
  flow_ops_flash(true,$hold?'Jármű HOLD aktiválva.':'Jármű HOLD feloldva.');
}

flow_ops_flash(false,'Ismeretlen FLOW művelet.');
