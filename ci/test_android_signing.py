import base64
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from prepare_android_signing import NAMES, prepare
from verify_android_signing import single_certificate


class SigningTest(unittest.TestCase):
    def test_classic_apksigner_certificate(self):
        digest = 'a1' * 32
        self.assertEqual(single_certificate('Number of signers: 1\n'
            f'Signer #1 certificate SHA-256 digest: {digest}\n'), digest)

    def test_sdk_range_signers_with_the_same_certificate(self):
        digest = 'a1' * 32
        output = 'Number of signers: 1\n'
        for minimum, maximum in [(24, 32), (33, 2147483647)]:
            output += (f'Signer (minSdkVersion={minimum}, maxSdkVersion={maximum}) '
                       f'certificate SHA-256 digest: {digest}\n')
        output += f'Source Stamp Signer certificate SHA-256 digest: {"b2" * 32}\n'
        self.assertEqual(single_certificate(output), digest)

    def test_different_sdk_range_certificates_are_rejected(self):
        with self.assertRaises(ValueError):
            single_certificate('Number of signers: 1\n'
                f'Signer (minSdkVersion=24) certificate SHA-256 digest: {"a1" * 32}\n'
                f'Signer (minSdkVersion=33) certificate SHA-256 digest: {"b2" * 32}\n')

    def test_public_key_and_stamp_cannot_substitute_an_apk_certificate(self):
        with self.assertRaises(ValueError):
            single_certificate('Number of signers: 1\n'
                f'Signer #1 public key SHA-256 digest: {"a1" * 32}\n'
                f'Source Stamp Signer certificate SHA-256 digest: {"a1" * 32}\n')

    def test_multiple_signers_are_rejected(self):
        with self.assertRaises(ValueError):
            single_certificate('Number of signers: 2\n'
                f'Signer #1 certificate SHA-256 digest: {"a1" * 32}\n')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = {key: value for key, value in os.environ.items() if key not in NAMES}
        self.env.update(RUNNER_TEMP=str(self.root), GITHUB_ENV=str(self.root / 'env'),
                        AIMS_REQUIRE_STABLE_SIGNING='false')

    def test_explicit_disposable_mode_without_secrets(self):
        self.assertEqual(prepare(self.env), 'ephemeral-debug')

    def test_required_mode_never_falls_back(self):
        self.env['AIMS_REQUIRE_STABLE_SIGNING'] = 'true'
        with self.assertRaisesRegex(ValueError, 'required'):
            prepare(self.env)

    def test_partial_configuration_is_rejected(self):
        self.env[NAMES[0]] = 'YQ=='
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            prepare(self.env)

    def test_real_certificate_is_verified_and_passwords_stay_out_of_gradle(self):
        original = self.root / 'fixture.p12'
        self.env.update({NAMES[1]: 'fixture-only-pass', NAMES[2]: 'fixture',
                         NAMES[3]: 'fixture-only-pass'})
        subprocess.run(['keytool', '-genkeypair', '-keystore', str(original),
            '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA',
            '-dname', 'CN=Disposable Test Fixture', '-validity', '1',
            '-storepass:env', NAMES[1], '-keypass:env', NAMES[3]],
            env=self.env, capture_output=True, check=True)
        der = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(original),
            '-alias', 'fixture', '-storepass:env', NAMES[1]], env=self.env)
        self.env[NAMES[0]] = base64.b64encode(original.read_bytes()).decode()
        self.env[NAMES[4]] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'fingerprint'):
            prepare(self.env)
        self.assertFalse((self.root / 'aims-flow-signing.keystore').exists())
        self.env[NAMES[4]] = hashlib.sha256(der).hexdigest()
        gradle = self.root / 'build.gradle.kts'
        gradle.write_text('android {}\n')
        real_path = Path
        def paths(value):
            return gradle if value == 'android/app/build.gradle.kts' else real_path(value)
        with patch('prepare_android_signing.Path', side_effect=paths):
            self.assertEqual(prepare(self.env), 'stable-pilot')
        self.assertNotIn('fixture-only-pass', gradle.read_text())
        self.assertIn('System.getenv', gradle.read_text())
        self.assertEqual((self.root / 'aims-flow-signing.keystore').stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
