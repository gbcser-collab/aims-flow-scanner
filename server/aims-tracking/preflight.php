<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
require __DIR__.'/bootstrap.php';

$dataDir = trim((string)(getenv('AIMS_TRACKING_DATA_DIR') ?: '')) ?: __DIR__.'/data';
$webRoot = dirname(__DIR__,2);
$checks = [
    'PHP 8.1 vagy újabb'=>PHP_VERSION_ID >= 80100,
    'PDO SQLite'=>class_exists(PDO::class) && in_array('sqlite',PDO::getAvailableDrivers(),true),
    'mbstring'=>extension_loaded('mbstring'),
    'Meglévő admin hitelesítés (inc/analytics.php)'=>is_file($webRoot.'/inc/analytics.php'),
    'Meglévő partner/admin segédfüggvények (inc/portal.php)'=>is_file($webRoot.'/inc/portal.php'),
    'Szerveroldali tracking token'=>trim((string)getenv('AIMS_TRACKING_TOKEN')) !== '',
    'Admin tracking token'=>trim((string)getenv('AIMS_ADMIN_TRACKING_TOKEN')) !== '',
    'Írható adatmappa vagy szülő'=>is_dir($dataDir) ? is_writable($dataDir) : is_writable(dirname($dataDir)),
];
$ok = true;
foreach ($checks as $label=>$passed) {
    echo ($passed ? '[OK] ' : '[HIÁNYZIK] ').$label.PHP_EOL;
    $ok = $ok && $passed;
}
echo 'Ez a próba nem módosít adatot, nem küld levelet és nem igazolja a telefonos működést.'.PHP_EOL;
exit($ok ? 0 : 1);
