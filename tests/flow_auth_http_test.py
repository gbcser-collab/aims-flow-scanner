"""Real PHP HTTP endpoints + a TLS CONTROL contract fixture; never uses live accounts."""
import signal
import base64, concurrent.futures, http.server, json, os, pathlib, socket, sqlite3, ssl, subprocess, tempfile, threading, time, urllib.error, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
PHP = os.environ.get('PHP_BIN', 'php')
DEVICE = 'd' * 64
SERVICE = 'test-control-service-' + 'x' * 40
PERMS = ['flow.jobs.read', 'flow.jobs.write', 'flow.workday.write', 'flow.events.write', 'flow.vehicle.read', 'flow.push', 'flow.documents.write']
users = {
 '004271': dict(subjectId='driver-a', tenantId='tenant-a', flowId='004271', assignmentId='assignment-a', vehicleId='vehicle-a', credentialVersion='1', active=True, flowEnabled=True, role='driver', displayName='Test Driver', language='hu', permissions=PERMS),
 '004272': dict(subjectId='driver-b', tenantId='tenant-b', flowId='004272', assignmentId='assignment-b', vehicleId='vehicle-b', credentialVersion='1', active=True, flowEnabled=True, role='driver', displayName='Test Driver B', language='hu', permissions=PERMS),
}
class Control(http.server.BaseHTTPRequestHandler):
 def log_message(self, *_): pass
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
  status=200; result={}
  if self.headers.get('Authorization')!='Bearer '+SERVICE: status=403
  elif self.path=='/verify':
   identity=users.get(body.get('flowId'))
   if identity is None or body.get('pin')!='03816': status=401
   else: result={'ok':True,'identity':identity}
  elif self.path=='/authorize':
   identity=next((x for x in users.values() if x['subjectId']==body.get('subjectId')),None)
   if identity is None: status=403
   else: result={'ok':True,'identity':identity}
  else: status=404
  self.send_response(status); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(json.dumps(result).encode())

def free_port():
 with socket.socket() as s: s.bind(('127.0.0.1',0)); return s.getsockname()[1]

