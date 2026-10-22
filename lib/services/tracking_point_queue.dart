import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One writer per installation. A failed write never truncates the live queue.
class TrackingPointQueue {
  TrackingPointQueue({required this.directory, this.beforeReplace});

  final Future<Directory> Function() directory;
  // Fault injection at the durable-write boundary for regression tests.
  final Future<void> Function(File temporary)? beforeReplace;
  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<File> _file(String name) async {
    final root = await directory();
    await root.create(recursive: true);
    return File('${root.path}/$name');
  }

  Future<List<String>> _read(File file) async => await file.exists()
      ? (await file.readAsLines()).where((line) => line.trim().isNotEmpty).toList()
      : <String>[];

  Future<void> _replace(File file, List<String> lines) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      lines.isEmpty ? '' : '${lines.join('\n')}\n', flush: true,
    );
    await beforeReplace?.call(temporary);
    // Same-directory rename: never delete/truncate the live file beforehand.
    await temporary.rename(file.path);
  }

  Future<List<String>> snapshot() => _locked(() async =>
      _read(await _file('aims_tracking_queue.jsonl')));

  Future<int> quarantinedCount() => _locked(() async =>
      (await _read(await _file('aims_tracking_queue_corrupt.jsonl'))).length);

  Future<void> append(String line) => _locked(() async {
    if (line.contains('\n') || line.contains('\r')) {
      throw const FormatException('A GPS-bejegyzés csak egy sor lehet.');
    }
    final file = await _file('aims_tracking_queue.jsonl');
    final lines = await _read(file);
    lines.add(line);
    // Unacknowledged data is never removed to enforce a count limit.
    await _replace(file, lines);
  });

  Future<void> acknowledge(List<String> consumed) => _locked(() async {
    if (consumed.isEmpty) return;
    final file = await _file('aims_tracking_queue.jsonl');
    final lines = await _read(file);
    final counts = <String, int>{};
    for (final line in consumed) {
      counts[line] = (counts[line] ?? 0) + 1;
    }
    final remaining = <String>[];
    for (final line in lines) {
      final count = counts[line] ?? 0;
      if (count > 0) {
        counts[line] = count - 1;
      } else {
        remaining.add(line);
      }
    }
    await _replace(file, remaining);
  });

  Future<void> quarantine(String line, String reason) => _locked(() async {
    final file = await _file('aims_tracking_queue_corrupt.jsonl');
    final lines = await _read(file);
    lines.add(jsonEncode({
      'quarantinedAt': DateTime.now().toUtc().toIso8601String(),
      'reason': reason, 'raw': line,
    }));
    // Persist the rejected record before the caller acknowledges it.
    await _replace(file, lines);
  });
}
