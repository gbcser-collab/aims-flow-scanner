<?php
declare(strict_types=1);

require_once __DIR__.'/../inc/analytics.php';
aims_require_admin();
aims_start_session();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    exit('POST only');
}
if (!aims_check_admin_csrf($_POST['csrf'] ?? '')) {
    http_response_code(403);
    exit('Érvénytelen munkamenet.');
}

require_once __DIR__.'/../api/aims-tracking/bootstrap.php';
require_once __DIR__.'/../inc/portal.php';

$pdo = aims_db();
$jobId = (int)($_POST['job_id'] ?? 0);
$action = strtolower(trim((string)($_POST['action'] ?? 'create')));
$sendEmail = !empty($_POST['send_email']);
$expiresHours = max(1, min(720, (int)($_POST['expires_hours'] ?? 336)));

if ($jobId < 1 || !in_array($action, ['create','revoke'], true)) {
    $_SESSION['aims_flow_dispatch_flash'] = ['ok'=>false,'message'=>'Érvénytelen megbízói link művelet.'];
    header('Location: aims-flow.php');
    exit;
}

$stmt = $pdo->prepare('SELECT j.*, v.plate, v.label
    FROM jobs j
    JOIN vehicles v ON v.id = j.vehicle_id
    WHERE j.id = :job AND COALESCE(j.status, "") <> "deleted"
    LIMIT 1');
$stmt->execute([':job'=>$jobId]);
$job = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$job) {
    $_SESSION['aims_flow_dispatch_flash'] = ['ok'=>false,'message'=>'A Flow-fuvar nem található.'];
    header('Location: aims-flow.php');
    exit;
}

if ($action === 'revoke') {
    $u = $pdo->prepare('UPDATE jobs
        SET customer_tracking_token_hash = NULL,
            customer_tracking_expires_at = NULL,
            customer_tracking_last_view_at = NULL,
            updated_at = :updated
        WHERE id = :job');
    $u->execute([':updated'=>gmdate(DateTimeInterface::ATOM),':job'=>$jobId]);
    $_SESSION['aims_flow_dispatch_flash'] = [
        'ok'=>true,
        'message'=>'Megbízói követőlink visszavonva: '.(string)$job['reference'],
    ];
    header('Location: aims-flow.php');
    exit;
}

$now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
$token = bin2hex(random_bytes(32));
$hash = hash('sha256', $token);
$expiresAt = $now->modify("+{$expiresHours} hours")->format(DateTimeInterface::ATOM);

$u = $pdo->prepare('UPDATE jobs
    SET customer_tracking_token_hash = :hash,
        customer_tracking_expires_at = :expires,
        customer_tracking_created_at = :created,
        customer_tracking_last_view_at = NULL,
        updated_at = :updated
    WHERE id = :job');
$u->execute([
    ':hash'=>$hash,
    ':expires'=>$expiresAt,
    ':created'=>$now->format(DateTimeInterface::ATOM),
    ':updated'=>$now->format(DateTimeInterface::ATOM),
    ':job'=>$jobId,
]);

$url = 'https://logistic-aims.hu/api/aims-tracking/customer_portal.php?t='
    . rawurlencode($token) . '&lang=hu';

$orderData = [];
if (!empty($job['order_payload_json'])) {
    $decoded = json_decode((string)$job['order_payload_json'], true);
    if (is_array($decoded)) $orderData = $decoded;
}
$email = trim((string)($orderData['customer_email'] ?? ''));
$mailSent = false;
if ($sendEmail && filter_var($email, FILTER_VALIDATE_EMAIL)) {
    $vehicle = trim((string)$job['label']) !== '' ? (string)$job['label'] : (string)$job['plate'];
    $subject = 'Fuvar követése · ' . (string)$job['reference'];
    $body = "Tisztelt Partnerünk!\n\n"
        . "Az alábbi biztonságos linken követheti a fuvar aktuális állapotát:\n"
        . $url . "\n\n"
        . "Referencia: " . (string)$job['reference'] . "\n"
        . "Jármű: " . $vehicle . "\n"
        . "A link érvényessége: " . $expiresAt . "\n\n"
        . "Logistic-A.I.M.S. Kft.";
    $mailSent = @portal_send_mail($email, $subject, $body, 'office@logistic-aims.hu');
}

$_SESSION['aims_flow_dispatch_flash'] = [
    'ok'=>true,
    'message'=>'Megbízói követőlink elkészült: '.(string)$job['reference']
        .' · érvényes: '.$expiresAt
        .($sendEmail ? ($mailSent ? ' · e-mail elküldve' : ' · e-mail küldése sikertelen / nincs cím') : ''),
    'trackingUrl'=>$url,
];
header('Location: aims-flow.php');
exit;
