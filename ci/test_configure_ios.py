import plistlib
import tempfile
import unittest
from pathlib import Path
from configure_ios import configure

class IosConfigurationTest(unittest.TestCase):
    def test_background_permissions_signing_and_idempotence(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); runner=root/'ios/Runner'; runner.mkdir(parents=True)
            (root/'ios/Runner.xcodeproj').mkdir()
            (runner/'Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion':'$(FLUTTER_BUILD_NUMBER)'}))
            (runner/'AppDelegate.swift').write_text('import Flutter\nfunc application() -> Bool { return true }\n')
            project=root/'ios/Runner.xcodeproj/project.pbxproj'
            project.write_text('  IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n  INFOPLIST_FILE = Runner/Info.plist;\n  PRODUCT_BUNDLE_IDENTIFIER = hu.logisticaims.aimsFlowScanner;\n')
            configure(root)
            first={p.relative_to(root):p.read_bytes() for p in root.rglob('*') if p.is_file()}
            configure(root)
            second={p.relative_to(root):p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertEqual(first,second)
            info=plistlib.loads((runner/'Info.plist').read_bytes())
            self.assertEqual(info['UIBackgroundModes'],['location'])
            self.assertIn('NSLocationAlwaysAndWhenInUseUsageDescription',info)
            self.assertNotIn('NSAppTransportSecurity',info)
            ent=plistlib.loads((runner/'Flow.entitlements').read_bytes())
            self.assertEqual(ent['com.apple.developer.default-data-protection'],'NSFileProtectionCompleteUntilFirstUserAuthentication')
            self.assertNotIn('aps-environment',ent)
            self.assertIn('IPHONEOS_DEPLOYMENT_TARGET = 15.5;',project.read_text())
            self.assertEqual(project.read_text().count('CODE_SIGN_ENTITLEMENTS'),1)

if __name__=='__main__': unittest.main()
