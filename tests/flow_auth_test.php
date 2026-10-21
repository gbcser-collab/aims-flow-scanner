<?php
declare(strict_types=1);
require __DIR__.'/../server/aims-tracking/bootstrap.php';
require __DIR__.'/../server/aims-tracking/flow_auth.php';
function check(bool $condition, string $name): void { if (!$condition) throw new RuntimeException($name); echo "PASS $name\n"; }
function rejects(callable $fn, string $code): void {
    try { $fn(); } catch (FlowAuthError $e) { check($e->error===$code,$code); return; }
    throw new RuntimeException('Expected '.$code);
}
final class FakeControl implements FlowControlProvider {
    public array $users=[];
    public bool $offline=false;
    public function verify(string $flowId,string $pin): array {
        if ($this->offline) throw new FlowAuthError('identity_unavailable',503);
        if (!isset($this->users[$flowId]) || $pin!=='03816') throw new FlowAuthError('invalid_credentials',401);
        return $this->users[$flowId];
    }
    public function authorize(array $identity): array {
        if ($this->offline) throw new FlowAuthError('identity_unavailable',503);
        return $this->users[$identity['flowId']];
    }
}
$pdo=aims_db(); $admin=aims_ensure_default_admin($pdo); $now=gmdate(DATE_ATOM);
$q=$pdo->prepare('INSERT INTO vehicles(plate,admin_user_id,created_at) VALUES (?,?,?)');
$q->execute(['DEV9001',$admin,$now]);$v1=(int)$pdo->lastInsertId();
$q->execute(['DEV9002',$admin,$now]);$v2=(int)$pdo->lastInsertId();
$control=new FakeControl();$auth=new FlowAuth($pdo,$control);
$pdo->prepare('INSERT INTO flow_vehicle_bindings(vehicle_id,tenant_id,control_vehicle_id) VALUES (?,?,?)')->execute([$v1,'tenant-a','vehicle-a']);
$pdo->prepare('INSERT INTO flow_vehicle_bindings(vehicle_id,tenant_id,control_vehicle_id) VALUES (?,?,?)')->execute([$v2,'tenant-b','vehicle-b']);
$control->users['004271']=['subjectId'=>'driver-a','tenantId'=>'tenant-a','flowId'=>'004271',
 'assignmentId'=>'assignment-a','vehicleId'=>'vehicle-a','credentialVersion'=>'1','active'=>true,'flowEnabled'=>true,'role'=>'driver',
 'displayName'=>'Teszt Sofőr','language'=>'hu','permissions'=>['flow.jobs.read','flow.workday.write','flow.events.write','flow.push']];
