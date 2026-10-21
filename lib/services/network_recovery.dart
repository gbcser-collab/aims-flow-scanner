import 'dart:async';

import 'package:flutter/services.dart';

/// Coalesces native connectivity transitions without overlapping sync passes.
/// Existing request timeouts and bounded retries remain the fallback when a
/// validated network cannot actually reach the FLOW server.
class NetworkRecovery {
  NetworkRecovery(
    Stream<bool> events,
    this.onRestored, {
    this.debounce = const Duration(milliseconds: 350),
  }) {
    _subscription = events.listen(
      _changed,
      onError: (Object error) => _changed(false),
    );
  }

  static const _channel =
      EventChannel('hu.logisticaims.aims_flow/connectivity');
  static Stream<bool> get androidEvents =>
      _channel.receiveBroadcastStream().map((event) => event == true);

  final Future<void> Function() onRestored;
  final Duration debounce;
  StreamSubscription<bool>? _subscription;
  Timer? _timer;
  bool _online = false;
  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  void _changed(bool online) {
    if (_disposed || _online == online) return;
    _online = online;
    _timer?.cancel();
    if (!online) {
      _pending = false;
      return;
    }
    _timer = Timer(debounce, () => unawaited(_recover()));
  }

  Future<void> _recover() async {
    if (_disposed || !_online) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      await onRestored();
    } catch (_) {
      // A network notification is a retry hint, not a delivery guarantee.
    } finally {
      _running = false;
      if (_pending && !_disposed && _online) {
        _pending = false;
        _timer = Timer(debounce, () => unawaited(_recover()));
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _pending = false;
    _timer?.cancel();
    await _subscription?.cancel();
  }
}
