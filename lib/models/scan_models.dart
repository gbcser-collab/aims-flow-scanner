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

  int get score {
    var value = 100;
    if (isTooDark) value -= 20;
    if (isTooBright) value -= 20;
    if (isBlurry) value -= 25;
    if (hasTooMuchGlare) value -= 20;
    if (documentTooSmall) value -= 15;
    return value.clamp(0, 100).toInt();
  }
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

class ScanLocation {
  const ScanLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;

  String get coordinates => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory ScanLocation.fromJson(Map<String, dynamic> json) => ScanLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble() ?? 0,
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ?? DateTime.now(),
      );
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

  int get filledFieldCount {
    final values = <Object?>[
      cmrNumber,
      shipper,
      consignee,
      loadingPlace,
      deliveryPlace,
      date,
      plate,
      packageCount,
      grossWeightKg,
      goodsDescription,
    ];
    return values.where((value) {
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      return true;
    }).length;
  }

  double get completion => filledFieldCount / 10;

  String toPlainText() {
    String value(Object? input) => input == null || input.toString().trim().isEmpty ? '—' : input.toString().trim();
    return [
      'CMR: ${value(cmrNumber)}',
      'Feladó: ${value(shipper)}',
      'Címzett: ${value(consignee)}',
      'Felrakóhely: ${value(loadingPlace)}',
      'Lerakóhely: ${value(deliveryPlace)}',
      'Dátum: ${value(date)}',
      'Rendszám: ${value(plate)}',
      'Darabszám: ${value(packageCount)}',
      'Bruttó tömeg: ${grossWeightKg == null ? '—' : '${grossWeightKg!.toStringAsFixed(grossWeightKg! % 1 == 0 ? 0 : 2)} kg'}',
      'Áru: ${value(goodsDescription)}',
    ].join('\n');
  }

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

class ScannedDocument {
  const ScannedDocument({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.cmr,
    required this.quality,
    this.location,
  });

  final String id;
  final DateTime createdAt;
  final String imagePath;
  final CmrData cmr;
  final ScanQuality quality;
  final ScanLocation? location;

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
      };

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    final q = json['quality'] as Map<String, dynamic>;
    final rawLocation = json['location'];
    return ScannedDocument(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      imagePath: json['imagePath'] as String,
      cmr: CmrData.fromJson(json['cmr'] as Map<String, dynamic>),
      quality: ScanQuality(
        brightness: (q['brightness'] as num).toDouble(),
        sharpness: (q['sharpness'] as num).toDouble(),
        glareRatio: (q['glareRatio'] as num).toDouble(),
        documentFillRatio: (q['documentFillRatio'] as num).toDouble(),
      ),
      location: rawLocation is Map
          ? ScanLocation.fromJson(Map<String, dynamic>.from(rawLocation))
          : null,
    );
  }
}
