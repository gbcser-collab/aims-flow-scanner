"""Authenticated phone sessions work without a manually installed master secret.
Direct unauthenticated endpoints and revoked/foreign sessions remain denied.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='aims-public-session-') as temporary:
    root=Path(temporary)
    backend=root/'public/api/aims-tracking'
    shutil.copytree(repo/'server/aims-tracking',backend)
    env=dict(os.environ,AIMS_TRACKING_DATA_DIR=str(root/'data'))
    env.pop('AIMS_TRACKING_TOKEN',None)
    env.pop('AIMS_ADMIN_TRACKING_TOKEN',None)
    setup='''require $argv[1].'/bootstrap.php';require_once $argv[1].'/driver_auth_v2.php';
    $pdo=aims_db();aims_driver_auth_schema($pdo);$admin=aims_ensure_default_admin($pdo);
    $now=gmdate(DateTimeInterface::ATOM);
    $pdo->prepare('INSERT INTO vehicles(plate,label,admin_user_id,enabled,created_at) VALUES (?,?,?,?,?)')->execute(['PUBLIC43','Public test',$admin,1,$now]);
    $vehicle=(int)$pdo->lastInsertId();
    $pdo->prepare('INSERT INTO driver_accounts(flow_id,pin_hash,email,driver_name,vehicle_id,onboarding_complete,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)')->execute(['430001',password_hash('12345',PASSWORD_DEFAULT),'test@example.test','Fixture',$vehicle,1,1,$now,$now]);
    $session=aims_driver_issue_session($pdo,(int)$pdo->lastInsertId(),str_repeat('d',64),1);
    echo json_encode($session);'''
    result=subprocess.run(['php','-r',setup,str(backend)],env=env,text=True,capture_output=True,check=True)
    token=json.loads(result.stdout)['token']
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    log=(root/'server.log').open('w+')
    server=subprocess.Popen(['php','-S',f'127.0.0.1:{port}','-t',str(backend)],env=env,stdout=log,stderr=log)
    def request(path,payload=None,bearer=None):
        headers={'Content-Type':'application/json'}
        if bearer:headers['Authorization']='Bearer '+bearer
        req=urllib.request.Request(f'http://127.0.0.1:{port}/'+path,data=json.dumps(payload).encode() if payload else None,headers=headers)
        try:
            with urllib.request.urlopen(req,timeout=10) as response:return response.status,json.load(response)
        except urllib.error.HTTPError as error:return error.code,json.loads(error.read())
    try:
        for attempt in range(50):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:time.sleep(.1)
        payload={'action':'workday_start','plate':'PUBLIC43','workdayId':'430001-public-test','startedAt':'2026-10-22T06:00:00Z','startKm':100000}
        status,body=request('session/driver_ops_v2.php',payload,'0'*64)
        assert status==401,(status,body)
        status,body=request('session/driver_ops_v2.php',dict(payload,plate='OTHER43'),token)
        assert status==403,(status,body)
        status,body=request('session/driver_ops_v2.php',payload,token)
        assert status==200 and body['ok'],(status,body)
        status,body=request('driver_ops_v2.php',payload,token)
        assert status in (401,503) and not body.get('ok'),(status,body)
        with sqlite3.connect(root/'data/tracking.sqlite') as db:
            db.execute('UPDATE driver_sessions SET revoked_at=? WHERE token_hash=?',('2026-10-22T06:01:00Z',hashlib.sha256(token.encode()).hexdigest()))
        status,body=request('session/driver_ops_v2.php',payload,token)
        assert status==401,(status,body)
        print('PUBLIC SESSION: valid login accepted; invalid, foreign, direct and revoked access denied')
    finally:
        server.terminate();server.wait(timeout=10);log.close()
