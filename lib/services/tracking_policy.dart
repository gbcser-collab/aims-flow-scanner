/// Hysteresis prevents traffic lights and GPS jitter from changing profiles.
class TrackingPolicy {
  DateTime? _quietSince;
  DateTime? _lastSample;
  DateTime? _lastSaved;
  bool stationary = false;

  Duration get sampleInterval => Duration(seconds: stationary ? 60 : 15);
  Duration get saveInterval => Duration(seconds: stationary ? 120 : 15);
  Duration get staleAfter => Duration(seconds: stationary ? 210 : 120);

  bool observe({required DateTime at, required double speedMps,
    required double distanceM, required double accuracyM}) {
    if (_lastSample != null && !at.isAfter(_lastSample!)) return false;
    if (_lastSample != null && at.difference(_lastSample!) > const Duration(minutes: 3)) {
      _quietSince = null;
    }
    _lastSample = at;
    final before = stationary;
    // An unreliable fix must never convince us that the truck has parked.
    if (accuracyM > 35 || speedMps >= 1.5 || distanceM > 35) {
      _quietSince = null;
      stationary = false;
    } else {
      _quietSince ??= at;
      if (at.difference(_quietSince!) >= const Duration(minutes: 2)) stationary = true;
    }
    return stationary != before;
  }

  bool shouldSave(DateTime at) => _lastSaved == null ||
      at.difference(_lastSaved!) >= saveInterval;
  void saved(DateTime at) { _lastSaved = at; }
  void reset() {
    _quietSince = null;
    _lastSample = null;
    _lastSaved = null;
    stationary = false;
  }
}

/// Every automatic caller respects the same deadline. A new GPS point cannot
/// undo backoff; a validated connection or explicit retry can bypass it once.
class TrackingRetryGate {
  DateTime? retryAt;
  int failures = 0;
  bool ready(DateTime now) => retryAt == null || !now.isBefore(retryAt!);
  Duration fail(DateTime now, {Duration minimum = Duration.zero}) {
    const seconds = [2, 5, 10, 30, 60, 120, 300];
    final index = failures.clamp(0, seconds.length - 1);
    failures++;
    final delay = Duration(seconds: seconds[index]);
    final effective = delay < minimum ? minimum : delay;
    retryAt = now.add(effective);
    return effective;
  }
  void retryNow() { retryAt = null; }
  void succeeded() { failures = 0; retryAt = null; }
}