def run():
 with tempfile.TemporaryDirectory() as tmp:
  tmp=pathlib.Path(tmp); cp, pp=free_port(),free_port()
  cert=tmp/'cert.pem'; key=tmp/'key.pem'
  subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  control=http.server.ThreadingHTTPServer(('127.0.0.1',cp),Control)
  tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(cert,key);control.socket=tls.wrap_socket(control.socket,server_side=True)
  threading.Thread(target=control.serve_forever,daemon=True).start()
  env=os.environ.copy();env.update(AIMS_TRACKING_DATA_DIR=str(tmp/'data'), AIMS_FLOW_ID_AUTH_ENABLED='1', AIMS_CONTROL_FLOW_URL=f'https://localhost:{cp}', AIMS_CONTROL_FLOW_SERVICE_TOKEN=SERVICE, AIMS_CONTROL_CA_FILE=str(cert), AIMS_TRACKING_TOKEN='legacy-key-must-be-rejected', PHP_CLI_SERVER_WORKERS='4')
  setup='''require "server/aims-tracking/bootstrap.php";require "server/aims-tracking/flow_auth.php";
  $p=aims_db();$a=aims_ensure_default_admin($p);new FlowAuth($p,new FlowControlHttpClient());$now=gmdate(DATE_ATOM);
  foreach([["DEV9001","tenant-a","vehicle-a"],["DEV9002","tenant-b","vehicle-b"]] as [$plate,$tenant,$cv]){
   $p->prepare("INSERT INTO vehicles(plate,admin_user_id,created_at) VALUES (?,?,?)")->execute([$plate,$a,$now]);$v=$p->lastInsertId();
   $p->prepare("INSERT INTO flow_vehicle_bindings(vehicle_id,tenant_id,control_vehicle_id) VALUES (?,?,?)")->execute([$v,$tenant,$cv]);}
  '''
  subprocess.run([PHP,'-r',setup],cwd=ROOT,env=env,check=True)
  log=open(tmp/'php.log','w+')
  server=subprocess.Popen([PHP,'-S',f'127.0.0.1:{pp}','-t',str(ROOT/'server/aims-tracking')],env=env,stdout=log,stderr=log,start_new_session=True)
  base=f'http://127.0.0.1:{pp}'
  def request(path, data=None, token=None, expected=200, content_type=None):
   headers={'X-Flow-Device':DEVICE}
   if token:headers['Authorization']='Bearer '+token
   if data is not None:
    if isinstance(data,dict):data=json.dumps(data).encode()
    headers['Content-Type']=content_type or 'application/json'
   req=urllib.request.Request(base+'/'+path,data=data,headers=headers)
   try:
    with urllib.request.urlopen(req,timeout=15) as response: status=response.status;raw=response.read()
   except urllib.error.HTTPError as e:status=e.code;raw=e.read()
   assert status==expected,(path,status,raw.decode()[:300])
   result=json.loads(raw)
   if expected==200:assert result['ok'] is True
   return result
  try:
   for _ in range(50):
    try:
     with socket.create_connection(('127.0.0.1',pp),timeout=.1):break
    except OSError:time.sleep(.1)
   def login(id='004271',pin='03816',expected=200):return request('driver_auth.php',{'action':'login','flowId':id,'pin':pin,'deviceId':DEVICE},expected=expected)
   login(pin='00000',expected=401)
   login(id=4271,expected=422)
   a=login();token=a['accessToken']
   assert a['principal']['flowId']=='004271'
   request('driver_jobs.php?plate=DEV9001',token=token)
   request('driver_jobs.php?plate=DEV9002',token=token,expected=403)
   request('driver_jobs.php?plate=DEV9001',token='legacy-key-must-be-rejected',expected=401)
   wd=dict(action='workday_start',plate='DEV9001',workdayId='http-workday',startedAt='2026-10-19T06:00:00Z',startKm=100000)
   request('driver_ops_v2.php',wd,token)
   request('driver_ops_v2.php',wd,token)
   b=login('004272')
   request('driver_ops_v2.php',dict(wd,plate='DEV9002'),b['accessToken'],expected=403)
   png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
   boundary='flow-test-boundary';parts=[]
   values={'action':'safety_check','plate':'DEV9001','id':'http-safety','km':'100060','createdAt':'2026-10-19T08:05:00Z','statuses':json.dumps(dict(oil='ok',coolant='ok',tires='ok',steering='ok'))}
   for k,v in values.items():parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
   for kind in ('oil','coolant','tires','odometer'):
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="photo_{kind}"; filename="{kind}.png"\r\nContent-Type: image/png\r\n\r\n'.encode()+png+b'\r\n')
   parts.append(f'--{boundary}--\r\n'.encode())
   request('driver_ops_v2.php',b''.join(parts),token,content_type='multipart/form-data; boundary='+boundary)
   request('driver_event.php',dict(plate='DEV9001',type='vehicle_issue',message='Brake fault',urgent=True,eventId='http-issue',occurredAt='2026-10-19T08:10:00Z'),token)
   result=request('driver_ops_v2.php',dict(action='workday_finish',plate='DEV9001',workdayId='http-workday',finishedAt='2026-10-19T16:00:00Z',endKm=100120,startedAt=wd['startedAt'],startKm=wd['startKm']),token)
   assert result['distanceKm']==120
   db=sqlite3.connect(tmp/'data/tracking.sqlite')
   assert db.execute('SELECT count(*) FROM driver_workdays').fetchone()[0]==1
   assert db.execute('SELECT count(*) FROM vehicle_safety_photos').fetchone()[0]==4
   assert db.execute('SELECT hold FROM vehicle_operational_state LIMIT 1').fetchone()[0]==1
   db.close()
   request('driver_push_device.php',dict(plate='DEV9001',deviceId=DEVICE,fcmToken='fake-token',platform='android'),token)
   new=request('driver_auth.php',dict(action='refresh',refreshToken=a['refreshToken']))
   request('driver_jobs.php?plate=DEV9001',token=token,expected=401)
   request('driver_jobs.php?plate=DEV9001',token=new['accessToken'])
   request('driver_auth.php',dict(action='refresh',refreshToken=a['refreshToken']),expected=401)
   request('driver_jobs.php?plate=DEV9001',token=new['accessToken'],expected=401)
   # True simultaneous refresh: at most one response wins; replay revokes the family.
   a=login()
   def rotate():
    try:return request('driver_auth.php',dict(action='refresh',refreshToken=a['refreshToken']))
    except AssertionError:return None
   with concurrent.futures.ThreadPoolExecutor(2) as pool: results=list(pool.map(lambda _:rotate(),range(2)))
   assert sum(r is not None for r in results)<=1
   for r in results:
    if r:request('driver_jobs.php?plate=DEV9001',token=r['accessToken'],expected=401)
   a=login();users['004271']['active']=False
   request('driver_jobs.php?plate=DEV9001',token=a['accessToken'],expected=401)
   users['004271']['active']=True
   # Restore the already-authorized B session, then revoke through logout.
   request('driver_auth.php',dict(action='logout',refreshToken=b['refreshToken']))
   request('driver_jobs.php?plate=DEV9002',token=b['accessToken'],expected=401)
   print('PASS real HTTP login, TLS CONTROL adapter, cross-tenant denial, multipart, workday, HOLD, refresh replay/concurrency, revocation, logout')
  except Exception:
   log.flush();log.seek(0);print(log.read());raise
  finally:
   os.killpg(server.pid,signal.SIGTERM);server.wait(timeout=10);control.shutdown();control.server_close();log.close()
if __name__=='__main__':run()
