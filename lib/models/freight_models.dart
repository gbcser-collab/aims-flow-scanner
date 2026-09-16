import 'dart:convert';

enum FreightStage {
  assigned,
  accepted,
  toPickup,
  atPickup,
  loaded,
  toDelivery,
  atDelivery,
  cmrReview,
  completed,
  adminApproved,
}

extension FreightStageX on FreightStage {
  String get label => switch (this) {
        FreightStage.assigned => 'KIADVA',
        FreightStage.accepted => 'ELFOGADVA',
        FreightStage.toPickup => 'ÚTON FELRAKÓRA',
        FreightStage.atPickup => 'FELRAKÓN',
        FreightStage.loaded => 'FELRAKVA',
        FreightStage.toDelivery => 'ÚTON LERAKÓRA',
        FreightStage.atDelivery => 'LERAKÓN',
        FreightStage.cmrReview => 'CMR ELLENŐRZÉS',
        FreightStage.completed => 'TELJESÍTVE',
        FreightStage.adminApproved => 'ADMIN JÓVÁHAGYVA',
      };

  String get nextAction => switch (this) {
        FreightStage.assigned => 'FUVAR ELFOGADÁSA',
        FreightStage.accepted => 'INDULÁS FELRAKÓRA',
        FreightStage.toPickup => 'ÉRKEZÉS FELRAKÓRA',
        FreightStage.atPickup => 'FELRAKÁS KÉSZ',
        FreightStage.loaded => 'INDULÁS LERAKÓRA',
        FreightStage.toDelivery => 'ÉRKEZÉS LERAKÓRA',
        FreightStage.atDelivery => 'LERAKÁS KÉSZ',
        FreightStage.cmrReview => 'FUVAR LEZÁRÁSA',
        FreightStage.completed => 'ADMIN JÓVÁHAGYÁSRA VÁR',
        FreightStage.adminApproved => 'FUVAR LEZÁRVA',
      };

  double get progress => index / (FreightStage.values.length - 1);

  bool get canDriverAdvance => this != FreightStage.completed && this != FreightStage.adminApproved;

  FreightStage get next => canDriverAdvance ? FreightStage.values[index + 1] : this;
}

enum FlowEventLevel { info, warning, critical, success }

enum IncidentKind { waiting, damage, address, vehicle, cargo, document, other }

extension IncidentKindX on IncidentKind {
  String get label => switch (this) {
        IncidentKind.waiting => 'Várakozás',
        IncidentKind.damage => 'Sérülés / kár',
        IncidentKind.address => 'Címhiba',
        IncidentKind.vehicle => 'Járműhiba',
        IncidentKind.cargo => 'Rakományprobléma',
        IncidentKind.document => 'Dokumentumhiba',
        IncidentKind.other => 'Egyéb',
      };
}

class FlowEvent {
  const FlowEvent({
    required this.id,
    required this.title,
    required this.createdAt,
    this.detail,
    this.level = FlowEventLevel.info,
  });

  final String id;
  final String title;
  final String? detail;
  final DateTime createdAt;
  final FlowEventLevel level;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'detail': detail,
        'createdAt': createdAt.toIso8601String(),
        'level': level.name,
      };

  factory FlowEvent.fromJson(Map<String, dynamic> json) => FlowEvent(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        detail: json['detail']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        level: FlowEventLevel.values.firstWhere((e) => e.name == json['level'], orElse: () => FlowEventLevel.info),
      );
}

class FreightIncident {
  const FreightIncident({
    required this.id,
    required this.kind,
    required this.note,
    required this.createdAt,
    this.critical = false,
  });

  final String id;
  final IncidentKind kind;
  final String note;
  final DateTime createdAt;
  final bool critical;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'critical': critical,
      };

  factory FreightIncident.fromJson(Map<String, dynamic> json) => FreightIncident(
        id: json['id']?.toString() ?? '',
        kind: IncidentKind.values.firstWhere((e) => e.name == json['kind'], orElse: () => IncidentKind.other),
        note: json['note']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        critical: json['critical'] == true,
      );
}

class FreightOperationState {
  const FreightOperationState({
    required this.reference,
    required this.plate,
    required this.pickup,
    required this.delivery,
    required this.stage,
    required this.updatedAt,
    required this.checklist,
    required this.events,
    required this.incidents,
    required this.notes,
    required this.evidenceCount,
    this.waitingStartedAt,
    this.accumulatedWaitingSeconds = 0,
  });

