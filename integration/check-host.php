<?php
declare(strict_types=1);
// CLI-only, read-only dependency check. Does not create or migrate a database.
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
$root=rtrim((string)($argv[1]??''),'/');
if($root===''||!is_dir($root)){fwrite(STDERR,"Használat: php check-host.php /teljes/ut/public_html\n");exit(2);}
$failed=false;
$check=static function(bool $ok,string $name)use(&$failed):void{echo ($ok?'OK   ':'HIÁNY ').$name.PHP_EOL;if(!$ok)$failed=true;};
$check(PHP_VERSION_ID>=80100,'PHP 8.1+');
foreach(['pdo_sqlite','mbstring','curl','fileinfo','openssl'] as $ext)$check(extension_loaded($ext),'PHP '.$ext);
foreach(['inc/analytics.php','inc/portal.php','inc/app-metrics.php','inc/mailbot.php','inc/mailbox.php','inc/workflow.php','inc/outlook.php','inc/autopilot100.php','inc/dispatch-engine.php','inc/ops-intelligence.php','partner/index.php','api/aims-flow-auth-v2.php','api/aims-tracking/bootstrap.php','api/aims-tracking/session/ingest.php','api/aims-tracking/smart_document_storage.php','admin/index.php','admin/order-ai.php','admin/aims-flow-driver-access.php'] as $path)$check(is_readable($root.'/'.$path),$path);
$check(is_readable(dirname($root).'/aims-flow-config.php')||(getenv('AIMS_TRACKING_TOKEN')!==false&&getenv('AIMS_ADMIN_TRACKING_TOKEN')!==false),'FLOW szerverkonfiguráció jelenléte (értékek nem kerülnek kiírásra)');
echo "A vizsgálat nem igazolja az adatbázis, a levelezés, a push vagy a belépés működését; ezeket saját tesztfiókkal ellenőrizd.\n";
exit($failed?1:0);
