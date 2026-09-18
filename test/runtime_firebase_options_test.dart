import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aims_flow_scanner/services/runtime_firebase_options.dart';

void main() {
  test('AIMS Flow Android Firebase client is configured', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final options = RuntimeFirebaseOptions.current;

    expect(options, isNotNull);
    expect(options!.projectId, 'aims-flow');
    expect(options.messagingSenderId, '271406385287');
    expect(
      options.appId,
      '1:271406385287:android:83e6c1cdc361ebfe289022',
    );
    expect(options.apiKey, isNotEmpty);
    expect(options.storageBucket, 'aims-flow.firebasestorage.app');
  });
}
