<?php
declare(strict_types=1);
require __DIR__.'/bootstrap.php';
$siteRoot=dirname(__DIR__,2);
require_once $siteRoot.'/inc/config.php';
require_once $siteRoot.'/inc/security.php';

function vi_portal_dir(): string { $d=aims_data_path('portal'); if(!is_dir($d))@mkdir($d,0750,true); if(!is_dir($d.'/uploads'))@mkdir($d.'/uploads',0750,true); return $d; }
function vi_read(string $name): array { $f=vi_portal_dir().'/'.$name.'.json'; if(!is_file($f))return []; $h=@fopen($f,'r');if(!$h)return [];if(!flock($h,LOCK_SH)){fclose($h);return [];} $raw=stream_get_contents($h);flock($h,LOCK_UN);fclose($h);$d=json_decode($raw?:'[]',true);return is_array($d)?$d:[]; }
function vi_update(string $name, callable $fn){ $f=vi_portal_dir().'/'.$name.'.json';if(!is_file($f))@file_put_contents($f,'[]');$h=@fopen($f,'c+');if(!$h)throw new RuntimeException('portal_store_open');if(!flock($h,LOCK_EX)){fclose($h);throw new RuntimeException('portal_store_lock');}rewind($h);$data=json_decode(stream_get_contents($h)?:'[]',true);if(!is_array($data))$data=[];$res=$fn($data);rewind($h);ftruncate($h,0);fwrite($h,json_encode(array_values($data),JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES));fflush($h);flock($h,LOCK_UN);fclose($h);@chmod($f,0640);return $res; }
function vi_id(string $p): string { return $p.bin2hex(random_bytes(8)); }
function vi_text($v,int $max=500): string { $v=trim(preg_replace('/[\x00-\x1F\x7F]/u',' ',(string)$v));return mb_substr($v,0,$max,'UTF-8'); }
function vi_find_vehicle(string $plate): ?array {
  $p=aims_normalize_plate($plate);$companies=[];foreach(vi_read('companies') as $c)$companies[$c['id']??'']=$c;
  $fallback=null;
  foreach(vi_read('vehicles') as $v){
    if(!empty($v['deleted_at'])||aims_normalize_plate((string)($v['plate']??''))!==$p)continue;
    $c=$companies[$v['company_id']??'']??null;if(!$c)continue;
    if(($c['status']??'')==='approved')return ['vehicle'=>$v,'company'=>$c];
    if($fallback===null)$fallback=['vehicle'=>$v,'company'=>$c];
  }
  return $fallback;
}
function vi_notify_partner(string $companyId,string $title,string $message,string $url,string $dedupe): void {
  vi_update('partner_notifications',function(&$rows)use($companyId,$title,$message,$url,$dedupe){
    foreach($rows as $r)if(($r['company_id']??'')===$companyId&&($r['dedupe']??'')===$dedupe&&empty($r['read_at']))return;
    $rows[]=['id'=>vi_id('ntf_'),'company_id'=>$companyId,'type'=>'invoice','title'=>$title,'message'=>$message,'url'=>$url,'dedupe'=>$dedupe,'created_at'=>date('c'),'read_at'=>''];
    if(count($rows)>2500)$rows=array_slice($rows,-2500);
  });
}

if(($_SERVER['REQUEST_METHOD']??'GET')!=='POST'){header('Allow: POST');aims_json(['ok'=>false,'error'=>'method_not_allowed'],405);}
aims_require_token('AIMS_TRACKING_TOKEN');
$data=json_decode(file_get_contents('php://input')?:'',true);if(!is_array($data))aims_json(['ok'=>false,'error'=>'invalid_json'],400);
$deviceId=vi_text($data['deviceId']??'',160);$plate=vi_text($data['plate']??'',30);if($plate==='')aims_json(['ok'=>false,'error'=>'missing_plate'],422);
$link=vi_find_vehicle($plate);if(!$link)aims_json(['ok'=>false,'error'=>'partner_vehicle_not_found'],409);
$vehicle=$link['vehicle'];$company=$link['company'];$companyId=(string)$company['id'];$vehicleId=(string)$vehicle['id'];
$image=$data['image']??null;if(!is_array($image))aims_json(['ok'=>false,'error'=>'missing_image'],422);
$bytes=base64_decode((string)($image['base64']??''),true);if($bytes===false||strlen($bytes)<60||strlen($bytes)>12*1024*1024)aims_json(['ok'=>false,'error'=>'invalid_image'],422);
$info=@getimagesizefromstring($bytes);$mime=is_array($info)?(string)($info['mime']??''):'';if(!in_array($mime,['image/jpeg','image/png','image/webp'],true))aims_json(['ok'=>false,'error'=>'unsupported_image'],422);
$ext=$mime==='image/png'?'png':($mime==='image/webp'?'webp':'jpg');

