<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

$pdo=aims_db();
$type=preg_replace('/[^a-z0-9_-]/','',strtolower(trim((string)($_GET['type']??'')))) ?: '';
$allowed=['workdays','odometer','safety','issues','service','jobs','activity'];
if(!in_array($type,$allowed,true)){http_response_code(404);exit;}

header('Content-Type: text/csv; charset=UTF-8');
header('Content-Disposition: attachment; filename="aims-flow-'.$type.'-'.gmdate('Ymd-His').'.csv"');
header('Cache-Control: no-store');
echo "\xEF\xBB\xBF";
$out=fopen('php://output','wb');
if(!$out)exit;

function csv_rows($out,array $header,array $rows):void{
    fputcsv($out,$header,';');
    foreach($rows as $row)fputcsv($out,$row,';');
}

if($type==='workdays'){
    $q=$pdo->query('SELECT v.plate,j.reference,w.started_at,w.finished_at,w.start_km,w.end_km,
      CASE WHEN w.end_km IS NULL THEN NULL ELSE w.end_km-w.start_km END distance_km
      FROM driver_workdays w JOIN vehicles v ON v.id=w.vehicle_id
      LEFT JOIN jobs j ON j.id=w.start_job_id ORDER BY w.started_at DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['plate'],$r['reference'],$r['started_at'],$r['finished_at'],$r['start_km'],$r['end_km'],$r['distance_km']
    ];
    csv_rows($out,['Rendszám','Fuvar','Kezdés','Vége','Kezdő km','Záró km','Nap km'],$rows);exit;
}

if($type==='odometer'){
    $q=$pdo->query('SELECT v.plate,o.km,o.source,o.captured_at,o.created_at
      FROM vehicle_odometer_log o JOIN vehicles v ON v.id=o.vehicle_id
      ORDER BY o.captured_at DESC,o.id DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['plate'],$r['km'],$r['source'],$r['captured_at'],$r['created_at']
    ];
    csv_rows($out,['Rendszám','Km','Forrás','Rögzítve','Szerveridő'],$rows);exit;
}

if($type==='safety'){
    $q=$pdo->query('SELECT v.plate,c.km,c.has_problem,c.statuses_json,c.created_at,c.received_at
      FROM vehicle_safety_checks c JOIN vehicles v ON v.id=c.vehicle_id
      ORDER BY c.created_at DESC,c.id DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['plate'],$r['km'],(int)$r['has_problem']===1?'PROBLÉMA':'RENDBEN',
      $r['statuses_json'],$r['created_at'],$r['received_at']
    ];
    csv_rows($out,['Rendszám','Km','Eredmény','Checklist','Sofőr idő','Szerver idő'],$rows);exit;
}

if($type==='issues'){
    $q=$pdo->query('SELECT v.plate,i.category,i.message,i.urgent,i.status,i.created_at,i.resolved_at,i.resolved_note
      FROM vehicle_issues i JOIN vehicles v ON v.id=i.vehicle_id
      ORDER BY i.created_at DESC,i.id DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['plate'],$r['category'],$r['message'],(int)$r['urgent']===1?'KRITIKUS':'NORMÁL',
      $r['status'],$r['created_at'],$r['resolved_at'],$r['resolved_note']
    ];
    csv_rows($out,['Rendszám','Kategória','Üzenet','Súlyosság','Állapot','Nyitva','Lezárva','Megoldás'],$rows);exit;
}

if($type==='service'){
    $q=$pdo->query('SELECT v.plate,s.service_type,s.title,s.due_km,s.due_date,s.warning_km,s.warning_days,
      s.interval_km,s.interval_days,s.last_done_km,s.last_done_at,s.notes,s.enabled
      FROM vehicle_service_items s JOIN vehicles v ON v.id=s.vehicle_id
      ORDER BY v.plate,s.id');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['plate'],$r['service_type'],$r['title'],$r['due_km'],$r['due_date'],$r['warning_km'],$r['warning_days'],
      $r['interval_km'],$r['interval_days'],$r['last_done_km'],$r['last_done_at'],$r['notes'],$r['enabled']
    ];
    csv_rows($out,['Rendszám','Típus','Tétel','Esedékes km','Esedékes dátum','Figyelmeztetés km','Figyelmeztetés nap',
      'Intervallum km','Intervallum nap','Utolsó km','Utolsó dátum','Megjegyzés','Aktív'],$rows);exit;
}

if($type==='jobs'){
    $q=$pdo->query('SELECT j.reference,v.plate,j.status,j.driver_seen_at,j.driver_accepted_at,
      j.document_received_at,j.document_sync_state,j.created_at,j.updated_at
      FROM jobs j JOIN vehicles v ON v.id=j.vehicle_id
      WHERE j.status<>"deleted" ORDER BY j.updated_at DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['reference'],$r['plate'],$r['status'],$r['driver_seen_at'],$r['driver_accepted_at'],
      $r['document_received_at'],$r['document_sync_state'],$r['created_at'],$r['updated_at']
    ];
    csv_rows($out,['Fuvar','Rendszám','Állapot','Látta','Elfogadta','Dokumentum','Dokumentum állapot','Létrehozva','Frissítve'],$rows);exit;
}

if($type==='activity'){
    $q=$pdo->query('SELECT n.id,n.type,n.severity,n.title,n.body,v.plate,n.created_at,n.read_at
      FROM notifications n LEFT JOIN vehicles v ON v.id=n.vehicle_id
      ORDER BY n.id DESC');
    $rows=[];foreach($q->fetchAll(PDO::FETCH_ASSOC) as $r)$rows[]=[
      $r['id'],$r['type'],$r['severity'],$r['title'],$r['body'],$r['plate'],$r['created_at'],$r['read_at']
    ];
    csv_rows($out,['ID','Típus','Súlyosság','Cím','Leírás','Rendszám','Idő','Olvasva'],$rows);exit;
}
