<?php
declare(strict_types=1);

final class AimsSafetyCheckError extends RuntimeException {
    public function __construct(string $error, public readonly int $httpStatus=422) {
        parent::__construct($error);
    }
}

/** Validate a full snapshot before writing. Caller supplies authenticated owner. */
function aims_store_safety_check(PDO $pdo,array $vehicle,array $data,array $uploads,string $flowId,string $now):array {
    $clientId=trim((string)($data['id']??''));
    if (preg_match('/^[A-Za-z0-9._:-]{1,180}$/D',$clientId)!==1) throw new AimsSafetyCheckError('invalid_check_id');
    $km=filter_var($data['km']??null,FILTER_VALIDATE_INT,['options'=>['min_range'=>0,'max_range'=>5000000]]);
    if ($km===false || $km===null) throw new AimsSafetyCheckError('invalid_km');
    $time=strtotime((string)($data['createdAt']??''));
    if ($time===false) throw new AimsSafetyCheckError('invalid_created_at');
    $created=gmdate(DateTimeInterface::ATOM,$time);
    $statuses=json_decode((string)($data['statuses']??''),true);
    $checks=['coolant','oil','steering','tires'];
    if (!is_array($statuses)) throw new AimsSafetyCheckError('invalid_statuses');
    ksort($statuses);
    if (array_keys($statuses)!==$checks) throw new AimsSafetyCheckError('invalid_statuses');
    foreach ($statuses as $value) {
        if (!is_string($value) || !in_array($value,['ok','problem'],true)) throw new AimsSafetyCheckError('invalid_statuses');
    }
    $statusesJson=json_encode($statuses,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR);
    $hasProblem=in_array('problem',$statuses,true);
    $vehicleId=(int)$vehicle['id'];
    $required=['oil','coolant','tires','odometer'];
    $photos=[];
    $finfo=new finfo(FILEINFO_MIME_TYPE);
    foreach ($required as $kind) {
        $file=$uploads['photo_'.$kind]??null;
        if (!is_array($file) || (int)($file['error']??UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK) {
            throw new AimsSafetyCheckError('missing_photo_'.$kind);
        }
        $tmp=(string)($file['tmp_name']??'');
        if (!is_uploaded_file($tmp)) throw new AimsSafetyCheckError('invalid_upload_'.$kind);
        $size=filesize($tmp);
        if ($size===false || $size<1 || $size>8*1024*1024) throw new AimsSafetyCheckError('photo_size_'.$kind);
        $mime=(string)$finfo->file($tmp);
        $ext=match($mime){'image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp',default=>''};
        if ($ext==='' || @getimagesize($tmp)===false) throw new AimsSafetyCheckError('photo_type_'.$kind);
        $hash=hash_file('sha256',$tmp);
        if (!is_string($hash)) throw new AimsSafetyCheckError('photo_read_'.$kind,503);
        $photos[$kind]=['tmp'=>$tmp,'size'=>$size,'mime'=>$mime,'ext'=>$ext,'hash'=>$hash];
    }

    $root=flow_ops_data_dir();
    $newFiles=[];
    $pdo->beginTransaction();
    try {
        $query=$pdo->prepare('SELECT * FROM vehicle_safety_checks WHERE client_check_id=:id');
        $query->execute([':id'=>$clientId]);
        $existing=$query->fetch(PDO::FETCH_ASSOC);
        $new=$existing===false;
        if (!$new) {
            if ((int)$existing['vehicle_id']!==$vehicleId) throw new AimsSafetyCheckError('safety_id_conflict',409);
            $owner=(string)($existing['flow_id']??'');
            if ($owner!=='' && !hash_equals($owner,$flowId)) throw new AimsSafetyCheckError('safety_owner_forbidden',403);
            $oldStatuses=json_decode((string)$existing['statuses_json'],true);
            if (is_array($oldStatuses)) ksort($oldStatuses);
            if ((int)$existing['km']!==$km || strtotime((string)$existing['created_at'])!==$time || $oldStatuses!==$statuses) {
                throw new AimsSafetyCheckError('safety_snapshot_conflict',409);
            }
            $q=$pdo->prepare('SELECT * FROM vehicle_safety_photos WHERE safety_check_id=:id');
            $q->execute([':id'=>(int)$existing['id']]);
            $oldPhotos=[];
            foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $photo) $oldPhotos[(string)$photo['photo_type']]=$photo;
            // Legacy partial uploads have no trustworthy complete snapshot.
            if (count($oldPhotos)!==4) throw new AimsSafetyCheckError('safety_legacy_incomplete',409);
            foreach ($photos as $kind=>$photo) {
                if (!isset($oldPhotos[$kind])) throw new AimsSafetyCheckError('safety_legacy_incomplete',409);
                $old=$oldPhotos[$kind];
                $path=$root.'/'.(string)$old['relative_path'];
                $hash=is_file($path) ? hash_file('sha256',$path) : false;
                if (!is_string($hash)) throw new AimsSafetyCheckError('safety_photo_unavailable',503);
                if (!hash_equals($hash,$photo['hash'])) throw new AimsSafetyCheckError('safety_photo_conflict',409);
            }
            $checkId=(int)$existing['id'];
            $received=(string)$existing['received_at'];
        } else {
            $pdo->prepare('INSERT INTO vehicle_safety_checks
                (client_check_id,vehicle_id,flow_id,km,statuses_json,has_problem,created_at,received_at)
                VALUES (:id,:vehicle,:owner,:km,:statuses,:problem,:created,:received)')->execute([
                    ':id'=>$clientId,':vehicle'=>$vehicleId,':owner'=>$flowId,':km'=>$km,
                    ':statuses'=>$statusesJson,':problem'=>$hasProblem?1:0,':created'=>$created,':received'=>$now,
                ]);
            $checkId=(int)$pdo->lastInsertId();
            $base=$root.'/safety/'.$vehicleId;
            if (!is_dir($base) && !@mkdir($base,0700,true) && !is_dir($base)) {
                throw new AimsSafetyCheckError('safety_storage_unavailable',503);
            }
            foreach ($photos as $kind=>$photo) {
                // Hash the original ID, so ':' and '_' can never collide.
                $filename=hash('sha256',$clientId).'_'.$kind.'_'.$photo['hash'].'.'.$photo['ext'];
                $target=$base.'/'.$filename;
                if (is_file($target)) {
                    if (!hash_equals($photo['hash'],(string)hash_file('sha256',$target))) {
                        throw new AimsSafetyCheckError('safety_storage_conflict',503);
                    }
                } else {
                    if (!@move_uploaded_file($photo['tmp'],$target)) throw new AimsSafetyCheckError('photo_store_'.$kind,503);
                    $newFiles[]=$target;
                    @chmod($target,0600);
                }
                $pdo->prepare('INSERT INTO vehicle_safety_photos
                    (safety_check_id,photo_type,relative_path,mime_type,size_bytes,created_at)
                    VALUES (:check,:type,:path,:mime,:size,:created)')->execute([
                        ':check'=>$checkId,':type'=>$kind,':path'=>'safety/'.$vehicleId.'/'.$filename,
                        ':mime'=>$photo['mime'],':size'=>$photo['size'],':created'=>$now,
                    ]);
            }
            $pdo->prepare('INSERT INTO vehicle_odometer_log(vehicle_id,km,source,captured_at,created_at)
                VALUES (:vehicle,:km,"safety_check",:captured,:created)')->execute([
                    ':vehicle'=>$vehicleId,':km'=>$km,':captured'=>$created,':created'=>$now,
                ]);
            if ($hasProblem) {
                $name=trim((string)$vehicle['label'])!=='' ? (string)$vehicle['label'] : (string)$vehicle['plate'];
                aims_notify($pdo,(int)$vehicle['admin_user_id'],$vehicleId,'safety_check_problem','warning',
                    $name.' · Safety Check probléma','A sofőr problémát jelölt a járműellenőrzésen.',
                    'safety_check_problem:'.$checkId,
                    ['safetyCheckId'=>$checkId,'plate'=>(string)$vehicle['plate'],'km'=>$km]);
            }
            $received=$now;
        }
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        foreach ($newFiles as $path) @unlink($path);
        throw $error;
    }
    if ($new && $hasProblem) aims_try_push($pdo,8);
    return ['ok'=>true,'safetyCheckId'=>$checkId,'clientCheckId'=>$clientId,
        'hasProblem'=>$hasProblem,'storedPhotos'=>$required,'receivedAt'=>$received];
}
