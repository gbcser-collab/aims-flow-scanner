"""Apply repeatable iOS settings to a fresh Flutter-generated runner."""
from pathlib import Path
import plistlib
import re


def configure(root: Path):
    ios = root / 'ios'
    info = ios / 'Runner/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data.update({
        'CFBundleDisplayName': 'AIMS FLOW',
        'NSCameraUsageDescription': 'A kamera a fuvarokmányok, bizonylatok és Safety-fotók rögzítéséhez szükséges.',
        'NSLocationWhenInUseUsageDescription': 'Az aktív munkanap fuvarhelyzete és az érkezések rögzítéséhez használjuk a helyzetedet.',
        'NSLocationAlwaysAndWhenInUseUsageDescription': 'Az aktív munkanap alatt lezárt képernyőnél is rögzítjük a fuvar útvonalát. A munkanap lezárásakor a követés leáll.',
        'NSFaceIDUsageDescription': 'Face ID-val nyithatod meg a saját FLOW-munkamenetedet.',
        'UIBackgroundModes': ['location'],
        'ITSAppUsesNonExemptEncryption': False,
    })
    info.write_bytes(plistlib.dumps(data, sort_keys=False))
    entitlements = {
        'keychain-access-groups': [],
        'com.apple.developer.default-data-protection': 'NSFileProtectionCompleteUntilFirstUserAuthentication',
    }
    (ios / 'Runner/Flow.entitlements').write_bytes(plistlib.dumps(entitlements))
    project = ios / 'Runner.xcodeproj/project.pbxproj'
    text = project.read_text()
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.5;', text)
    text = text.replace('hu.logisticaims.aimsFlowScanner', 'hu.logisticaims.aims-flow-scanner')
    text = text.replace('hu.logisticaims.aims_flow_scanner', 'hu.logisticaims.aims-flow-scanner')
    # Only Runner configs carry this key; RunnerTests must retain their own entitlements.
    text = re.sub(r'\s*CODE_SIGN_ENTITLEMENTS = Runner/Flow.entitlements;', '', text)
    text = re.sub(r'(^\s*)INFOPLIST_FILE = Runner/Info.plist;',
        r'\1INFOPLIST_FILE = Runner/Info.plist;\1CODE_SIGN_ENTITLEMENTS = Runner/Flow.entitlements;', text, flags=re.M)
    project.write_text(text)
    delegate = ios / 'Runner/AppDelegate.swift'
    text = delegate.read_text()
    if 'import UserNotifications' not in text:
        text = 'import UserNotifications\n' + text
    marker = ') -> Bool {'
    if marker not in text:
        raise RuntimeError('Unknown Flutter AppDelegate template; review notification integration.')
    if 'UNUserNotificationCenter.current().delegate = self' not in text:
        text = text.replace(marker, marker + '\n    UNUserNotificationCenter.current().delegate = self', 1)
    delegate.write_text(text)
    (ios / 'Podfile').write_text('''platform :ios, '15.5'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release }
def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise 'FLUTTER_ROOT missing; run flutter pub get first'
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '0'
      if Gem::Version.new(current) < Gem::Version.new('15.5')
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
      end
      config.build_settings['EXCLUDED_ARCHS[sdk=*]'] = 'armv7'
    end
  end
end
''')


if __name__ == '__main__':
    configure(Path(__file__).resolve().parents[1])
