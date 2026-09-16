import 'package:flutter/foundation.dart';

import '../models/freight_models.dart';
import 'driver_flow_repository.dart';

class DriverFlowController extends ChangeNotifier {
  DriverFlowController._();

  static final DriverFlowController instance = DriverFlowController._();

  final DriverFlowRepository _repository = const DriverFlowRepository();
  FreightOperationState _state = FreightOperationState.initial();
  bool _initialized = false;
  bool _saving = false;

  FreightOperationState get state => _state;
  bool get initialized => _initialized;
  bool get saving => _saving;

  Future<void> initialize() async {
    if (_initialized) return;
    final stored = await _repository.load();
    if (stored != null) _state = stored;
    _initialized = true;
    notifyListeners();
  }

  Future<void> _commit(FreightOperationState next) async {
    _state = next.copyWith(updatedAt: DateTime.now());
    notifyListeners();
    _saving = true;
    notifyListeners();
    await _repository.save(_state);
    _saving = false;
    notifyListeners();
  }

  FlowEvent _event(String title, {String? detail, FlowEventLevel level = FlowEventLevel.info}) {
    final now = DateTime.now();
    return FlowEvent(
      id: 'evt_${now.microsecondsSinceEpoch}',
      title: title,
      detail: detail,
      createdAt: now,
      level: level,
    );
  }

  List<FlowEvent> _withEvent(FlowEvent event) => [event, ..._state.events].take(250).toList();

  Future<bool> advanceStage() async {
    final current = _state.stage;
    if (!current.canDriverAdvance) return false;

    if (current == FreightStage.accepted && !_state.checklistComplete) {
      await addEvent(
        'Indulás blokkolva',
        detail: 'Az indulás előtti checklist még nincs teljesen kipipálva.',
        level: FlowEventLevel.warning,
      );
      return false;
    }

    final next = current.next;
    await _commit(_state.copyWith(
      stage: next,
      events: _withEvent(_event(
        next.label,
        detail: 'Fuvarállapot frissítve: ${current.label} → ${next.label}',
        level: next == FreightStage.completed ? FlowEventLevel.success : FlowEventLevel.info,
      )),
    ));
    return true;
  }

  Future<void> setJobDetails({
    required String reference,
    required String plate,
    required String pickup,
    required String delivery,
  }) async {
    final cleanReference = reference.trim().isEmpty ? _state.reference : reference.trim();
    await _commit(_state.copyWith(
      reference: cleanReference,
      plate: plate.trim().toUpperCase(),
      pickup: pickup.trim().isEmpty ? 'Felrakó' : pickup.trim(),
      delivery: delivery.trim().isEmpty ? 'Lerakó' : delivery.trim(),
      events: _withEvent(_event('Fuvaradatok frissítve', detail: cleanReference)),
    ));
  }

  Future<void> setChecklistItem(String item, bool value) async {
    final checklist = Map<String, bool>.from(_state.checklist)..[item] = value;
    final completed = checklist.values.every((v) => v);
    await _commit(_state.copyWith(
      checklist: checklist,
      events: completed && !_state.checklistComplete
          ? _withEvent(_event('Checklist kész', detail: 'Minden indulás előtti ellenőrzés teljesítve.', level: FlowEventLevel.success))
          : _state.events,
    ));
  }

  Future<void> addEvent(
    String title, {
    String? detail,
    FlowEventLevel level = FlowEventLevel.info,
  }) async {
    await _commit(_state.copyWith(events: _withEvent(_event(title, detail: detail, level: level))));
  }

  Future<void> addIncident({
    required IncidentKind kind,
    required String note,
    bool critical = false,
  }) async {
    final now = DateTime.now();
    final incident = FreightIncident(
      id: 'inc_${now.microsecondsSinceEpoch}',
      kind: kind,
      note: note.trim().isEmpty ? kind.label : note.trim(),
      createdAt: now,
      critical: critical,
    );
    await _commit(_state.copyWith(
      incidents: [incident, ..._state.incidents],
      events: _withEvent(_event(
        critical ? 'KRITIKUS · ${kind.label}' : kind.label,
        detail: incident.note,
        level: critical ? FlowEventLevel.critical : FlowEventLevel.warning,
      )),
    ));
  }

  Future<void> addNote(String note) async {
    final clean = note.trim();
    if (clean.isEmpty) return;
    await _commit(_state.copyWith(
      notes: [clean, ..._state.notes].take(100).toList(),
      events: _withEvent(_event('Sofőr megjegyzés', detail: clean)),
    ));
  }

  Future<void> addEvidence({String label = 'Bizonyíték'}) async {
    await _commit(_state.copyWith(
      evidenceCount: _state.evidenceCount + 1,
      events: _withEvent(_event(label, detail: 'Bizonyíték hozzáadva a fuvarcsomaghoz.', level: FlowEventLevel.success)),
    ));
  }

  Future<void> startWaiting() async {
    if (_state.waitingActive) return;
    final now = DateTime.now();
    await _commit(_state.copyWith(
      waitingStartedAt: now,
      events: _withEvent(_event('Várakozás indult', detail: 'Kezdés: ${_clock(now)}', level: FlowEventLevel.warning)),
    ));
  }

  Future<void> stopWaiting() async {
    final started = _state.waitingStartedAt;
    if (started == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(started).inSeconds.clamp(0, 86400 * 7).toInt();
    await _commit(_state.copyWith(
      clearWaitingStartedAt: true,
      accumulatedWaitingSeconds: _state.accumulatedWaitingSeconds + elapsed,
      events: _withEvent(_event(
        'Várakozás lezárva',
        detail: 'Időtartam: ${_duration(Duration(seconds: elapsed))}',
        level: FlowEventLevel.success,
      )),
    ));
  }

  Future<void> markAdminApproved() async {
    if (_state.stage != FreightStage.completed) return;
    await _commit(_state.copyWith(
      stage: FreightStage.adminApproved,
      events: _withEvent(_event('Admin jóváhagyta', detail: _state.reference, level: FlowEventLevel.success)),
    ));
  }

  Future<void> resetForNextFreight() async {
    await _repository.clear();
    _state = FreightOperationState.initial();
    notifyListeners();
    await _repository.save(_state);
  }

  static String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _duration(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60);
    final s = value.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
