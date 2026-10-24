"""Build the V44 flat public update on the verified complete V43 package."""
from pathlib import Path
import argparse, hashlib, json, shutil, zipfile
from package_website import package

BASE_SHA256 = '4ec149d33dc8f7744411f242735f3a89cacb469eb1af0c3c2c977a104ebf8292'
ADMIN = ['admin-shell-static.php','aims-admin-shell.js','aims-flow-dispatch.php',
         'aims-flow-mileage.php','aims-flow-monthly-report.php','aims-flow-workspace.php',
         'aims-mileage.css','aims-mileage.js','foreign-stay-report.php']
SERVER = ['job_assign.php','mileage_report_lib.php','monthly_report_lib.php']

def build(base_zip, destination, output):
    if hashlib.sha256(base_zip.read_bytes()).hexdigest() != BASE_SHA256:
        raise ValueError('The input is not the verified V43 package.')
    if destination.exists():
        raise ValueError('Use a new staging directory.')
    root = destination / 'FELTOLTENDO';root.mkdir(parents=True)
    with zipfile.ZipFile(base_zip) as archive:
        if archive.testzip() is not None:raise ValueError('Invalid V43 ZIP.')
        archive.extractall(root)
    repo = Path(__file__).resolve().parents[1]
    for name in ADMIN:shutil.copy2(repo/'integration/site/admin'/name,root/'admin'/name)
    for name in SERVER:shutil.copy2(repo/'server/aims-tracking'/name,root/'api/aims-tracking'/name)
    manifest=[]
    for file in sorted(root.rglob('*')):
        if not file.is_file():continue
        relative=file.relative_to(root)
        if any(part.startswith('.') and part!='.htaccess' for part in relative.parts):continue
        if file.suffix.lower() in {'.sqlite','.db','.pem','.p12','.keystore'}:raise ValueError('Private data cannot be packaged.')
        manifest.append({'path':str(relative),'bytes':file.stat().st_size,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
    (destination/'FAJLLISTA.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    return package(destination,output)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ['base-zip','destination','output']:parser.add_argument('--'+name,required=True,type=Path)
    print(json.dumps(build(**vars(parser.parse_args())),indent=2))
