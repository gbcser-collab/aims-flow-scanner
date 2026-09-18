import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class RuntimeFirebaseOptions {
  RuntimeFirebaseOptions._();

  // Firebase Android client identifiers from the registered AIMS Flow app.
  // These values are client-side identifiers and are present in every APK.
  // GitHub/CI dart-defines can still override them without changing the app.
  static const _fallbackApiKey = 'AIzaSyAAi61i7YCVXJ7Lh5QY0cYnZ42LISC-vNQ';
  static const _fallbackProjectId = 'aims-flow';
  static const _fallbackSenderId = '271406385287';
  static const _fallbackAndroidAppId =
      '1:271406385287:android:83e6c1cdc361ebfe289022';
  static const _fallbackStorageBucket = 'aims-flow.firebasestorage.app';

  static const _apiKey = String.fromEnvironment(
    'AIMS_FIREBASE_API_KEY',
    defaultValue: _fallbackApiKey,
  );
  static const _projectId = String.fromEnvironment(
    'AIMS_FIREBASE_PROJECT_ID',
    defaultValue: _fallbackProjectId,
  );
  static const _senderId = String.fromEnvironment(
    'AIMS_FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: _fallbackSenderId,
  );
  static const _androidAppId = String.fromEnvironment(
    'AIMS_FIREBASE_ANDROID_APP_ID',
    defaultValue: _fallbackAndroidAppId,
  );
  static const _iosAppId = String.fromEnvironment(
    'AIMS_FIREBASE_IOS_APP_ID',
    defaultValue: '',
  );
  static const _storageBucket = String.fromEnvironment(
    'AIMS_FIREBASE_STORAGE_BUCKET',
    defaultValue: _fallbackStorageBucket,
  );

  static FirebaseOptions? get current {
    if (_apiKey.isEmpty || _projectId.isEmpty || _senderId.isEmpty) {
      return null;
    }

    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId,
      TargetPlatform.iOS => _iosAppId,
      _ => '',
    };
    if (appId.isEmpty) return null;

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
    );
  }
}
