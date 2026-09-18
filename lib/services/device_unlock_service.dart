import 'package:local_auth/local_auth.dart';

import 'aims_locale.dart';

class DeviceUnlockService {
  DeviceUnlockService._();

  static final DeviceUnlockService instance = DeviceUnlockService._();
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.authenticate(
        localizedReason: AimsLocaleController.instance.t('device_unlock_reason'),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
