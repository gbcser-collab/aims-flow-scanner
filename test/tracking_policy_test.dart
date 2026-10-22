import 'package:flutter_test/flutter_test.dart';
import 'package:aims_flow_scanner/services/tracking_policy.dart';

void main() {
  final start = DateTime.utc(2026, 10, 22, 8);
  test('short stops do not switch profiles; two minutes of stillness do', () {
    final policy = TrackingPolicy();
    for (var s = 0; s < 120; s += 15) {
      policy.observe(at: start.add(Duration(seconds: s)), speedMps: 0,
        distanceM: 2, accuracyM: 8);
      expect(policy.stationary, isFalse);
    }
    policy.observe(at: start.add(const Duration(seconds: 120)), speedMps: 0,
      distanceM: 3, accuracyM: 8);
    expect(policy.stationary, isTrue);
    expect(policy.sampleInterval, const Duration(seconds: 60));
    expect(policy.saveInterval, const Duration(seconds: 120));
  });

  test('movement and displacement immediately restore driving profile', () {
    for (final speed in [0.0, 12.0]) {
      final p = TrackingPolicy();
      for (var s = 0; s <= 120; s += 30) {
        p.observe(at: start.add(Duration(seconds: s)), speedMps: 0, distanceM: 0, accuracyM: 10);
      }
      expect(p.stationary, isTrue);
      p.observe(at: start.add(const Duration(seconds: 180)), speedMps: speed,
        distanceM: speed == 0 ? 50 : 0, accuracyM: 10);
      expect(p.stationary, isFalse);
      expect(p.sampleInterval, const Duration(seconds: 15));
    }
  });

  test('poor GPS and a long sample gap cannot establish parking', () {
    final p = TrackingPolicy();
    p.observe(at: start, speedMps: 0, distanceM: 0, accuracyM: 8);
    p.observe(at: start.add(const Duration(minutes: 10)), speedMps: 0, distanceM: 0, accuracyM: 8);
    expect(p.stationary, isFalse);
    for (var s = 630; s <= 800; s += 30) {
      p.observe(at: start.add(Duration(seconds: s)), speedMps: 0, distanceM: 0, accuracyM: 90);
    }
    expect(p.stationary, isFalse);
  });

  test('replayed old fixes cannot reset a moving profile', () {
    final p = TrackingPolicy();
    p.observe(at: start, speedMps: 0, distanceM: 0, accuracyM: 8);
    p.observe(at: start.add(const Duration(seconds: 60)), speedMps: 10, distanceM: 50, accuracyM: 8);
    p.observe(at: start.add(const Duration(seconds: 30)), speedMps: 0, distanceM: 0, accuracyM: 8);
    expect(p.stationary, isFalse);
    p.saved(start);
    expect(p.shouldSave(start.add(const Duration(seconds: 10))), isFalse);
    expect(p.shouldSave(start.add(const Duration(seconds: 15))), isTrue);
  });

  test('offline retry grows to five minutes and GPS arrivals cannot bypass it', () {
    final gate = TrackingRetryGate();
    var now = start;
    for (final seconds in [2, 5, 10, 30, 60, 120, 300, 300]) {
      final delay = gate.fail(now);
      expect(delay.inSeconds, seconds);
      expect(gate.ready(now.add(delay - const Duration(milliseconds: 1))), isFalse);
      now = now.add(delay);
      expect(gate.ready(now), isTrue);
    }
    gate.fail(now, minimum: const Duration(minutes: 5));
    expect(gate.ready(now.add(const Duration(minutes: 4))), isFalse);
    gate.retryNow();
    expect(gate.ready(now), isTrue);
    gate.succeeded();
    expect(gate.fail(now).inSeconds, 2);
  });
}
