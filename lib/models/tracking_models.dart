class TrackingPoint {
  const TrackingPoint({
    required this.id,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speedMps,
    required this.heading,
    required this.altitude,
    this.isMocked = false,
    this.synced = false,
  });

  final String id;
  final DateTime capturedAt;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speedMps;
  final double heading;
  final double altitude;
  final bool isMocked;
  final bool synced;

  double get speedKmh => speedMps < 0 ? 0 : speedMps * 3.6;

  TrackingPoint copyWith({bool? synced}) => TrackingPoint(
        id: id,
        capturedAt: capturedAt,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        speedMps: speedMps,
        heading: heading,
        altitude: altitude,
        isMocked: isMocked,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speedMps': speedMps,
        'heading': heading,
        'altitude': altitude,
        'isMocked': isMocked,
        'synced': synced,
      };

  factory TrackingPoint.fromJson(Map<String, dynamic> json) => TrackingPoint(
        id: json['id'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
        speedMps: (json['speedMps'] as num?)?.toDouble() ?? 0,
        heading: (json['heading'] as num?)?.toDouble() ?? 0,
        altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
        isMocked: json['isMocked'] as bool? ?? false,
        synced: json['synced'] as bool? ?? false,
      );
}

class TrackingSession {
  const TrackingSession({
    required this.id,
    required this.plate,
    required this.reference,
    required this.startedAt,
    required this.active,
    this.stoppedAt,
    this.serverStarted = false,
    this.serverStopped = false,
    this.lastSyncError,
    this.points = const [],
  });

  final String id;
  final String plate;
  final String reference;
  final DateTime startedAt;
  final bool active;
  final DateTime? stoppedAt;
  final bool serverStarted;
  final bool serverStopped;
  final String? lastSyncError;
  final List<TrackingPoint> points;

  TrackingPoint? get latestPoint => points.isEmpty ? null : points.last;
  int get queuedPointCount => points.where((point) => !point.synced).length;

  TrackingSession copyWith({
    bool? active,
    DateTime? stoppedAt,
    bool? serverStarted,
    bool? serverStopped,
    String? lastSyncError,
    bool clearLastSyncError = false,
    List<TrackingPoint>? points,
  }) => TrackingSession(
        id: id,
        plate: plate,
        reference: reference,
        startedAt: startedAt,
        active: active ?? this.active,
        stoppedAt: stoppedAt ?? this.stoppedAt,
        serverStarted: serverStarted ?? this.serverStarted,
        serverStopped: serverStopped ?? this.serverStopped,
        lastSyncError: clearLastSyncError ? null : (lastSyncError ?? this.lastSyncError),
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plate': plate,
        'reference': reference,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'active': active,
        'stoppedAt': stoppedAt?.toUtc().toIso8601String(),
        'serverStarted': serverStarted,
        'serverStopped': serverStopped,
        'lastSyncError': lastSyncError,
        'points': points.map((point) => point.toJson()).toList(),
      };

  factory TrackingSession.fromJson(Map<String, dynamic> json) => TrackingSession(
        id: json['id'] as String,
        plate: json['plate'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        startedAt: DateTime.parse(json['startedAt'] as String),
        active: json['active'] as bool? ?? false,
        stoppedAt: json['stoppedAt'] == null ? null : DateTime.tryParse(json['stoppedAt'].toString()),
        serverStarted: json['serverStarted'] as bool? ?? false,
        serverStopped: json['serverStopped'] as bool? ?? false,
        lastSyncError: json['lastSyncError'] as String?,
        points: ((json['points'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => TrackingPoint.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}
