import 'tracking_models.dart';

class DocPoint {
  const DocPoint(this.x, this.y);
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class DocumentCorners {
  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final DocPoint topLeft;
  final DocPoint topRight;
  final DocPoint bottomRight;
  final DocPoint bottomLeft;

  List<DocPoint> get ordered => [topLeft, topRight, bottomRight, bottomLeft];
}

class ScanQuality {
  const ScanQuality({
    required this.brightness,
    required this.sharpness,
    required this.glareRatio,
    required this.documentFillRatio,
  });

  final double brightness;
  final double sharpness;
  final double glareRatio;
  final double documentFillRatio;

  bool get isTooDark => brightness < 58;
  bool get isTooBright => brightness > 225;
  bool get isBlurry => sharpness < 70;
  bool get hasTooMuchGlare => glareRatio > 0.07;
  bool get documentTooSmall => documentFillRatio < 0.35;

  int get score {
    var result = 100;
    if (isTooDark || isTooBright) result -= 20;
    if (isBlurry) result -= 25;
    if (hasTooMuchGlare) result -= 20;
    if (documentTooSmall) result -= 15;
    return result.clamp(0, 100);
  }

  List<String> get warnings {
    final result = <String>[];
    if (isTooDark) result.add('Túl sötét a dokumentum.');
    if (isTooBright) result.add('Túl világos a dokumentum.');
    if (isBlurry) result.add('A kép életlennek tűnik.');
    if (hasTooMuchGlare) result.add('Erős becsillanás érzékelhető.');
    if (documentTooSmall) result.add('Túl kicsi a dokumentum a képen.');
    return result;
  }

  bool get isAcceptable => warnings.isEmpty;
}

class ScanProcessingResult {
  const ScanProcessingResult({
    required this.outputPath,
    required this.corners,
    required this.quality,
  });

  final String outputPath;
  final DocumentCorners corners;
  final ScanQuality quality;
}

class CmrData {
  const CmrData({
    this.cmrNumber,
    this.shipper,
    this.consignee,
    this.loadingPlace,
    this.deliveryPlace,
    this.date,
    this.plate,
    this.packageCount,
    this.grossWeightKg,
    this.goodsDescription,
    this.rawText = '',
  });

  final String? cmrNumber;
  final String? shipper;
  final String? consignee;
  final String? loadingPlace;
  final String? deliveryPlace;
  final String? date;
  final String? plate;
  final int? packageCount;
  final double? grossWeightKg;
  final String? goodsDescription;
  final String rawText;

  Map<String, dynamic> toJson() => {
        'cmrNumber': cmrNumber,
        'shipper': shipper,
        'consignee': consignee,
        'loadingPlace': loadingPlace,
        'deliveryPlace': deliveryPlace,
        'date': date,
        'plate': plate,
        'packageCount': packageCount,
        'grossWeightKg': grossWeightKg,
        'goodsDescription': goodsDescription,
        'rawText': rawText,
      };

  factory CmrData.fromJson(Map<String, dynamic> json) => CmrData(
        cmrNumber: json['cmrNumber'] as String?,
        shipper: json['shipper'] as String?,
        consignee: json['consignee'] as String?,
        loadingPlace: json['loadingPlace'] as String?,
        deliveryPlace: json['deliveryPlace'] as String?,
        date: json['date'] as String?,
        plate: json['plate'] as String?,
        packageCount: json['packageCount'] as int?,
        grossWeightKg: (json['grossWeightKg'] as num?)?.toDouble(),
        goodsDescription: json['goodsDescription'] as String?,
        rawText: (json['rawText'] as String?) ?? '',
      );
}

class ValidationIssue {
  const ValidationIssue({required this.field, required this.message, required this.severity});
  final String field;
  final String message;
  final IssueSeverity severity;
}

enum IssueSeverity { info, warning, error }
enum CmrSyncState { pending, uploaded, emailed, approved, failed }

class ScannedDocument {
  const ScannedDocument({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.cmr,
    required this.quality,
    this.location,
    this.syncState = CmrSyncState.pending,
    this.serverDocumentId,
    this.uploadedAt,
    this.emailedAt,
    this.approvedAt,
    this.deleteAfter,
    this.lastSyncError,
  });

