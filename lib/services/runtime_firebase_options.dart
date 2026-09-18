import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class RuntimeFirebaseOptions {
  RuntimeFirebaseOptions._();

  static const _apiKey =
      String.fromEnvironment('AIMS_FIREBASE_API_KEY', defaultValue: '');
  static const _projectId =
      String.fromEnvironment('AIMS_FIREBASE_PROJECT_ID', defaultValue: '');
  static const _senderId = String.fromEnvironment(
    'AIMS_FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const _androidAppId = String.fromEnvironment(
    'AIMS_FIREBASE_ANDROID_APP_ID',
    defaultValue: '',
  );
  static const _iosAppId = String.fromEnvironment(
    'AIMS_FIREBASE_IOS_APP_ID',
    defaultValue: '',
  );
  static const _storageBucket = String.fromEnvironment(
    'AIMS_FIREBASE_STORAGE_BUCKET',
    defaultValue: '',
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