  final String reference;
  final String plate;
  final String pickup;
  final String delivery;
  final FreightStage stage;
  final DateTime updatedAt;
  final Map<String, bool> checklist;
  final List<FlowEvent> events;
  final List<FreightIncident> incidents;
  final List<String> notes;
  final int evidenceCount;
  final DateTime? waitingStartedAt;
  final int accumulatedWaitingSeconds;

  bool get checklistComplete => checklist.isNotEmpty && checklist.values.every((v) => v);
  bool get waitingActive => waitingStartedAt != null;
  int get completedChecklistItems => checklist.values.where((v) => v).length;

  Duration waitingDuration(DateTime now) {
    final live = waitingStartedAt == null ? 0 : now.difference(waitingStartedAt!).inSeconds;
    return Duration(seconds: accumulatedWaitingSeconds + live);
  }

  FreightOperationState copyWith({
    String? reference,
    String? plate,
    String? pickup,
    String? delivery,
    FreightStage? stage,
    DateTime? updatedAt,
    Map<String, bool>? checklist,
    List<FlowEvent>? events,
    List<FreightIncident>? incidents,
    List<String>? notes,
    int? evidenceCount,
    DateTime? waitingStartedAt,
    bool clearWaitingStartedAt = false,
    int? accumulatedWaitingSeconds,
  }) {
    return FreightOperationState(
      reference: reference ?? this.reference,
      plate: plate ?? this.plate,
      pickup: pickup ?? this.pickup,
      delivery: delivery ?? this.delivery,
      stage: stage ?? this.stage,
      updatedAt: updatedAt ?? this.updatedAt,
      checklist: checklist ?? this.checklist,
      events: events ?? this.events,
      incidents: incidents ?? this.incidents,
      notes: notes ?? this.notes,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      waitingStartedAt: clearWaitingStartedAt ? null : (waitingStartedAt ?? this.waitingStartedAt),
      accumulatedWaitingSeconds: accumulatedWaitingSeconds ?? this.accumulatedWaitingSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'plate': plate,
        'pickup': pickup,
        'delivery': delivery,
        'stage': stage.name,
        'updatedAt': updatedAt.toIso8601String(),
        'checklist': checklist,
        'events': events.map((e) => e.toJson()).toList(),
        'incidents': incidents.map((e) => e.toJson()).toList(),
        'notes': notes,
        'evidenceCount': evidenceCount,
        'waitingStartedAt': waitingStartedAt?.toIso8601String(),
        'accumulatedWaitingSeconds': accumulatedWaitingSeconds,
      };

  String encode() => jsonEncode(toJson());

  factory FreightOperationState.fromJson(Map<String, dynamic> json) {
    final checklistRaw = json['checklist'] as Map? ?? const {};
    return FreightOperationState(
      reference: json['reference']?.toString() ?? 'AF-NEW',
      plate: json['plate']?.toString() ?? '',
      pickup: json['pickup']?.toString() ?? 'Felrakó',
      delivery: json['delivery']?.toString() ?? 'Lerakó',
      stage: FreightStage.values.firstWhere((e) => e.name == json['stage'], orElse: () => FreightStage.assigned),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      checklist: checklistRaw.map((key, value) => MapEntry(key.toString(), value == true)),
      events: (json['events'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FlowEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      incidents: (json['incidents'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FreightIncident.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      notes: (json['notes'] as List? ?? const []).map((e) => e.toString()).toList(),
      evidenceCount: int.tryParse(json['evidenceCount']?.toString() ?? '') ?? 0,
      waitingStartedAt: DateTime.tryParse(json['waitingStartedAt']?.toString() ?? ''),
      accumulatedWaitingSeconds: int.tryParse(json['accumulatedWaitingSeconds']?.toString() ?? '') ?? 0,
    );
  }

  static FreightOperationState initial() {
    final now = DateTime.now();
    return FreightOperationState(
      reference: 'AF-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-01',
      plate: '',
      pickup: 'Felrakó',
      delivery: 'Lerakó',
      stage: FreightStage.assigned,
      updatedAt: now,
      checklist: const {
        'Jármű külső állapot': false,
        'Gumik és világítás': false,
        'Üzemanyag / hatótáv': false,
        'Rakományrögzítés': false,
        'CMR / fuvarokmány': false,
        'Kötelező felszerelés': false,
      },
      events: [
        FlowEvent(
          id: 'evt_${now.microsecondsSinceEpoch}',
          title: 'Műveleti rendszer elindult',
          detail: 'A fuvar offline módban is kezelhető.',
          createdAt: now,
          level: FlowEventLevel.success,
        ),
      ],
      incidents: const [],
      notes: const [],
      evidenceCount: 0,
    );
  }
}