  final String id;
  final DateTime createdAt;
  final String imagePath;
  final CmrData cmr;
  final ScanQuality quality;
  final LocationStamp? location;
  final CmrSyncState syncState;
  final String? serverDocumentId;
  final DateTime? uploadedAt;
  final DateTime? emailedAt;
  final DateTime? approvedAt;
  final DateTime? deleteAfter;
  final String? lastSyncError;

  bool get needsSync => syncState == CmrSyncState.pending || syncState == CmrSyncState.failed || syncState == CmrSyncState.uploaded;

  ScannedDocument copyWith({
    CmrData? cmr,
    LocationStamp? location,
    bool clearLocation = false,
    CmrSyncState? syncState,
    String? serverDocumentId,
    DateTime? uploadedAt,
    DateTime? emailedAt,
    DateTime? approvedAt,
    DateTime? deleteAfter,
    String? lastSyncError,
    bool clearLastSyncError = false,
  }) =>
      ScannedDocument(
        id: id,
        createdAt: createdAt,
        imagePath: imagePath,
        cmr: cmr ?? this.cmr,
        quality: quality,
        location: clearLocation ? null : (location ?? this.location),
        syncState: syncState ?? this.syncState,
        serverDocumentId: serverDocumentId ?? this.serverDocumentId,
        uploadedAt: uploadedAt ?? this.uploadedAt,
        emailedAt: emailedAt ?? this.emailedAt,
        approvedAt: approvedAt ?? this.approvedAt,
        deleteAfter: deleteAfter ?? this.deleteAfter,
        lastSyncError: clearLastSyncError ? null : (lastSyncError ?? this.lastSyncError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'imagePath': imagePath,
        'cmr': cmr.toJson(),
        'quality': {
          'brightness': quality.brightness,
          'sharpness': quality.sharpness,
          'glareRatio': quality.glareRatio,
          'documentFillRatio': quality.documentFillRatio,
        },
        'location': location?.toJson(),
        'sync': {
          'state': syncState.name,
          'serverDocumentId': serverDocumentId,
          'uploadedAt': uploadedAt?.toIso8601String(),
          'emailedAt': emailedAt?.toIso8601String(),
          'approvedAt': approvedAt?.toIso8601String(),
          'deleteAfter': deleteAfter?.toIso8601String(),
          'lastError': lastSyncError,
        },
      };

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    final q = Map<String, dynamic>.from(json['quality'] as Map);
    final locationJson = json['location'];
    final syncJson = json['sync'] is Map ? Map<String, dynamic>.from(json['sync'] as Map) : <String, dynamic>{};
    final stateName = syncJson['state'] as String?;
    final state = CmrSyncState.values.where((item) => item.name == stateName).firstOrNull ?? CmrSyncState.pending;

    DateTime? parseDate(dynamic value) => value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

    return ScannedDocument(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      imagePath: json['imagePath'] as String,
      cmr: CmrData.fromJson(Map<String, dynamic>.from(json['cmr'] as Map)),
      quality: ScanQuality(
        brightness: (q['brightness'] as num).toDouble(),
        sharpness: (q['sharpness'] as num).toDouble(),
        glareRatio: (q['glareRatio'] as num).toDouble(),
        documentFillRatio: (q['documentFillRatio'] as num).toDouble(),
      ),
      location: locationJson is Map ? LocationStamp.fromJson(Map<String, dynamic>.from(locationJson)) : null,
      syncState: state,
      serverDocumentId: syncJson['serverDocumentId'] as String?,
      uploadedAt: parseDate(syncJson['uploadedAt']),
      emailedAt: parseDate(syncJson['emailedAt']),
      approvedAt: parseDate(syncJson['approvedAt']),
      deleteAfter: parseDate(syncJson['deleteAfter']),
      lastSyncError: syncJson['lastError'] as String?,
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
