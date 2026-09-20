<?php
declare(strict_types=1);
require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();
if(($_SERVER['REQUEST_METHOD']??'')!=='POST'){http_response_code(405);exit('POST only');}
if(!aims_check_admin_csrf($_POST['csrf']??'')){http_response_code(403);exit('Érvénytelen munkamenet.');}
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';
$pdo=aims_db();
$plate=aims_normalize_plate((string)($_POST['plate']??''));
$reference=trim((string)($_POST['reference']??''));
$pickupCompany=trim((string)($_POST['pickup_company']??''));
$pickupAddress=trim((string)($_POST['pickup_address']??''));
$pickupPhone=trim((string)($_POST['pickup_phone']??''));
$deliveryCompany=trim((string)($_POST['delivery_company']??''));
$deliveryAddress=trim((string)($_POST['delivery_address']??''));
$deliveryPhone=trim((string)($_POST['delivery_phone']??''));
$partial=!empty($_POST['partial_load']);
$flash=['ok'=>false,'message'=>''];
try{
  if($plate===''||$reference===''||$pickupAddress===''||$deliveryAddress==='')throw new RuntimeException('Rendszám, referencia, felrakó és lerakó kötelező.');
  $q=$pdo->prepare('SELECT id FROM vehicles WHERE plate=:plate LIMIT 1');
  $q->execute([':plate'=>$plate]);$vehicleId=$q->fetchColumn();
  if($vehicleId===false){
    $adminId=aims_ensure_default_admin($pdo);
    $ins=$pdo->prepare('INSERT INTO vehicles (plate,label,device_id,admin_user_id,enabled,created_at) VALUES (:plate,:label,NULL,:admin,1,:created)');
    $ins->execute([':plate'=>$plate,':label'=>$plate,':admin'=>$adminId,':created'=>gmdate(DateTimeInterface::ATOM)]);
    $vehicleId=(int)$pdo->lastInsertId();
  }  $adminToken=(string)(getenv('AIMS_ADMIN_TRACKING_TOKEN')?:'');
  if($adminToken==='')throw new RuntimeException('Az admin Flow-kulcs nincs konfigurálva.');
  $payload=['plate'=>$plate,'driverJob'=>[
    'reference'=>$reference,'partialLoad'=>$partial,
    'pickups'=>[['company'=>$pickupCompany,'address'=>$pickupAddress,'contactPhone'=>$pickupPhone]],
    'deliveries'=>[['company'=>$deliveryCompany,'address'=>$deliveryAddress,'contactPhone'=>$deliveryPhone]],
  ]];
  $ch=curl_init('https://logistic-aims.hu/api/aims-tracking/job_assign.php');
  curl_setopt_array($ch,[
    CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>4,CURLOPT_TIMEOUT=>15,
    CURLOPT_HTTPHEADER=>['Accept: application/json','Content-Type: application/json','Authorization: Bearer '.$adminToken],
  ]);
  $body=curl_exec($ch);$status=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);$curlError=curl_error($ch);curl_close($ch);
  $json=is_string($body)?json_decode($body,true):null;
  if($status<200||$status>=300||!is_array($json)||empty($json['ok'])){
    $why=is_array($json)?($json['error']??'ismeretlen_hiba'):($curlError?:'érvénytelen válasz');
    throw new RuntimeException('Flow küldési hiba: '.$why.' (HTTP '.$status.')');
  }
  $push=$json['driverPush']??[];
  $sent=(int)($push['sent']??0);$failed=(int)($push['failed']??0);
  $flash=['ok'=>true,'message'=>'Fuvar elküldve a Flow-ba: '.$reference.' • '.$plate.' • push elküldve: '.$sent.($failed?' • sikertelen: '.$failed:''),
    'jobId'=>(int)($json['jobId']??0),'sent'=>$sent,'failed'=>$failed];
}catch(Throwable $e){
  $flash=['ok'=>false,'message'=>$e->getMessage()];
}
$_SESSION['aims_flow_dispatch_flash']=$flash;
header('Location: aims-flow.php');
exit;
