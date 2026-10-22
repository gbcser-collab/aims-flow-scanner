"""Verify the built APK and write a public receipt (no private key material)."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

apk = Path(sys.argv[1])
receipt = Path(sys.argv[2])
tools = list((Path(os.environ['ANDROID_HOME']) / 'build-tools').glob('*/apksigner'))
if not tools:
    raise SystemExit('apksigner is unavailable')
signer = max(tools, key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.parent.name)))
result = subprocess.run([str(signer), 'verify', '--verbose', '--print-certs', str(apk)],
                        capture_output=True, text=True, check=True)
matches = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]+)', result.stdout)
if len(matches) != 1:
    raise SystemExit('Expected exactly one APK signing certificate')
actual = matches[0].lower()
mode = os.environ['AIMS_SIGNING_MODE']
expected = os.environ.get('AIMS_ANDROID_CERT_SHA256', '').replace(':', '').strip().lower()
if mode == 'stable-pilot' and (not expected or actual != expected):
    raise SystemExit('Built APK certificate differs from the approved fingerprint')
if mode not in ('stable-pilot', 'ephemeral-debug'):
    raise SystemExit('Unknown signing mode')
with apk.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
receipt.write_text(json.dumps({
    'apk': apk.name, 'sha256': digest, 'certificateSha256': actual,
    'signingMode': mode, 'buildType': 'debug-pilot',
    'sourceCommit': os.environ['GITHUB_SHA'],
    'upgradeRequirement': 'Same package and signing certificate; increasing versionCode.',
}, indent=2) + '\n')
print(f'Verified APK certificate SHA-256: {actual}; mode: {mode}')
