<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
require_once __DIR__.'/../api/aims-tracking/bootstrap.php';

$id=max(0,(int)($_GET['id']??0));
if($id<1){http_response_code(404);exit;}

$pdo=aims_db();
$stmt=$pdo->prepare('SELECT p.relative_path,p.mime_type,p.size_bytes
  FROM vehicle_safety_photos p
  JOIN vehicle_safety_checks c ON c.id=p.safety_check_id
  WHERE p.id=:id LIMIT 1');
$stmt->execute([':id'=>$id]);
$row=$stmt->fetch(PDO::FETCH_ASSOC);
if(!$row){http_response_code(404);exit;}

$dataDir=trim((string)(getenv('AIMS_TRACKING_DATA_DIR')?:''));
if($dataDir==='')$dataDir=__DIR__.'/../api/aims-tracking/data';
$base=realpath($dataDir);
$path=realpath($dataDir.'/'.ltrim((string)$row['relative_path'],'/'));

if($base===false||$path===false||!str_starts_with($path,$base.DIRECTORY_SEPARATOR)||!is_file($path)){
  http_response_code(404);exit;
}

$mime=(string)$row['mime_type'];
if(!in_array($mime,['image/jpeg','image/png','image/webp'],true))$mime='application/octet-stream';
header('Content-Type: '.$mime);
header('Content-Length: '.filesize($path));
header('Cache-Control: private, max-age=300');
header('X-Content-Type-Options: nosniff');
readfile($path);
