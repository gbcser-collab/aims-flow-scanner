import 'flow_account_service.dart';
import 'flow_local_journal.dart';

/// A completed storage read may authorize only the foreground generation that
/// requested it. Pausing/disposal invalidates delayed reads immediately.
class ForegroundSessionGuard {
  ForegroundSessionGuard({Future<FlowAccountSession?> Function()? loadSession})
      : _loadSession = loadSession ?? FlowSessionStore.instance.load;
  final Future<FlowAccountSession?> Function() _loadSession;
  bool _foreground = true;
  int _generation = 0;

  void pause() { _foreground = false; _generation++; }
  void resume() { _foreground = true; _generation++; }

  Future<bool> authorize(FlowAccountSession? expected) async {
    if (!_foreground) return false;
    final generation = _generation;
    final current = await _loadSession();
    if (!_foreground || generation != _generation) return false;
    if (expected == null || current == null || current.isExpired ||
        current.flowId != expected.flowId || current.sessionToken != expected.sessionToken ||
        flowJournalPlate(current.plate) != flowJournalPlate(expected.plate)) {
      throw const FlowSessionChanged();
    }
    return true;
  }
}
