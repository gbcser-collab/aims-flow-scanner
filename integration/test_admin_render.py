"""Render actual FLOW pages with real SQLite and an isolated host-auth fixture.

The fixtures model only the host authentication boundary and are never shipped.
Warnings are fatal, so a PHP syntax pass cannot hide broken page initialization.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='aims-admin-render-') as directory:
    root = Path(directory)
    shutil.copytree(repo / 'server/aims-tracking', root / 'api/aims-tracking')
    shutil.copytree(repo / 'integration/site/admin', root / 'admin')
    (root / 'inc').mkdir()
    (root / 'inc/analytics.php').write_text('''<?php
function aims_start_session(){if(session_status()!==PHP_SESSION_ACTIVE)session_start();}
function aims_require_admin(){aims_start_session();}
function aims_admin_csrf(){return 'isolated-test-csrf';}
function aims_audit($event,$data=[]){}
function aims_security_headers($admin=false){}
''')
    (root / 'inc/portal.php').write_text('''<?php
function portal_h($s){return htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');}
function portal_job_by_id($id){return null;}
''')
    (root / 'runner.php').write_text('''<?php
error_reporting(E_ALL);
set_error_handler(function($severity,$message,$file,$line){
  if(error_reporting() & $severity)throw new ErrorException($message,0,$severity,$file,$line);
  return false;
});
$_SERVER['REQUEST_METHOD']='GET';
$_SERVER['SCRIPT_NAME']='/admin/'.$argv[1];
$_GET=[];$_POST=[];
require __DIR__.'/api/aims-tracking/bootstrap.php';
require_once __DIR__.'/api/aims-tracking/driver_auth_v2.php';
$pdo=aims_db();aims_driver_auth_schema($pdo);
$admin=aims_ensure_default_admin($pdo);
$now=gmdate(DateTimeInterface::ATOM);
$pdo->prepare('INSERT OR IGNORE INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?)')->execute(['TEST043','Render test',$admin,1,$now]);
if($argv[2]==='populated'){
 $pdo->exec("INSERT OR IGNORE INTO notifications(admin_user_id,type,severity,title,body,dedupe_key,created_at) SELECT id,'test','info','Test notice','Test body','render-v43',datetime('now') FROM admin_users LIMIT 1");
}
ob_start();require __DIR__.'/admin/'.$argv[1];$html=ob_get_clean();
if(strpos($html,'</html>')===false)throw new RuntimeException('Incomplete HTML response');
if($argv[1]==='aims-flow-workspace.php' && $argv[2]==='populated' && $flowActionCount!==1)throw new RuntimeException('Unread action count is not initialized correctly');
echo json_encode(['page'=>$argv[1],'case'=>$argv[2],'bytes'=>strlen($html),'ok'=>true]).PHP_EOL;
''')
    env = dict(os.environ, AIMS_TRACKING_DATA_DIR=str(root / 'data'), AIMS_ADMIN_TRACKING_TOKEN='isolated-admin-test-token')
    for case in ('empty', 'populated'):
        for page in ('aims-flow-workspace.php', 'aims-flow-monthly-report.php', 'aims-flow-eco.php', 'aims-flow-driver-access.php', 'aims-flow-mileage.php', 'foreign-stay-report.php'):
            result = subprocess.run(['php', str(root / 'runner.php'), page, case], env=env, text=True, capture_output=True)
            print(result.stdout, end='')
            if result.returncode:
                raise RuntimeError(result.stderr or result.stdout)

