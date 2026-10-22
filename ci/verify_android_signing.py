"""Verify the built APK and write a public receipt (no private key material)."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def single_certificate(output):
    counts = re.findall(r'^Number of signers: (\d+)\s*$', output, re.MULTILINE)
    # v3.1 uses SDK-range signer labels and can repeat the same certificate.
    # Exclude Source Stamp Signer and public-key digests: neither signs the APK.
    certificates = {value.lower() for value in re.findall(
        r'^(?:V[1-9](?:\.[0-9]+)? )?Signer[^\r\n]* certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$',
        output, re.MULTILINE)}
    if counts != ['1'] or len(certificates) != 1:
        raise ValueError('Expected one APK signer with one certificate across all SDK ranges')
    return certificates.pop()


def main():
    apk = Path(sys.argv[1])
    receipt = Path(sys.argv[2])
    tools = list((Path(os.environ['ANDROID_HOME']) / 'build-tools').glob('*/apksigner'))
    if not tools:
        raise SystemExit('apksigner is unavailable')
    signer = max(tools, key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.parent.name)))
    result = subprocess.run([str(signer), 'verify', '--verbose', '--print-certs', str(apk)],
                            capture_output=True, text=True, check=True)
    try:
        actual = single_certificate(result.stdout)
    except ValueError:
        # Only public certificate information is printed by apksigner.
        print(result.stdout)
        raise
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
        'signingMode': mode, 'buildType': 'release-pilot',
        'sourceCommit': os.environ['GITHUB_SHA'],
        'upgradeRequirement': 'Same package and signing certificate; increasing versionCode.',
    }, indent=2) + '\n')
    print(f'Verified APK certificate SHA-256: {actual}; mode: {mode}')


if __name__ == '__main__':
    main()
