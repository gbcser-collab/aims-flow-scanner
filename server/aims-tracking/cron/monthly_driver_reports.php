<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI only\n");
}

require dirname(__DIR__).'/bootstrap.php';
require dirname(__DIR__).'/monthly_report_lib.php';

$options = getopt('', ['month:', 'force', 'dry-run']);
$force = array_key_exists('force', $options);
$dryRun = array_key_exists('dry-run', $options);
$tz = new DateTimeZone('Europe/Budapest');
$now = new DateTimeImmutable('now', $tz);
$month = trim((string)($options['month'] ?? ''));

if ($month === '') {
    // Run this script every morning. The first day is the normal delivery;
    // days 2 and 3 are automatic retry windows when hosting mail() failed.
    $day = (int)$now->format('j');
    if (!$force && ($day < 1 || $day > 3)) {
        echo "Nincs havi riportküldési ablak.\n";
        exit(0);
    }
    $month = $now->modify('first day of last month')->format('Y-m');
}

try {
    aims_monthly_period($month);
} catch (Throwable $error) {
    fwrite(STDERR, 'Érvénytelen hónap: '.$error->getMessage()."\n");
    exit(2);
}

$recipient = trim((string)(getenv('AIMS_MONTHLY_REPORT_EMAIL') ?: 'office@logistic-aims.hu'));
$pdo = aims_db();
aims_monthly_runs_schema($pdo);
try {
    $reportLock = aims_monthly_acquire_lock($month);
} catch (AimsMonthlyReportBusy $error) {
    echo $error->getMessage()."\n";
    exit(0);
}
$existing = aims_monthly_run_state($pdo, $month);
if (!$dryRun && !$force && $existing && ($existing['status'] ?? '') === 'sent') {
    echo "A {$month} havi riport már elküldve: ".($existing['sent_at'] ?? '')."\n";
    exit(0);
}

try {
    $report = aims_monthly_build_report($pdo, $month);
    $paths = aims_monthly_store_report($report);

    if ($dryRun) {
        echo "Próbagenerálás kész: {$month}\n";
        foreach ($paths as $name=>$path) echo "- {$name}: {$path}\n";
        exit(0);
    }

    $sent = aims_monthly_send_mail($report, $paths, $recipient);
    if (!$sent) {
        aims_monthly_record_run(
            $pdo,
            $month,
            $recipient,
            'mail_failed',
            'A levelezőszerver nem fogadta el küldésre a riportot. A következő napi cron újrapróbálja.',
            $paths
        );
        fwrite(STDERR, "A havi riport elkészült, de az e-mail-küldés sikertelen.\n");
        exit(3);
    }

    $sentAt = gmdate(DateTimeInterface::ATOM);
    aims_monthly_record_run(
        $pdo,
        $month,
        $recipient,
        'sent',
        'A levelezőszerver küldésre átvette a havi riportot; a kézbesítés külön ellenőrizendő.',
        $paths,
        $sentAt
    );
    echo "A {$month} havi riport átadva a levelezőszervernek, címzett: {$recipient}\n";
    exit(0);
} catch (Throwable $error) {
    aims_monthly_record_run(
        $pdo,
        $month,
        $recipient,
        'failed',
        mb_substr($error->getMessage(), 0, 1000, 'UTF-8'),
        []
    );
    fwrite(STDERR, 'Havi riport hiba: '.$error->getMessage()."\n");
    exit(4);
}

