"""Build an additive update for the existing Logistic-AIMS hosting account.
Inputs are extracted, verified website V39, admin V40, FLOW backend and APK.
Never copy credentials or live databases; never delete files on the server.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, shutil


def assemble(website, admin, backend, apk, destination):
    root=destination/'FELTOLTENDO'
    if destination.exists():
        raise ValueError('Choose an empty output directory; existing builds are preserved.')
    root.mkdir(parents=True)
    docs=destination/'DOKUMENTACIO';docs.mkdir()
    config=destination/'SZERVERBEALLITAS';config.mkdir()
    for f in website.iterdir():
        if f.name=='.htaccess':
            shutil.copy2(f,config/'honlap-apache-minta.conf');continue
        if f.is_file() and (f.suffix.lower() in ['.md','.txt','.json'] and f.name not in ['robots.txt','ads.txt']):
            shutil.copy2(f,docs/f.name);continue
        if f.is_dir(): shutil.copytree(f,root/f.name)
        else: shutil.copy2(f,root/f.name)
    shutil.copytree(admin/'admin',root/'admin')
    # V40 retains the full original dispatch and OCR modules. Only explicitly
    # merged modules below replace admin pages; FLOW's smaller dispatch is not copied.
    shutil.copytree(backend/'api',root/'api')
    overlay=Path(__file__).resolve().parents[1]/'integration/site'
    shutil.copytree(overlay,root,dirs_exist_ok=True)
    guard=Path(__file__).resolve().parents[1]/'server/aims-tracking/session/_guard.php'
    shutil.copy2(guard,root/'api/aims-tracking/session/_guard.php')
    css=(overlay/'assets/mobile-v41.css').read_text()
    refresh=root/'admin/admin-refresh.css'
    refresh.write_text(refresh.read_text()+'\n'+css)
    for f in root.rglob('*.html'):
        s=f.read_text()
        rel=os.path.relpath(root/'assets/mobile-v41.css',f.parent).replace(os.sep,'/')
        if 'mobile-v41.css' not in s:
            s=s.replace('</head>',f'<link rel="stylesheet" href="{rel}"></head>',1)
        s=re.sub(r'(name=["\']viewport["\'][^>]*content=["\'])([^"\']+)',
            lambda m:m[1]+(m[2] if 'viewport-fit=' in m[2] else m[2]+',viewport-fit=cover'),s,flags=re.I)
        f.write_text(s)
    for f in (root/'admin').glob('*.php'):
        s=f.read_text();s=s.replace('width=device-width,initial-scale=1"','width=device-width,initial-scale=1,viewport-fit=cover"');f.write_text(s)
    index=root/'index.html';s=index.read_text()
    # Relative access routes also work on the staging host before publication.
    s=s.replace('https://logistic-aims.hu/admin/','admin/').replace('https://logistic-aims.hu/partner/','partner/')
    s=s.replace('https://logistic-aims.hu/app/', 'flow/app/')
    s=s.replace('"app/"', '"flow/app/"').replace("'app/'", "'flow/app/'")
    # Load the independent escape path before the animation scripts execute.
    s=s.replace('</head>', '<script src="assets/startup-v43.js"></script><style>.aims-startup-recovered .reveal{opacity:1!important;transform:none!important}</style></head>', 1)
    s=s.replace('<a class="login-register-v24"', '<a class="login-option-v24 flow" href="flow/app/" role="menuitem"><span class="login-option-icon-v24">F</span><span><b>FLOW alkalmazás</b><small>Sofőrapp és telepítési segítség</small></span><em></em></a><a class="login-register-v24"',1)
    s=s.replace('</div><details class="mobile-access-quote', '<a class="flow-mobile-entry-v41" href="flow/app/"><b>FLOW alkalmazás</b><small>Letöltés és belépés</small></a></div><details class="mobile-access-quote',1)
    # Existing service links remain; append a direct app entry after the lead actions.
    s=s.replace('</main>','<section style="padding:32px;text-align:center"><a class="flow-app-entry" href="flow/app/">AIMS FLOW · Belépés és alkalmazás →</a></section></main>',1)
    if 'href="flow/app/"' not in s:
        s=s.replace('</body>','<p style="padding:24px;text-align:center"><a class="flow-app-entry" href="flow/app/">AIMS FLOW · Belépés és alkalmazás →</a></p></body>',1)
    index.write_text(s)
    flow=root/'flow/index.html';s=flow.read_text()
    s=s.replace('<div class="header-actions">','<div class="header-actions"><a class="header-cta" href="app/">Belépés és app</a>',1)
    s=s.replace('<a href="#kapcsolat">Kapcsolat</a>','<a href="#kapcsolat">Kapcsolat</a><a href="app/">Belépés és alkalmazás</a>',1)
    flow.write_text(s)
    downloads=root/'flow/app/downloads';downloads.mkdir()
    shutil.copy2(apk,downloads/apk.name)
    digest=hashlib.sha256(apk.read_bytes()).hexdigest()
    (downloads/(apk.name+'.sha256')).write_text(digest+'  '+apk.name+'\n')
    manifest=[]
    for f in sorted(root.rglob('*')):
        if not f.is_file():continue
        assert f.suffix.lower() not in ['.sqlite','.db','.pem','.p12','.keystore']
        manifest.append({'path':str(f.relative_to(root)), 'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    (destination/'FAJLLISTA.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    print(json.dumps({'files':len(manifest),'apk_sha256':digest,'output':str(destination)}))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ['website','admin','backend','apk','destination']:parser.add_argument('--'+name,required=True,type=Path)
    args=parser.parse_args();assemble(**vars(args))
