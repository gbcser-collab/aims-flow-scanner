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

/// Start every independent cleanup even if another one throws or stalls.
/// Report the first failure only after all bounded cleanup attempts finish.
Future<void> finishTrackingCleanup(List<Future<void> Function()> actions, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  Object? firstError;
  StackTrace? firstStack;
  await Future.wait(actions.map((action) async {
    try {
      await Future<void>.sync(action).timeout(timeout);
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
  }));
  if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
}
