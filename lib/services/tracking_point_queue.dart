import 'dart:convert';
import 'dart:io';
import 'local_serial_executor.dart';

/// One writer per installation. A failed write never truncates the live queue.
class TrackingPointQueue {
  TrackingPointQueue({required this.directory, this.beforeReplace});

  final Future<Directory> Function() directory;
  // Fault injection at the durable-write boundary for regression tests.
  final Future<void> Function(File temporary)? beforeReplace;
  static final _serial = LocalSerialExecutor();
  int? _knownCount;
  Future<T> _locked<T>(Future<T> Function() action) => _serial.run(action);

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

  Future<void> _recoverAppend({bool freshlyStaged = false}) async {
    final pending = await _file('aims_tracking_append.pending');
    if (!await pending.exists()) return;
    final line = await pending.readAsString();
    if (line.trim().isEmpty || line.contains('\n') || line.contains('\r')) {
      throw const FormatException('A GPS mentési napló sérült; az eredeti adat megmaradt.');
    }
    final file = await _file('aims_tracking_queue.jsonl');
    // Prefixing a newline isolates a partial last line after sudden power loss.
    // Replay can duplicate a point, but its stable server ID makes that safe.
    await file.writeAsString('\n$line\n', mode: FileMode.append, flush: true);
    await pending.delete();
    _knownCount = freshlyStaged && _knownCount != null ? _knownCount! + 1 : null;
  }

  Future<List<String>> snapshot() => _locked(() async {
    await _recoverAppend();
    final lines = await _read(await _file('aims_tracking_queue.jsonl'));
    _knownCount = lines.length;
    return lines;
  });

  Future<int> count() => _locked(() async {
    await _recoverAppend();
    return _knownCount ??= (await _read(await _file('aims_tracking_queue.jsonl'))).length;
  });

  Future<int> quarantinedCount() => _locked(() async =>
      (await _read(await _file('aims_tracking_queue_corrupt.jsonl'))).length);

  Future<void> append(String line) => _locked(() async {
    if (line.trim().isEmpty || line.contains('\n') || line.contains('\r')) {
      throw const FormatException('A GPS-bejegyzés csak egy nem üres sor lehet.');
    }
    await _recoverAppend();
    final pending = await _file('aims_tracking_append.pending');
    final temporary = File('${pending.path}.tmp');
    await temporary.writeAsString(line, flush: true);
    await beforeReplace?.call(temporary);
    await temporary.rename(pending.path);
    await _recoverAppend(freshlyStaged: true);
  });

  Future<void> acknowledge(List<String> consumed) => _locked(() async {
    if (consumed.isEmpty) return;
    await _recoverAppend();
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
    _knownCount = remaining.length;
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
