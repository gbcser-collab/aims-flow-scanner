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
$customerName=trim((string)($_POST['customer_name']??''));
$customerEmail=trim((string)($_POST['customer_email']??''));
$pickupCompany=trim((string)($_POST['pickup_company']??''));
$pickupAddress=trim((string)($_POST['pickup_address']??''));
$pickupPhone=trim((string)($_POST['pickup_phone']??''));
$deliveryCompany=trim((string)($_POST['delivery_company']??''));
$deliveryAddress=trim((string)($_POST['delivery_address']??''));
$deliveryPhone=trim((string)($_POST['delivery_phone']??''));
$pickupTime=trim((string)($_POST['pickup_time']??''));
$pickupLatestTime=trim((string)($_POST['pickup_latest_time']??''));
$deliveryTime=trim((string)($_POST['delivery_time']??''));
$cargo=trim((string)($_POST['cargo']??''));
$weightKg=trim((string)($_POST['weight_kg']??''));
$dimensions=trim((string)($_POST['dimensions']??''));
$packageCount=trim((string)($_POST['package_count']??''));
$vehicleRequirement=trim((string)($_POST['vehicle_requirement']??''));
$pickupReference=trim((string)($_POST['pickup_reference']??''));
$deliveryReference=trim((string)($_POST['delivery_reference']??''));
$sourceOrderId=trim((string)($_POST['source_order_id']??''));
$collectStops=function($companies,$addresses,$phones,$label){
  $companies=is_array($companies)?$companies:[];
  $addresses=is_array($addresses)?$addresses:[];
  $phones=is_array($phones)?$phones:[];
  $count=min(10,max(count($companies),count($addresses),count($phones)));
  $rows=[];
  for($i=0;$i<$count;$i++){
    $company=trim((string)($companies[$i]??''));
    $address=trim((string)($addresses[$i]??''));
    $phone=trim((string)($phones[$i]??''));
    if($company===''&&$address===''&&$phone==='')continue;
    if($address==='')throw new RuntimeException($label.' '.($i+2).'. pontnál a pontos cím kötelező.');
    $rows[]=['company'=>$company,'address'=>$address,'contactPhone'=>$phone];
  }
  return $rows;
};
$extraPickups=$collectStops($_POST['extra_pickup_company']??[],$_POST['extra_pickup_address']??[],$_POST['extra_pickup_phone']??[],'Felrakó');
$extraDeliveries=$collectStops($_POST['extra_delivery_company']??[],$_POST['extra_delivery_address']??[],$_POST['extra_delivery_phone']??[],'Lerakó');
$partial=!empty($_POST['partial_load'])||!empty($extraPickups)||!empty($extraDeliveries);
$pickups=array_merge([['company'=>$pickupCompany,'address'=>$pickupAddress,'contactPhone'=>$pickupPhone]],$extraPickups);
$deliveries=array_merge([['company'=>$deliveryCompany,'address'=>$deliveryAddress,'contactPhone'=>$deliveryPhone]],$extraDeliveries);
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
  if($customerEmail!==''&&!filter_var($customerEmail,FILTER_VALIDATE_EMAIL))throw new RuntimeException('A megbízó e-mail-címe hibás.');
  $orderData=array_filter([
    'customer'=>$customerName,
    'customer_name'=>$customerName,
    'customer_email'=>$customerEmail,
    'pickup_time'=>$pickupTime,
    'pickup_latest_time'=>$pickupLatestTime,
    'delivery_time'=>$deliveryTime,
    'cargo'=>$cargo,
    'weight_kg'=>$weightKg,
    'dimensions'=>$dimensions,
    'package_count'=>$packageCount,
    'vehicle_requirement'=>$vehicleRequirement,
    'pickup_reference'=>$pickupReference,
    'delivery_reference'=>$deliveryReference,
  ],static fn($v)=>trim((string)$v)!=='');
  $payload=['plate'=>$plate,'billing'=>['planned_km'=>(string)($_POST['planned_km']??''),'revenue_eur'=>(string)($_POST['revenue_eur']??'')],'driverJob'=>[
    'reference'=>$reference,'partialLoad'=>$partial,
    'sourceOrderId'=>$sourceOrderId,
    'orderData'=>$orderData,
    'operationsConfig'=>[
      'customerStatusMode'=>'off',
      'customerStatusEmail'=>'',
      'customerStatusLanguage'=>'hu',
    ],
    'pickups'=>$pickups,
    'deliveries'=>$deliveries,
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
    throw new RuntimeException('Flow-küldési hiba: '.$why.' (HTTP '.$status.')');
  }
  $push=$json['driverPush']??[];
  $sent=(int)($push['sent']??0);$failed=(int)($push['failed']??0);
  $stopCount=count($pickups)+count($deliveries);
  $flash=['ok'=>true,'message'=>'Fuvar elküldve a Flow-ba: '.$reference.' • '.$plate.' • '.$stopCount.' stop'.($partial?' • részrakomány':'').' • push elküldve: '.$sent.($failed?' • sikertelen: '.$failed:''),
    'jobId'=>(int)($json['jobId']??0),'sent'=>$sent,'failed'=>$failed];
}catch(Throwable $e){
  $flash=['ok'=>false,'message'=>$e->getMessage()];
}
$_SESSION['aims_flow_dispatch_flash']=$flash;
header('Location: aims-flow.php');
exit;