$control->users['004272']=array_replace($control->users['004271'],['subjectId'=>'driver-b','tenantId'=>'tenant-b','flowId'=>'004272','assignmentId'=>'assignment-b','vehicleId'=>'vehicle-b']);
$device=str_repeat('d',64);
$payload=['flowId'=>'004271','pin'=>'03816','deviceId'=>$device];
check(FlowAuth::credentialsValid('004271','03816'),'leading zeros');
foreach ([['004271','3816'],['004271','038160'],['4271','03816'],['００４２７１','03816'],[4271,'03816'],['004271',3816],['004271',"03816\n"]] as [$id,$pin]) {
 check(!FlowAuth::credentialsValid($id,$pin),'reject malformed credential');
}
rejects(fn()=>$auth->login(array_replace($payload,['pin'=>'00000']),'ip-a'),'invalid_credentials');
$r=$auth->login($payload,'ip-a');
check($r['principal']['flowId']==='004271','server-issued principal');
check(strlen($r['accessToken'])===64 && $r['accessToken']!==$r['refreshToken'],'independent random tokens');
$i=$auth->access($r['accessToken'],$device);
$auth->authorizePayload($i,'driver_jobs.php',['plate'=>'DEV-9001']);
rejects(fn()=>$auth->authorizePayload($i,'driver_jobs.php',['plate'=>'DEV9002']),'permission_denied');
rejects(fn()=>$auth->authorizePayload($i,'vehicle_invoice.php',['plate'=>'DEV9001']),'permission_denied');
rejects(fn()=>$auth->access(str_repeat('a',64),$device),'session_expired');
rejects(fn()=>$auth->access($r['accessToken'],str_repeat('b',64)),'session_expired');
$pdo->prepare('INSERT INTO jobs(reference,vehicle_id,created_at,updated_at) VALUES (?,?,?,?)')->execute(['other-job',$v2,$now,$now]);$job=(int)$pdo->lastInsertId();
rejects(fn()=>$auth->authorizePayload($i,'driver_ops_v2.php',['plate'=>'DEV9001','jobId'=>$job]),'permission_denied');
$auth->authorizePayload($i,'driver_ops_v2.php',['plate'=>'DEV9001','workdayId'=>'stable-workday']);
$auth->authorizePayload($i,'driver_ops_v2.php',['plate'=>'DEV9001','workdayId'=>'stable-workday']);
$r2=$auth->login(array_replace($payload,['flowId'=>'004272']),'ip-b');$i2=$auth->access($r2['accessToken'],$device);
rejects(fn()=>$auth->authorizePayload($i2,'driver_ops_v2.php',['plate'=>'DEV9002','workdayId'=>'stable-workday']),'permission_denied');
$stored=$pdo->query('SELECT * FROM flow_sessions')->fetchAll(PDO::FETCH_ASSOC);
check(!str_contains(json_encode($stored),'03816') && !str_contains(json_encode($stored),$r['refreshToken']) && !str_contains(json_encode($stored),$r['accessToken']),'no PIN or raw token persisted');
$next=$auth->refresh($r['refreshToken'],$device);
check($r['refreshToken']!==$next['refreshToken'],'refresh rotates');
rejects(fn()=>$auth->access($r['accessToken'],$device),'session_expired');
rejects(fn()=>$auth->refresh($r['refreshToken'],$device),'session_expired');
rejects(fn()=>$auth->access($next['accessToken'],$device),'session_expired');
$r=$auth->login($payload,'ip-a');
$control->offline=true;
rejects(fn()=>$auth->access($r['accessToken'],$device),'identity_unavailable');
$control->offline=false;
$auth->access($r['accessToken'],$device);
$control->users['004271']['credentialVersion']='2';
rejects(fn()=>$auth->access($r['accessToken'],$device),'session_revoked');
$r=$auth->login($payload,'ip-a');
$pdo->prepare('INSERT INTO flow_push_sessions VALUES (?,?)')->execute(['fake-fcm',$r['sessionId']]);
check($auth->pushAllowed('fake-fcm',$v1),'push has live session');
$auth->logout($r['refreshToken'],$device);
check(!$auth->pushAllowed('fake-fcm',$v1),'logout revokes push');
rejects(fn()=>$auth->refresh($r['refreshToken'],$device),'session_expired');
for($n=0;$n<6;$n++) rejects(fn()=>$auth->login(['flowId'=>'999999','pin'=>'11111','deviceId'=>$device],'ip-'.$n),'invalid_credentials');
rejects(fn()=>$auth->login(['flowId'=>'999999','pin'=>'11111','deviceId'=>$device],'different-ip'),'rate_limited');
$pdo->exec('UPDATE flow_auth_limits SET reset_at=0');
$r=$auth->login($payload,'ip-a');
$control->users['004271']['flowEnabled']=false;
rejects(fn()=>$auth->access($r['accessToken'],$device),'session_revoked');
$control->users['004271']['flowEnabled']=true;
$r=$auth->login($payload,'ip-a');
$pdo->prepare('UPDATE flow_sessions SET access_expires=0 WHERE id=?')->execute([$r['sessionId']]);
rejects(fn()=>$auth->access($r['accessToken'],$device),'session_expired');
$pdo->prepare('UPDATE flow_sessions SET refresh_expires=0 WHERE id=?')->execute([$r['sessionId']]);
rejects(fn()=>$auth->refresh($r['refreshToken'],$device),'session_expired');
echo "FLOW AUTH TESTS PASSED\n";
