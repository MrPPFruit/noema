enum MediaKind { photo, video, livePhoto, raw, unknown }

enum AssetAvailability { available, unavailable }

class PhotoExif {
  const PhotoExif({
    this.iso,
    this.shutterSpeed,
    this.aperture,
    this.focalLengthMm,
    this.whiteBalance,
  });

  final int? iso;
  final String? shutterSpeed;
  final double? aperture;
  final double? focalLengthMm;
  final String? whiteBalance;

  bool get isEmpty =>
      iso == null &&
      shutterSpeed == null &&
      aperture == null &&
      focalLengthMm == null &&
      (whiteBalance == null || whiteBalance!.isEmpty);

  bool get isNotEmpty => !isEmpty;

  Map<String, Object?> toJson() {
    return {
      'iso': iso,
      'shutterSpeed': shutterSpeed,
      'aperture': aperture,
      'focalLengthMm': focalLengthMm,
      'whiteBalance': whiteBalance,
    };
  }

  factory PhotoExif.fromJson(Map<String, Object?> json) {
    return PhotoExif(
      iso: _nullableIntValue(json['iso']),
      shutterSpeed: _nullableStringValue(json['shutterSpeed']),
      aperture: _nullableDoubleValue(json['aperture']),
      focalLengthMm: _nullableDoubleValue(json['focalLengthMm']),
      whiteBalance: _nullableStringValue(json['whiteBalance']),
    );
  }
}

class PhotoAppraisal {
  PhotoAppraisal({
    required this.initial,
    required this.overall,
    required this.refine,
    required this.question,
    required List<PhotoAppraisalMetric> metrics,
  }) : metrics = List.unmodifiable(metrics);

  final String initial;
  final String overall;
  final String refine;
  final String question;
  final List<PhotoAppraisalMetric> metrics;

  int get totalScore {
    return metrics.fold<int>(0, (value, metric) => value + metric.value);
  }

  Map<String, Object?> toJson() {
    return {
      'initial': initial,
      'overall': overall,
      'refine': refine,
      'question': question,
      'metrics': [for (final metric in metrics) metric.toJson()],
    };
  }

  factory PhotoAppraisal.fromJson(Map<String, Object?> json) {
    return PhotoAppraisal(
      initial: _stringValue(json['initial'], ''),
      overall: _stringValue(json['overall'], ''),
      refine: _stringValue(json['refine'], ''),
      question: _stringValue(json['question'], ''),
      metrics: [
        for (final metric in _jsonMapList(json['metrics']))
          PhotoAppraisalMetric.fromJson(metric),
      ],
    );
  }
}

class PhotoAppraisalMetric {
  const PhotoAppraisalMetric({
    required this.label,
    required this.value,
    required this.text,
  });

  final String label;
  final int value;
  final String text;

  Map<String, Object?> toJson() {
    return {'label': label, 'value': value, 'text': text};
  }

  factory PhotoAppraisalMetric.fromJson(Map<String, Object?> json) {
    return PhotoAppraisalMetric(
      label: _stringValue(json['label'], ''),
      value: _nullableIntValue(json['value'])?.clamp(0, 25).toInt() ?? 0,
      text: _stringValue(json['text'], ''),
    );
  }
}

class PhotoAsset {
  const PhotoAsset({
    required this.id,
    required this.sessionId,
    required this.platformAssetId,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.mediaKind,
    required this.availability,
    this.fileSize,
    this.mimeType,
    this.duration,
    this.isScreenshot = false,
    this.isRaw = false,
    this.isCherished = false,
    this.appraisalScore,
    this.appraisal,
    this.sourceUri,
    this.thumbnailPath,
    this.previewPath,
    this.exif,
    this.dimensionsEstimated = false,
    this.createdAtEstimated = false,
  });

  final String id;
  final String sessionId;
  final String platformAssetId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int width;
  final int height;
  final MediaKind mediaKind;
  final AssetAvailability availability;
  final int? fileSize;
  final String? mimeType;
  final Duration? duration;
  final bool isScreenshot;
  final bool isRaw;
  final bool isCherished;
  final int? appraisalScore;
  final PhotoAppraisal? appraisal;
  final String? sourceUri;
  final String? thumbnailPath;
  final String? previewPath;
  final PhotoExif? exif;
  final bool dimensionsEstimated;
  final bool createdAtEstimated;

