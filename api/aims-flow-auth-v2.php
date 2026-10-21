<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
require_once __DIR__.'/../inc/portal.php';
require_once __DIR__.'/aims-tracking/bootstrap.php';
require_once __DIR__.'/aims-tracking/driver_auth_v2.php';

aims_security_headers(true);
header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');

function flow_auth_v2_reply(array $payload, int $status = 200): never {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    flow_auth_v2_reply(['ok' => false, 'error' => 'method_not_allowed'], 405);
}

$data = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($data)) flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_json'], 400);

$action = strtolower(trim((string)($data['action'] ?? 'login')));
$pdo = aims_db();
aims_driver_auth_schema($pdo);

if ($action === 'login') {
    $flowId = preg_replace('/\D/', '', (string)($data['flowId'] ?? '')) ?: '';
    $pin = preg_replace('/\D/', '', (string)($data['pin'] ?? '')) ?: '';
    $deviceId = trim((string)($data['deviceId'] ?? ''));

    if (!aims_driver_flow_id_valid($flowId) ||
        !aims_driver_pin_valid($pin) ||
        strlen($deviceId) < 16 || strlen($deviceId) > 200) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_credentials'], 401);
    }

    $rateKey = aims_client_ip().'|'.$flowId;
    $rate = aims_rate_limit('flow-id-pin-login', $rateKey, 7, 900, false);
    if (!$rate['allowed']) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'rate_limited'], 429);
    }

    $account = aims_driver_find_account($pdo, $flowId);
    $valid = $account &&
        ((int)($account['enabled'] ?? 0)) === 1 &&
        password_verify($pin, (string)$account['pin_hash']);

    if (!$valid) {
        aims_rate_limit('flow-id-pin-login', $rateKey, 7, 900, true);
        usleep(250000);
        flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_credentials'], 401);
    }

    aims_rate_limit_clear('flow-id-pin-login', $rateKey);
    $session = aims_driver_issue_session($pdo, (int)$account['id'], $deviceId, 90);
    $now = gmdate(DateTimeInterface::ATOM);
    $pdo->prepare('UPDATE driver_accounts SET last_login_at=:now,updated_at=:now WHERE id=:id')
        ->execute([':now' => $now, ':id' => (int)$account['id']]);

    $fresh = aims_driver_find_account($pdo, $flowId) ?? $account;
    aims_audit('flow_id_pin_login', [
        'actor' => 'driver',
        'detail' => $flowId,
        'result' => 'ok',
    ]);

    flow_auth_v2_reply([
        'ok' => true,
        'role' => 'driver',
        'sessionToken' => $session['token'],
        'sessionExpiresAt' => $session['expiresAt'],
        'profile' => aims_driver_account_payload($pdo, $fresh),
    ]);
}

if ($action === 'validate') {
    $session = aims_require_driver_session($pdo);
    flow_auth_v2_reply([
        'ok' => true,
        'sessionExpiresAt' => (string)$session['expires_at'],
        'profile' => aims_driver_account_payload($pdo, $session),
    ]);
}

if ($action === 'onboarding') {
    $session = aims_require_driver_session($pdo);
    $name = trim((string)($data['driverName'] ?? ''));
    $plate = aims_normalize_plate((string)($data['plate'] ?? ''));
    $currentKm = filter_var($data['currentKm'] ?? null, FILTER_VALIDATE_INT);

    if (mb_strlen($name, 'UTF-8') < 2 || mb_strlen($name, 'UTF-8') > 80) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_driver_name'], 422);
    }
    if ($plate === '' || strlen($plate) < 4 || strlen($plate) > 16) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_plate'], 422);
    }
    if ($currentKm === false || $currentKm < 0 || $currentKm > 5000000) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'invalid_odometer'], 422);
    }

    $accountId = (int)$session['account_id'];
    $assignedVehicleId = (int)($session['vehicle_id'] ?? 0);
    $existingPlate = aims_normalize_plate((string)($session['plate'] ?? ''));
    if ($assignedVehicleId > 0 && $existingPlate !== '' && !hash_equals($existingPlate, $plate)) {
        flow_auth_v2_reply(['ok' => false, 'error' => 'vehicle_already_assigned'], 409);
    }

    $pdo->beginTransaction();
    try {
        $vehicleQuery = $pdo->prepare('SELECT * FROM vehicles WHERE plate=:plate LIMIT 1');
        $vehicleQuery->execute([':plate' => $plate]);
        $vehicle = $vehicleQuery->fetch(PDO::FETCH_ASSOC);

        if (!$vehicle) {
            $adminId = aims_ensure_default_admin($pdo);
            $insertVehicle = $pdo->prepare('INSERT INTO vehicles
                (plate,label,admin_user_id,enabled,created_at)
                VALUES (:plate,:label,:admin,1,:created)');
            $insertVehicle->execute([
                ':plate' => $plate,
                ':label' => $plate,
                ':admin' => $adminId,
                ':created' => gmdate(DateTimeInterface::ATOM),
            ]);
            $vehicleId = (int)$pdo->lastInsertId();
        } else {
            if (((int)$vehicle['enabled']) !== 1) {
                throw new RuntimeException('vehicle_disabled');
            }
            $vehicleId = (int)$vehicle['id'];
        }

        // One active driver account per vehicle. This avoids two colleagues
        // silently claiming the same truck at the same time.
        $conflict = $pdo->prepare('SELECT id FROM driver_accounts
            WHERE vehicle_id=:vehicle AND id<>:account AND enabled=1 LIMIT 1');
        $conflict->execute([':vehicle' => $vehicleId, ':account' => $accountId]);
        if ($conflict->fetchColumn() !== false) {
            throw new RuntimeException('vehicle_assigned_to_other_driver');
        }

        $now = gmdate(DateTimeInterface::ATOM);
        $update = $pdo->prepare('UPDATE driver_accounts SET
            driver_name=:name,vehicle_id=:vehicle,onboarding_complete=1,updated_at=:updated
            WHERE id=:account');
        $update->execute([
            ':name' => $name,
            ':vehicle' => $vehicleId,
            ':updated' => $now,
            ':account' => $accountId,
        ]);

        $odo = $pdo->prepare('INSERT INTO vehicle_odometer_log
            (vehicle_id,km,source,captured_at,created_at)
            VALUES (:vehicle,:km,"driver_onboarding",:captured,:created)');
        $odo->execute([
            ':vehicle' => $vehicleId,
            ':km' => $currentKm,
            ':captured' => $now,
            ':created' => $now,
        ]);
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        $code = $error->getMessage();
        if (in_array($code, ['vehicle_disabled', 'vehicle_assigned_to_other_driver'], true)) {
            flow_auth_v2_reply(['ok' => false, 'error' => $code], 409);
        }
        throw $error;
    }

    $fresh = aims_driver_find_account($pdo, (string)$session['flow_id']);
    if (!$fresh) flow_auth_v2_reply(['ok' => false, 'error' => 'account_not_found'], 404);

    aims_audit('flow_driver_onboarding', [
        'actor' => 'driver',
        'detail' => (string)$session['flow_id'].'|'.$plate,
        'result' => 'ok',
    ]);
    flow_auth_v2_reply([
        'ok' => true,
        'sessionExpiresAt' => (string)$session['expires_at'],
        'profile' => aims_driver_account_payload($pdo, $fresh),
    ]);
}

if ($action === 'logout') {
    $token = aims_bearer();
    aims_driver_revoke_session($pdo, $token);
    flow_auth_v2_reply(['ok' => true]);
}

flow_auth_v2_reply(['ok' => false, 'error' => 'unsupported_action'], 422);
