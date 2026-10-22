import 'dart:async';

/// Stop location collection before attempting any potentially slow upload.
Future<void> stopTrackingBeforeSync({
  required Future<void> Function() stop,
  required Future<void> Function() sync,
}) async {
  await stop();
  // The queue owns retry/error reporting; network availability must not delay
  // completion of a local workday shutdown.
  unawaited(Future<void>.sync(sync).catchError((Object _) {}));
}