$category=(string)($data['category']??'other');if(!in_array($category,['fuel','toll_vignette','parking','service','parts','other'],true))$category='other';
$invoiceDate=trim((string)($data['invoiceDate']??''));if(!preg_match('/^20\d{2}-\d{2}-\d{2}$/',$invoiceDate))$invoiceDate=date('Y-m-d');
[$year,$month]=explode('-',substr($invoiceDate,0,7));
$safeCompany=preg_replace('/[^A-Za-z0-9_-]/','_',$companyId);$safeVehicle=preg_replace('/[^A-Za-z0-9_-]/','_',$vehicleId);
$rel='vehicle-invoices/'.$safeCompany.'/'.$safeVehicle.'/'.$year.'/'.$month;$dir=vi_portal_dir().'/uploads/'.$rel;if(!is_dir($dir)&&!@mkdir($dir,0750,true))aims_json(['ok'=>false,'error'=>'storage_dir'],500);
$stored=vi_id('app_').'.'.$ext;$dest=$dir.'/'.$stored;if(file_put_contents($dest,$bytes,LOCK_EX)===false)aims_json(['ok'=>false,'error'=>'image_write_failed'],500);@chmod($dest,0640);

$vendor=vi_text($data['vendor']??'',180);$currency=mb_strtoupper(vi_text($data['currency']??'',8),'UTF-8');$docNo=vi_text($data['documentNumber']??'',120);$note=vi_text($data['note']??'',500);$ocr=vi_text($data['ocrText']??'',40000);
$total=isset($data['totalAmount'])&&is_numeric($data['totalAmount'])?(float)$data['totalAmount']:null;$confidence=isset($data['confidence'])?(float)$data['confidence']:null;
if($note===''){ $bits=[];if($vendor!=='')$bits[]=$vendor;if($total!==null)$bits[]=rtrim(rtrim(number_format($total,2,'.',''),'0'),'.').($currency!==''?' '.$currency:'');$bits[]='AIMS Flow scanner';$note=implode(' • ',$bits); }
$invoiceId=vi_id('vinv_');$row=['id'=>$invoiceId,'company_id'=>$companyId,'vehicle_id'=>$vehicleId,'invoice_date'=>$invoiceDate,'note'=>$note,'original_name'=>'AIMS_Flow_'.$plate.'_'.$invoiceDate.'.'.$ext,'stored_path'=>$rel.'/'.$stored,'mime'=>$mime,'size'=>strlen($bytes),'source'=>'aims_flow_app','category'=>$category,'vendor'=>$vendor,'total_amount'=>$total,'currency'=>$currency,'document_number'=>$docNo,'ocr_text'=>$ocr,'recognition_confidence'=>$confidence,'captured_at'=>vi_text($data['capturedAt']??'',60),'device_id'=>$deviceId,'created_at'=>date('c')];
try{vi_update('vehicle_invoices',function(&$rows)use($row){$rows[]=$row;});}catch(Throwable $e){@unlink($dest);aims_json(['ok'=>false,'error'=>'storage_error'],500);}
vi_notify_partner($companyId,'Új számla érkezett az AIMS Flow appból',$plate.' • '.$invoiceDate.($vendor!==''?' • '.$vendor:''),'vehicle.php?id='.rawurlencode($vehicleId),'app-invoice-'.$invoiceId);
aims_audit('vehicle_invoice_upload',['actor'=>'driver_app','company_id'=>$companyId,'result'=>'ok','detail'=>$plate.' '.$invoiceDate.' '.$category]);

$vignetteId=null;
if(!empty($data['createVignette'])&&$category==='toll_vignette'){
  $country=mb_strtoupper(trim((string)($data['vignetteCountry']??'')),'UTF-8');$type=(string)($data['vignetteType']??'electronic');
  $from=(string)($data['validFrom']??'');$until=(string)($data['validUntil']??'');
  $ft=strtotime($from);$ut=strtotime($until);
  if(preg_match('/^[A-Z]{2}$/',$country)&&in_array($type,['electronic','point_of_sale'],true)&&$ft!==false&&$ut!==false&&$ut>$ft){
    $vignetteId=vi_id('vig_');$vr=['id'=>$vignetteId,'company_id'=>$companyId,'vehicle_id'=>$vehicleId,'country'=>$country,'type'=>$type,'valid_from'=>date('c',$ft),'valid_until'=>date('c',$ut),'notes'=>'AIMS Flow számlaszkenner • '.$docNo,'source'=>'aims_flow_app','invoice_id'=>$invoiceId,'reminder_days_sent'=>[],'created_at'=>date('c')];
    vi_update('vehicle_vignettes',function(&$rows)use($vr){$rows[]=$vr;});
    aims_audit('vehicle_vignette_add',['actor'=>'driver_app','company_id'=>$companyId,'result'=>'ok','detail'=>$plate.' '.$country]);
  }
}
$pdo=aims_db();$trackingVehicle=aims_vehicle_for_point($pdo,$deviceId,$plate);
if($trackingVehicle){aims_notify($pdo,(int)$trackingVehicle['admin_user_id'],(int)$trackingVehicle['id'],'vehicle_invoice','success',$plate.' számla érkezett',trim($invoiceDate.' • '.$vendor.' • '.$category),'vehicle_invoice:'.$invoiceId,['invoiceId'=>$invoiceId,'category'=>$category]);aims_try_push($pdo,8);}
aims_json(['ok'=>true,'invoiceId'=>$invoiceId,'vignetteId'=>$vignetteId]);
