<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

$type=strtolower(trim((string)($_GET['type']??'')));
$id=max(0,(int)($_GET['id']??0));
if(!in_array($type,['fuel','smart'],true)||$id<1){http_response_code(404);exit;}

$pdo=aims_db();
$dataDir=trim((string)(getenv('AIMS_TRACKING_DATA_DIR')?:''));
if($dataDir==='')$dataDir=__DIR__.'/../api/aims-tracking/data';
$base=realpath($dataDir);
if($base===false){http_response_code(404);exit;}

$path=null;
if($type==='fuel'){
  $stmt=$pdo->prepare('SELECT image_path FROM fuel_receipts WHERE id=:id LIMIT 1');
  $stmt->execute([':id'=>$id]);
  $stored=$stmt->fetchColumn();
  if($stored!==false)$path=realpath($dataDir.'/fuel/'.basename((string)$stored));
}else{
  $stmt=$pdo->prepare('SELECT image_path FROM smart_documents WHERE id=:id LIMIT 1');
  $stmt->execute([':id'=>$id]);
  $stored=$stmt->fetchColumn();
  if($stored!==false)$path=realpath($dataDir.'/'.ltrim((string)$stored,'/'));
}

if($path===false||$path===null||!str_starts_with($path,$base.DIRECTORY_SEPARATOR)||!is_file($path)){
  http_response_code(404);exit;
}

$info=@getimagesize($path);
$mime=is_array($info)?(string)($info['mime']??''):'';
if(!in_array($mime,['image/jpeg','image/png','image/webp'],true)){$mime='application/octet-stream';}
header('Content-Type: '.$mime);
header('Content-Length: '.filesize($path));
header('Cache-Control: private, no-store');
header('X-Content-Type-Options: nosniff');
readfile($path);
