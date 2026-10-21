<?php
declare(strict_types=1);
require_once __DIR__ . '/flow_control_client.php';

final class FlowAuth {
    public const ACCESS_TTL = 900;
    public const REFRESH_TTL = 2592000;
    public function __construct(private PDO $db, private FlowControlProvider $control) {
        $db->exec('PRAGMA busy_timeout=5000');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_vehicle_bindings (
            vehicle_id INTEGER PRIMARY KEY REFERENCES vehicles(id), tenant_id TEXT NOT NULL,
            control_vehicle_id TEXT NOT NULL, portal_company_id TEXT,
            UNIQUE(tenant_id,control_vehicle_id))');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_sessions (
            id TEXT PRIMARY KEY, access_hash TEXT NOT NULL UNIQUE, refresh_hash TEXT NOT NULL UNIQUE,
            identity_json TEXT NOT NULL, device_id TEXT NOT NULL,
            access_expires INTEGER NOT NULL, refresh_expires INTEGER NOT NULL,
            created_at INTEGER NOT NULL, revoked_at INTEGER)');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_used_refresh (
            token_hash TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES flow_sessions(id))');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_auth_limits (
            bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, reset_at INTEGER NOT NULL)');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_resource_owners (
            kind TEXT NOT NULL, resource_key TEXT NOT NULL, owner TEXT NOT NULL,
            PRIMARY KEY(kind,resource_key))');
        $db->exec('CREATE TABLE IF NOT EXISTS flow_push_sessions (
            fcm_token TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES flow_sessions(id))');
    }
    public static function credentialsValid(mixed $id, mixed $pin): bool {
        return is_string($id) && is_string($pin) &&
            preg_match('/\A[0-9]{6}\z/D', $id) === 1 && preg_match('/\A[0-9]{5}\z/D', $pin) === 1;
    }
    private function token(): string { return bin2hex(random_bytes(32)); }
    private function row(string $column, string $token): array {
        if (!preg_match('/\A[a-f0-9]{64}\z/D', $token)) throw new FlowAuthError('session_expired', 401);
        $q = $this->db->prepare('SELECT * FROM flow_sessions WHERE ' . $column . '=?');
        $q->execute([hash('sha256', $token)]);
        return $q->fetch(PDO::FETCH_ASSOC) ?: [];
    }
    private function checkRow(array $row, string $expiry): void {
        if (!$row || $row['revoked_at'] !== null || (int)$row[$expiry] <= time()) {
            throw new FlowAuthError('session_expired', 401);
        }
    }
    /** Reserve attempts before contacting CONTROL, atomically across PHP workers. */
    private function throttle(string $flowId, string $ip): void {
        $now = time();
        $this->db->exec('BEGIN IMMEDIATE');
        try {
            foreach ([['id:' . $flowId, 6, 900], ['ip:' . $ip, 60, 900]] as [$key, $max, $window]) {
                $bucket = hash('sha256', $key);
                $q = $this->db->prepare('SELECT count,reset_at FROM flow_auth_limits WHERE bucket=?');
                $q->execute([$bucket]); $r = $q->fetch(PDO::FETCH_ASSOC);
                if ($r && (int)$r['reset_at'] > $now && (int)$r['count'] >= $max) {
                    throw new FlowAuthError('rate_limited', 429);
                }
                $count = $r && (int)$r['reset_at'] > $now ? (int)$r['count'] + 1 : 1;
                $reset = $r && (int)$r['reset_at'] > $now ? (int)$r['reset_at'] : $now + $window;
                $q = $this->db->prepare('INSERT INTO flow_auth_limits VALUES (?,?,?)
                    ON CONFLICT(bucket) DO UPDATE SET count=excluded.count,reset_at=excluded.reset_at');
                $q->execute([$bucket, $count, $reset]);
            }
            $this->db->exec('COMMIT');
        } catch (Throwable $e) { $this->db->exec('ROLLBACK'); throw $e; }
    }
    private function identity(array $i): array {
        foreach (['subjectId', 'tenantId', 'flowId', 'assignmentId', 'vehicleId', 'credentialVersion'] as $key) {
            if (!is_string($i[$key] ?? null) || $i[$key] === '' || strlen($i[$key]) > 160) {
                throw new FlowAuthError('identity_unavailable', 503);
            }
        }
        if (!preg_match('/\A[0-9]{6}\z/D', $i['flowId']) || ($i['active'] ?? false) !== true ||
            ($i['flowEnabled'] ?? false) !== true || ($i['role'] ?? '') !== 'driver' ||
            !is_array($i['permissions'] ?? null) || !array_is_list($i['permissions'])) {
            throw new FlowAuthError('permission_denied', 403);
        }
        foreach ($i['permissions'] as $p) if (!is_string($p)) throw new FlowAuthError('identity_unavailable', 503);
        $q = $this->db->prepare('SELECT v.*,b.portal_company_id FROM flow_vehicle_bindings b
            JOIN vehicles v ON v.id=b.vehicle_id
            WHERE b.tenant_id=? AND b.control_vehicle_id=? AND v.enabled=1');
        $q->execute([$i['tenantId'], $i['vehicleId']]);
        $v = $q->fetch(PDO::FETCH_ASSOC);
        if (!$v) throw new FlowAuthError('assignment_required', 403);
        // Allowlist fields: upstream must never persist a PIN/token in identity_json.
        return [
            'subjectId'=>$i['subjectId'], 'tenantId'=>$i['tenantId'], 'flowId'=>$i['flowId'],
            'assignmentId'=>$i['assignmentId'], 'vehicleId'=>$i['vehicleId'],
            'credentialVersion'=>$i['credentialVersion'], 'permissions'=>$i['permissions'],
            'displayName'=>is_string($i['displayName'] ?? null) ? mb_substr($i['displayName'],0,100) : '',
            'language'=>in_array($i['language'] ?? '', ['hu','en','de'], true) ? $i['language'] : 'hu',
            'localVehicleId'=>(int)$v['id'], 'plate'=>(string)$v['plate'],
            'portalCompanyId'=>$v['portal_company_id'],
        ];
    }
    private function revalidate(array $row): array {
        $old = json_decode($row['identity_json'], true, 32, JSON_THROW_ON_ERROR);
        try {
            $new = $this->identity($this->control->authorize($old));
            foreach (['subjectId','tenantId','flowId','assignmentId','vehicleId','credentialVersion','localVehicleId'] as $key) {
                if ($new[$key] !== $old[$key]) throw new FlowAuthError('session_revoked', 401);
            }
            return $new;
        } catch (FlowAuthError $e) {
            if (in_array($e->status, [401,403], true)) {
                $this->db->prepare('UPDATE flow_sessions SET revoked_at=? WHERE id=?')->execute([time(),$row['id']]);
                throw new FlowAuthError('session_revoked', 401);
            }
            throw $e;
        }
    }
    private function response(array $r, array $i, string $access, string $refresh): array {
        return ['ok'=>true,'tokenType'=>'Bearer','accessToken'=>$access,'refreshToken'=>$refresh,
            'accessExpiresAt'=>gmdate(DATE_ATOM,(int)$r['access_expires']),
            'refreshExpiresAt'=>gmdate(DATE_ATOM,(int)$r['refresh_expires']),
            'sessionId'=>$r['id'], 'principal'=>['subjectId'=>$i['subjectId'],'tenantId'=>$i['tenantId'],
                'flowId'=>$i['flowId'],'role'=>'driver','displayName'=>$i['displayName'],'language'=>$i['language']],
            'assignment'=>['assignmentId'=>$i['assignmentId'],'vehicleId'=>$i['localVehicleId'],'plate'=>$i['plate']],
            'permissions'=>$i['permissions']];
    }
    public function login(array $data, string $ip): array {
        if (!self::credentialsValid($data['flowId'] ?? null, $data['pin'] ?? null) ||
            !is_string($data['deviceId'] ?? null) || !preg_match('/\A[a-f0-9]{32,64}\z/D',$data['deviceId'])) {
            throw new FlowAuthError('invalid_payload',422);
        }
        $this->throttle($data['flowId'], $ip);
        $i = $this->identity($this->control->verify($data['flowId'], $data['pin']));
        if ($i['flowId'] !== $data['flowId']) throw new FlowAuthError('identity_unavailable',503);
        $access=$this->token(); $refresh=$this->token(); $now=time();
        $r=['id'=>$this->token(),'access_expires'=>$now+self::ACCESS_TTL,'refresh_expires'=>$now+self::REFRESH_TTL];
        $q=$this->db->prepare('INSERT INTO flow_sessions
            (id,access_hash,refresh_hash,identity_json,device_id,access_expires,refresh_expires,created_at)
            VALUES (?,?,?,?,?,?,?,?)');
        $q->execute([$r['id'],hash('sha256',$access),hash('sha256',$refresh),json_encode($i,JSON_THROW_ON_ERROR),
            $data['deviceId'],$r['access_expires'],$r['refresh_expires'],$now]);
        return $this->response($r,$i,$access,$refresh);
    }
    public function access(string $token, string $device): array {
        $r=$this->row('access_hash',$token); $this->checkRow($r,'access_expires');
        if (!hash_equals($r['device_id'],$device)) throw new FlowAuthError('session_expired',401);
        $i=$this->revalidate($r);
        $i['sessionId']=$r['id']; $i['deviceId']=$r['device_id'];
        return $i;
    }
    public function refresh(string $token, string $device): array {
        $r=$this->row('refresh_hash',$token);
        if (!$r) {
            $q=$this->db->prepare('UPDATE flow_sessions SET revoked_at=? WHERE id IN
                (SELECT session_id FROM flow_used_refresh WHERE token_hash=?)');
            $q->execute([time(),hash('sha256',$token)]);
            throw new FlowAuthError('session_expired',401);
        }
        $this->checkRow($r,'refresh_expires');
        if (!hash_equals($r['device_id'],$device)) throw new FlowAuthError('session_expired',401);
        $i=$this->revalidate($r); $access=$this->token(); $refresh=$this->token();
        $r['access_expires']=min(time()+self::ACCESS_TTL,(int)$r['refresh_expires']);
        $this->db->exec('BEGIN IMMEDIATE');
        try {
            $q=$this->db->prepare('UPDATE flow_sessions SET access_hash=?,refresh_hash=?,access_expires=?,identity_json=?
                WHERE id=? AND refresh_hash=? AND revoked_at IS NULL AND refresh_expires>?');
            $q->execute([hash('sha256',$access),hash('sha256',$refresh),$r['access_expires'],json_encode($i,JSON_THROW_ON_ERROR),
                $r['id'],hash('sha256',$token),time()]);
            if ($q->rowCount() !== 1) {
                $this->db->prepare('UPDATE flow_sessions SET revoked_at=? WHERE id=?')->execute([time(),$r['id']]);
                $this->db->exec('COMMIT');
                throw new FlowAuthError('session_revoked',401);
            }
            $this->db->prepare('INSERT INTO flow_used_refresh VALUES (?,?)')->execute([hash('sha256',$token),$r['id']]);
            $this->db->exec('COMMIT');
        } catch (Throwable $e) {
            // SQLite BEGIN IMMEDIATE is issued explicitly; PDO transaction state varies by driver.
            try { $this->db->exec('ROLLBACK'); } catch (Throwable) {}
            throw $e;
        }
        return $this->response($r,$i,$access,$refresh);
    }
    public function logout(string $token, string $device): void {
        $r=$this->row('refresh_hash',$token);
        if ($r && hash_equals($r['device_id'],$device)) {
            $this->db->prepare('UPDATE flow_sessions SET revoked_at=? WHERE id=?')->execute([time(),$r['id']]);
        }
    }
    public function pushAllowed(string $fcmToken, int $vehicleId): bool {
        try {
            $q=$this->db->prepare('SELECT s.* FROM flow_sessions s JOIN flow_push_sessions p ON p.session_id=s.id WHERE p.fcm_token=?');
            $q->execute([$fcmToken]); $r=$q->fetch(PDO::FETCH_ASSOC) ?: [];
            $this->checkRow($r,'refresh_expires');
            $i=$this->revalidate($r);
            return $i['localVehicleId']===$vehicleId && in_array('flow.push',$i['permissions'],true);
        } catch (Throwable) { return false; }
    }
    public function authorizePayload(array $i, string $endpoint, array $data): void {
        $permissions=[
            'driver_jobs.php'=>'flow.jobs.read','driver_autopilot.php'=>'flow.jobs.read',
            'driver_job_ack.php'=>'flow.jobs.write','driver_stop_action.php'=>'flow.jobs.write',
            'driver_job_document.php'=>'flow.documents.write','registration_point.php'=>'flow.jobs.write',
            'driver_event.php'=>'flow.events.write','driver_messages.php'=>'flow.messages',
            'driver_rest_mode.php'=>'flow.rest','driver_push_device.php'=>'flow.push',
            'ingest.php'=>'flow.tracking.write','fuel_receipt.php'=>'flow.documents.write',
            'smart_document.php'=>'flow.documents.write','vehicle_invoice.php'=>'flow.documents.write',
            'driver_ops_v2.php'=>($data['action']??'')==='service_alerts'?'flow.vehicle.read':'flow.workday.write',
        ];
        if (!isset($permissions[$endpoint]) || !in_array($permissions[$endpoint],$i['permissions'],true)) {
            throw new FlowAuthError('permission_denied',403);
        }
        foreach (['plate','vehicleLabel'] as $key) {
            if (isset($data[$key]) && (!is_string($data[$key]) || aims_normalize_plate($data[$key]) !== $i['plate'])) {
                throw new FlowAuthError('permission_denied',403);
            }
        }
        if (isset($data['deviceId']) && $data['deviceId'] !== $i['deviceId']) {
            throw new FlowAuthError('permission_denied',403);
        }
        // DEV9 does not contain the CMR backend. Its acknowledgement must not
        // trust a client-supplied uploaded/approved flag while the bridge is absent.
        if ($endpoint==='driver_job_document.php') throw new FlowAuthError('scanner_auth_bridge_required',503);
        foreach (['jobId','stopId'] as $key) {
            if (!isset($data[$key])) continue;
            if (!is_int($data[$key]) || $data[$key]<1) throw new FlowAuthError('invalid_payload',422);
            $sql=$key==='jobId'?'SELECT vehicle_id FROM jobs WHERE id=?':
                'SELECT j.vehicle_id FROM job_stops s JOIN jobs j ON j.id=s.job_id WHERE s.id=?';
            $q=$this->db->prepare($sql); $q->execute([$data[$key]]);
            if ((int)$q->fetchColumn() !== $i['localVehicleId']) throw new FlowAuthError('permission_denied',403);
        }
        // Keep historical idempotency keys bound to their original person and assignment.
        $owner=json_encode([$i['tenantId'],$i['subjectId'],$i['assignmentId'],$i['localVehicleId']],JSON_THROW_ON_ERROR);
        $keys=['workdayId'=>'workday','eventId'=>'event','localId'=>'document'];
        if ($endpoint==='driver_ops_v2.php' && ($data['action']??'')==='safety_check') $keys['id']='safety';
        foreach ($keys as $field=>$kind) {
            if (!isset($data[$field])) continue;
            $key=$data[$field];
            if (!is_string($key) || $key==='' || strlen($key)>160) throw new FlowAuthError('invalid_payload',422);
            $q=$this->db->prepare('SELECT owner FROM flow_resource_owners WHERE kind=? AND resource_key=?');
            $q->execute([$kind,$key]);
            if ($q->fetchColumn()===false) {
                $legacy=['workday'=>['driver_workdays','workday_key'], 'safety'=>['vehicle_safety_checks','client_check_id'],
                    'event'=>['vehicle_issues','event_id'], 'document'=>['smart_documents','local_id']];
                [$table,$column]=$legacy[$kind];
                $q=$this->db->prepare('SELECT 1 FROM '.$table.' WHERE '.$column.'=? LIMIT 1'); $q->execute([$key]);
                if ($q->fetchColumn()) throw new FlowAuthError('legacy_owner_required',409);
            }
            $q=$this->db->prepare('INSERT OR IGNORE INTO flow_resource_owners VALUES (?,?,?)');
            $q->execute([$kind,$key,$owner]);
            $q=$this->db->prepare('SELECT owner FROM flow_resource_owners WHERE kind=? AND resource_key=?');
            $q->execute([$kind,$key]);
            if ($q->fetchColumn() !== $owner) throw new FlowAuthError('permission_denied',403);
        }
    }
}

function flow_auth_service(): FlowAuth { return new FlowAuth(aims_db(),new FlowControlHttpClient()); }
function flow_auth_reply_error(Throwable $e): never {
    $status=$e instanceof FlowAuthError?$e->status:503;
    if ($status===429) header('Retry-After: 900');
    aims_json(['ok'=>false,'error'=>$e instanceof FlowAuthError?$e->error:'identity_unavailable'],$status);
}
function flow_require_driver_request(): void {
    try {
        $auth=flow_auth_service();
        $i=$auth->access(aims_bearer(),(string)($_SERVER['HTTP_X_FLOW_DEVICE']??''));
        $method=$_SERVER['REQUEST_METHOD']??'GET';
        if ($method==='GET') $data=$_GET;
        elseif (str_starts_with(strtolower($_SERVER['CONTENT_TYPE']??''),'multipart/form-data')) $data=$_POST;
        else $data=json_decode(file_get_contents('php://input')?:'',true);
        if (!is_array($data)) throw new FlowAuthError('invalid_json',400);
        $auth->authorizePayload($i,basename($_SERVER['SCRIPT_NAME']??''),$data);
        $GLOBALS['flow_driver_identity']=$i;
    } catch (Throwable $e) { flow_auth_reply_error($e); }
}
