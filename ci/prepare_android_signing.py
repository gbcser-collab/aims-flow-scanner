"""Prepare an existing signing key; never generate or publish private keys."""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess

NAMES = (
    'AIMS_ANDROID_KEYSTORE_BASE64', 'AIMS_ANDROID_STORE_PASSWORD',
    'AIMS_ANDROID_KEY_ALIAS', 'AIMS_ANDROID_KEY_PASSWORD', 'AIMS_ANDROID_CERT_SHA256',
)


def prepare(env):
    present = [bool(env.get(name)) for name in NAMES]
    required = env.get('AIMS_REQUIRE_STABLE_SIGNING', '').lower() == 'true'
    if not any(present):
        if required:
            raise ValueError('Stable signing is required, but the signing secrets are missing.')
        return 'ephemeral-debug'
    if not all(present):
        raise ValueError('Incomplete signing configuration. All five signing secrets are required.')
    expected = env[NAMES[4]].replace(':', '').strip().lower()
    if not re.fullmatch('[a-f0-9]{64}', expected):
        raise ValueError('The expected certificate SHA-256 must contain 64 hexadecimal digits.')
    keyfile = Path(env['RUNNER_TEMP']) / 'aims-flow-signing.keystore'
    try:
        data = base64.b64decode(''.join(env[NAMES[0]].split()), validate=True)
        with keyfile.open('xb') as stream:
            os.chmod(keyfile, 0o600)
            stream.write(data)
        result = subprocess.run([
            'keytool', '-exportcert', '-keystore', str(keyfile),
            '-alias', env[NAMES[2]], '-storepass:env', NAMES[1],
        ], env=env, capture_output=True, check=False)
        if result.returncode or not result.stdout:
            raise ValueError('Cannot read the signing certificate. Check the key, alias and password.')
        if hashlib.sha256(result.stdout).hexdigest() != expected:
            raise ValueError('Signing certificate fingerprint does not match the configured SHA-256.')
        gradle = Path('android/app/build.gradle.kts')
        gradle.write_text(gradle.read_text() + '''

// Managed pilot signing: passwords remain in runner environment variables.
android {
    signingConfigs {
        getByName("debug") {
            storeFile = file(System.getenv("AIMS_SIGNING_KEYSTORE"))
            storePassword = System.getenv("AIMS_ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("AIMS_ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("AIMS_ANDROID_KEY_PASSWORD")
        }
    }
}
''')
        with Path(env['GITHUB_ENV']).open('a') as stream:
            stream.write(f'AIMS_SIGNING_KEYSTORE={keyfile}\n')
        return 'stable-pilot'
    except Exception:
        keyfile.unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    try:
        mode = prepare(dict(os.environ))
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            output.write(f'mode={mode}\n')
        print(f'APK signing mode: {mode}')
        if mode == 'ephemeral-debug':
            print('::warning::Temporary debug certificate: this APK is not an upgrade channel.')
    except Exception as error:
        # Errors above deliberately exclude secret values and subprocess output.
        print(f'::error::{error}' if isinstance(error, ValueError)
              else '::error::Signing preparation failed. No APK will be published.')
        raise SystemExit(1)
