import 'dart:async';

/// One idle-safe local transaction lane. An error never poisons later writes.
class LocalSerialExecutor {
  Future<void>? _tail;
  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    final result = Completer<T>();
    _tail = done.future;
    Future<void> execute() async {
      try {
        if (previous != null) await previous;
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        if (identical(_tail, done.future)) _tail = null;
        done.complete();
      }
    }
    unawaited(execute());
    return result.future;
  }
}
