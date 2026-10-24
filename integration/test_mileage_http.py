"""Exercise actual admin handlers against isolated host authentication and SQLite."""
from pathlib import Path
import json, os, re, shutil, socket, sqlite3, subprocess, tempfile, time
import urllib.request, urllib.error, urllib.parse
repo=Path(__file__).resolve().parents[1]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
with tempfile.TemporaryDirectory(prefix='aims-mileage-http-') as temp:
    root=Path(temp);public=root/'public';(public/'inc').mkdir(parents=True);(root/'sessions').mkdir()
    shutil.copytree(repo/'server/aims-tracking',public/'api/aims-tracking')
    shutil.copytree(repo/'integration/site/admin',public/'admin')
    (public/'inc/analytics.php').write_text('''<?php
function aims_start_session(){if(session_status()!==PHP_SESSION_ACTIVE)session_start();}
function aims_require_admin(){aims_start_session();if(empty($_SESSION['fixture_admin'])){http_response_code(401);exit('Login required');}}
function aims_admin_csrf(){return 'fixture-csrf-v44';}
function aims_audit($event,$data=[]){}
function aims_security_headers($admin=false){}
''')
    (public/'inc/portal.php').write_text("<?php function portal_h($v){return htmlspecialchars((string)$v,ENT_QUOTES,'UTF-8');} function portal_job_by_id($id){return null;}")
    env=dict(os.environ,AIMS_TRACKING_DATA_DIR=str(root/'data'),AIMS_ADMIN_TRACKING_TOKEN='fixture-admin-44',AIMS_TRACKING_TOKEN='fixture-tracking-44')
    setup='''session_id('fixture-v44-admin');session_start();$_SESSION['fixture_admin']=true;session_write_close();
require $argv[1].'/bootstrap.php';require $argv[1].'/driver_auth_v2.php';
$p=aims_db();aims_driver_auth_schema($p);$admin=aims_ensure_default_admin($p);$now=gmdate('c');
$p->prepare('INSERT INTO vehicles(plate,label,admin_user_id,created_at) VALUES(?,?,?,?)')->execute(['HTTP44','HTTP',$admin,$now]);
$p->prepare('INSERT INTO jobs(reference,vehicle_id,created_at,updated_at) VALUES(?,?,?,?)')->execute(['HTTP-TEST',1,$now,$now]);
echo 'ready';'''
    subprocess.run(['php','-d','session.save_path='+str(root/'sessions'),'-r',setup,str(public/'api/aims-tracking')],env=env,check=True,capture_output=True,text=True)
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    log=(root/'php.log').open('w+')
    server=subprocess.Popen(['php','-d','session.save_path='+str(root/'sessions'),'-S',f'127.0.0.1:{port}','-t',str(public)],env=env,stdout=log,stderr=log)
    opener=urllib.request.build_opener(NoRedirect)
    def request(path='aims-flow-mileage.php',data=None,auth=True):
        headers={'Cookie':'PHPSESSID=fixture-v44-admin'} if auth else {}
        payload=urllib.parse.urlencode(data).encode() if data is not None else None
        req=urllib.request.Request(f'http://127.0.0.1:{port}/admin/'+path,data=payload,headers=headers)
        try:
            with opener.open(req,timeout=20) as r:return r.status,r.read().decode(),dict(r.headers)
        except urllib.error.HTTPError as e:return e.code,e.read().decode(),dict(e.headers)
    try:
        for i in range(50):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:time.sleep(.1)
        assert request(auth=False)[0]==401
        payload={'csrf':'bad','action':'home','vehicle_id':'1','flow_id':'','address':'Teszt <img src=x onerror=alert(1)>','latitude':'47','longitude':'19','radius_m':'200','valid_from':'2026-01-01'}
        assert request(data=payload)[0]==403
        payload['csrf']='fixture-csrf-v44';assert request(data=payload)[0]==303
        status,body,_=request();assert status==200 and '&lt;img src=x' in body and '<img src=x onerror=' not in body
        with sqlite3.connect(root/'data/tracking.sqlite') as db:assert db.execute('SELECT COUNT(*) FROM vehicle_home_locations').fetchone()[0]==1
        invalid=dict(payload,latitude='999',valid_from='2026-02-01');status,body,_=request(data=invalid);assert 'Pontos cím' in body
        with sqlite3.connect(root/'data/tracking.sqlite') as db:assert db.execute('SELECT COUNT(*) FROM vehicle_home_locations').fetchone()[0]==1
        finance={'csrf':'fixture-csrf-v44','action':'finance','job_id':'1','planned_km':'125,5','revenue_eur':'200,00','service_date':'2026-05-04','flow_id':''}
        assert request(data=finance)[0]==303;assert request(data=finance)[0]==303
        with sqlite3.connect(root/'data/tracking.sqlite') as db:
            assert db.execute('SELECT COUNT(*) FROM flow_job_finance').fetchone()[0]==1
            assert db.execute('SELECT planned_km,revenue_eur_cents FROM flow_job_finance').fetchone()==(125.5,20000)
        status,body,headers=request('aims-flow-mileage.php?from=2026-05-04&to=2026-05-06&download=summary')
        assert status==200 and 'text/csv' in headers['Content-Type'] and 'HTTP44' in body and '125.5' in body
        assert request('aims-flow-mileage.php?from=2026-02-30&to=2026-03-01')[0]==422
        for page in ['aims-flow-monthly-report.php','foreign-stay-report.php']:
            status,body,_=request(page+'?from=2026-05-04&to=2026-05-06');assert status==200 and '</html>' in body
        assert request('aims-flow-mileage.php?download=summary',auth=False)[0]==401
        def api(path,payload=None,token='fixture-admin-44'):
            req=urllib.request.Request(f'http://127.0.0.1:{port}/api/aims-tracking/'+path,data=None if payload is None else json.dumps(payload).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(req,timeout=20) as response:return response.status,json.load(response)
            except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
        assignment={'plate':'HTTP44','billing':{'planned_km':'150','revenue_eur':'250'},'driverJob':{'reference':'HTTP-BILLING','pickups':[{'address':'A','latitude':47,'longitude':19}],'deliveries':[{'address':'B','latitude':47.1,'longitude':19.1}]}}
        code,body=api('job_assign.php',assignment);assert code==200 and body['ok'],(code,body)
        code,driver=api('driver_jobs.php?plate=HTTP44',token='fixture-tracking-44');assert code==200 and 'revenue_eur' not in json.dumps(driver) and 'billing' not in driver
        code,body=api('job_assign.php',dict(assignment,billing={'planned_km':'-2'}));assert code==422
        assignment['billing']['revenue_eur']='999';assert api('job_assign.php',assignment)[0]==200
        with sqlite3.connect(root/'data/tracking.sqlite') as db:assert db.execute('SELECT revenue_eur_cents FROM flow_job_finance WHERE job_id=2').fetchone()[0]==25000
        print('MILEAGE HTTP: admin gate, CSRF, home/finance persistence, XSS escaping, atomic invalid input, CSV, and date filters passed')
    except Exception:
        log.flush();print((root/'php.log').read_text()[-5000:]);raise
    finally:server.terminate();server.wait(timeout=10);log.close()