  PhotoAsset copyWith({
    String? id,
    String? sessionId,
    String? platformAssetId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? width,
    int? height,
    MediaKind? mediaKind,
    AssetAvailability? availability,
    int? fileSize,
    String? mimeType,
    Duration? duration,
    bool? isScreenshot,
    bool? isRaw,
    bool? isCherished,
    int? appraisalScore,
    PhotoAppraisal? appraisal,
    String? sourceUri,
    String? thumbnailPath,
    String? previewPath,
    PhotoExif? exif,
    bool? dimensionsEstimated,
    bool? createdAtEstimated,
    bool clearPreviewPath = false,
  }) {
    return PhotoAsset(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      platformAssetId: platformAssetId ?? this.platformAssetId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      mediaKind: mediaKind ?? this.mediaKind,
      availability: availability ?? this.availability,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      duration: duration ?? this.duration,
      isScreenshot: isScreenshot ?? this.isScreenshot,
      isRaw: isRaw ?? this.isRaw,
      isCherished: isCherished ?? this.isCherished,
      appraisalScore: appraisalScore ?? this.appraisalScore,
      appraisal: appraisal ?? this.appraisal,
      sourceUri: sourceUri ?? this.sourceUri,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      previewPath: clearPreviewPath ? null : previewPath ?? this.previewPath,
      exif: exif ?? this.exif,
      dimensionsEstimated: dimensionsEstimated ?? this.dimensionsEstimated,
      createdAtEstimated: createdAtEstimated ?? this.createdAtEstimated,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'platformAssetId': platformAssetId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'width': width,
      'height': height,
      'mediaKind': mediaKind.name,
      'availability': availability.name,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'durationMilliseconds': duration?.inMilliseconds,
      'isScreenshot': isScreenshot,
      'isRaw': isRaw,
      'isCherished': isCherished,
      'appraisalScore': appraisalScore,
      'appraisal': appraisal?.toJson(),
      'sourceUri': sourceUri,
      'thumbnailPath': thumbnailPath,
      'previewPath': previewPath,
      'exif': exif?.toJson(),
      'dimensionsEstimated': dimensionsEstimated,
      'createdAtEstimated': createdAtEstimated,
    };
  }

  factory PhotoAsset.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return PhotoAsset(
      id: _stringValue(
        json['id'],
        'photo-${fallbackTime.microsecondsSinceEpoch}',
      ),
      sessionId: _stringValue(json['sessionId'], ''),
      platformAssetId: _stringValue(json['platformAssetId'], ''),
      createdAt: _dateValue(json['createdAt'], fallbackTime),
      updatedAt: _dateValue(json['updatedAt'], fallbackTime),
      width: _intValue(json['width'], 0),
      height: _intValue(json['height'], 0),
      mediaKind: _enumValue(
        MediaKind.values,
        json['mediaKind'],
        MediaKind.unknown,
      ),
      availability: _enumValue(
        AssetAvailability.values,
        json['availability'],
        AssetAvailability.available,
      ),
      fileSize: _nullableIntValue(json['fileSize']),
      mimeType: _nullableStringValue(json['mimeType']),
      duration: _durationValue(json['durationMilliseconds']),
      isScreenshot: _boolValue(json['isScreenshot'], false),
      isRaw: _boolValue(json['isRaw'], false),
      isCherished: _boolValue(json['isCherished'], false),
      appraisalScore: _scoreValue(json['appraisalScore']),
      appraisal: _appraisalValue(json['appraisal']),
      sourceUri: _nullableStringValue(json['sourceUri']),
      thumbnailPath: _nullableStringValue(json['thumbnailPath']),
      previewPath: _nullableStringValue(json['previewPath']),
      exif: _exifValue(json['exif']),
      dimensionsEstimated: _boolValue(json['dimensionsEstimated'], false),
      createdAtEstimated: _boolValue(json['createdAtEstimated'], true),
    );
  }
}

PhotoExif? _exifValue(Object? value) {
  if (value is Map<String, Object?>) {
    final exif = PhotoExif.fromJson(value);
    return exif.isEmpty ? null : exif;
  }
  if (value is Map) {
    final exif = PhotoExif.fromJson(value.cast<String, Object?>());
    return exif.isEmpty ? null : exif;
  }
  return null;
}

PhotoAppraisal? _appraisalValue(Object? value) {
  if (value is Map<String, Object?>) {
    return PhotoAppraisal.fromJson(value);
  }
  if (value is Map) {
    return PhotoAppraisal.fromJson(value.cast<String, Object?>());
  }
  return null;
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _jsonMapList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return [for (final item in value) _jsonMap(item)];
}

T _enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = value?.toString();
  for (final item in values) {
    if (item.name == name) {
      return item;
    }
  }
  return fallback;
}

String _stringValue(Object? value, String fallback) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return fallback;
}

String? _nullableStringValue(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int _intValue(Object? value, int fallback) {
  return _nullableIntValue(value) ?? fallback;
}

int? _nullableIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

int? _scoreValue(Object? value) {
  final score = _nullableIntValue(value);
  if (score == null) {
    return null;
  }
  return score.clamp(0, 100).toInt();
}

double? _nullableDoubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

bool _boolValue(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

Duration? _durationValue(Object? value) {
  final milliseconds = _nullableIntValue(value);
  if (milliseconds == null) {
    return null;
  }
  return Duration(milliseconds: milliseconds);
}
