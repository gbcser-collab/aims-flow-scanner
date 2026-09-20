<?php
declare(strict_types=1);

$tmp=sys_get_temp_dir().'/aims-flow-country-test-'.bin2hex(random_bytes(4));
if(!mkdir($tmp,0700,true)&&!is_dir($tmp))throw new RuntimeException('tmp_dir_failed');
putenv('AIMS_TRACKING_DATA_DIR='.$tmp);

require __DIR__.'/bootstrap.php';
require __DIR__.'/country_stay.php';

function fail_test(string $message):never{
    fwrite(STDERR,"FAIL: $message\n");
    exit(1);
}
function expect_true(bool $value,string $message):void{
    if(!$value)fail_test($message);
}

$pdo=aims_db();
$pdo->prepare('INSERT INTO vehicles
    (plate,label,device_id,admin_user_id,enabled,created_at)
    VALUES (:plate,:label,:device,1,1,:created)')
    ->execute([
        ':plate'=>'SIP115',
        ':label'=>'SIP-115',
        ':device'=>'test-device',
        ':created'=>gmdate(DateTimeInterface::ATOM),
    ]);
$vehicle=$pdo->query('SELECT * FROM vehicles WHERE plate="SIP115"')->fetch(PDO::FETCH_ASSOC);
expect_true(is_array($vehicle),'vehicle missing');

$base=new DateTimeImmutable('2026-09-20T00:00:00+00:00');
$countries=['HU','SK','AT','DE','PL','CZ','LT','LV','EE','PL'];

for($i=0;$i<10000;$i++){
    $block=intdiv($i,1000);
    $actual=$countries[$block];
    $code=$actual;

    if($i>20 && $i%211===0 && $i%1000>20 && $i%1000<970){
        $code=$actual==='SK'?'HU':'SK';
    }

    $time=$base->modify('+'.($i*30).' seconds');
    aims_process_country_stay(
        $pdo,
        $vehicle,
        $code,
        47.0+($i%500)/100000.0,
        17.0+($i%700)/100000.0,
        $time,
        false
    );
}
$state=$pdo->query('SELECT * FROM vehicle_country_state WHERE vehicle_id=1')->fetch(PDO::FETCH_ASSOC);
expect_true(is_array($state),'state missing');
expect_true($state['confirmed_country_code']==='PL','final country should be PL');
expect_true((int)$state['candidate_hits']===0,'candidate should be cleared');

$stays=$pdo->query('SELECT * FROM country_stays WHERE vehicle_id=1 ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
expect_true(count($stays)===10,'expected exactly 10 confirmed country stays, got '.count($stays));

$open=0;
$previousExit=null;
foreach($stays as $index=>$stay){
    $entered=new DateTimeImmutable((string)$stay['entered_at']);
    if($stay['exited_at']===null){
        $open++;
    }else{
        $exited=new DateTimeImmutable((string)$stay['exited_at']);
        expect_true($exited>$entered,'stay duration must be positive at index '.$index);
        if($previousExit!==null){
            expect_true($entered>=$previousExit,'stays must not overlap at index '.$index);
        }
        $previousExit=$exited;
    }
}
expect_true($open===1,'exactly one stay must remain open');
$before=count($stays);
$outOfOrder=$base->modify('+120 seconds');
aims_process_country_stay($pdo,$vehicle,'RO',48.0,18.0,$outOfOrder,false);
$after=(int)$pdo->query('SELECT COUNT(*) FROM country_stays WHERE vehicle_id=1')->fetchColumn();
expect_true($after===$before,'out-of-order replay must not create border crossing');

$singleJitterBase=$base->modify('+400000 seconds');
aims_process_country_stay($pdo,$vehicle,'SK',48.1,18.1,$singleJitterBase,false);
aims_process_country_stay($pdo,$vehicle,'PL',48.1,18.1,$singleJitterBase->modify('+30 seconds'),false);
$afterJitter=(int)$pdo->query('SELECT COUNT(*) FROM country_stays WHERE vehicle_id=1')->fetchColumn();
expect_true($afterJitter===$before,'single-country jitter must not create a stay');

echo "PASS country_stay 10000 observations, stays=$afterJitter, final=".$state['confirmed_country_code']."\n";

foreach(new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($tmp,FilesystemIterator::SKIP_DOTS),
    RecursiveIteratorIterator::CHILD_FIRST
) as $item){
    if($item->isDir())rmdir($item->getPathname());
    else unlink($item->getPathname());
}
rmdir($tmp);