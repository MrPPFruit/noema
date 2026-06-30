import 'dart:collection';

// Keeps each analyzed asset's quality summary and immutable review signals.

enum ExposureFlag { normal, dark, overexposed, highlightRisk }

enum QualityFlag {
  possibleBlur,
  dark,
  overexposed,
  highlightRisk,
  screenshot,
  video,
  livePhoto,
  raw,
  unavailable,
  unsupportedType,
}

class AnalysisResult {
  AnalysisResult({
    required this.photoId,
    required this.blurScore,
    required this.brightnessScore,
    required this.exposureFlag,
    required this.similarityHash,
    this.averageHashHex,
    this.differenceHashHex,
    this.perceptualHashHex,
    this.waveletHashHex,
    required List<int> colorSignature,
    required List<int> luminanceSignature,
    required List<QualityFlag> qualityFlags,
    required this.analyzedAt,
  }) : _colorSignature = List.unmodifiable(colorSignature),
       _luminanceSignature = List.unmodifiable(luminanceSignature),
       _qualityFlags = List.unmodifiable(qualityFlags);

  final String photoId;
  final double blurScore;
  final double brightnessScore;
  final ExposureFlag exposureFlag;

  // Legacy compact hash retained for quick checks and backwards-compatible JSON.
  final int similarityHash;
  final String? averageHashHex;
  final String? differenceHashHex;
  final String? perceptualHashHex;
  final String? waveletHashHex;
  final List<int> _colorSignature;
  final List<int> _luminanceSignature;
  final List<QualityFlag> _qualityFlags;
  final DateTime analyzedAt;

  UnmodifiableListView<int> get colorSignature =>
      UnmodifiableListView(_colorSignature);

  UnmodifiableListView<int> get luminanceSignature =>
      UnmodifiableListView(_luminanceSignature);

  UnmodifiableListView<QualityFlag> get qualityFlags =>
      UnmodifiableListView(_qualityFlags);

  Map<String, Object?> toJson() {
    return {
      'photoId': photoId,
      'blurScore': blurScore,
      'brightnessScore': brightnessScore,
      'exposureFlag': exposureFlag.name,
      'similarityHash': similarityHash,
      'averageHashHex': averageHashHex,
      'differenceHashHex': differenceHashHex,
      'perceptualHashHex': perceptualHashHex,
      'waveletHashHex': waveletHashHex,
      'colorSignature': _colorSignature,
      'luminanceSignature': _luminanceSignature,
      'qualityFlags': [for (final flag in _qualityFlags) flag.name],
      'analyzedAt': analyzedAt.toIso8601String(),
    };
  }

  factory AnalysisResult.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return AnalysisResult(
      photoId: _stringValue(json['photoId'], ''),
      blurScore: _doubleValue(json['blurScore'], 0),
      brightnessScore: _doubleValue(json['brightnessScore'], 0),
      exposureFlag: _enumValue(
        ExposureFlag.values,
        json['exposureFlag'],
        ExposureFlag.normal,
      ),
      similarityHash: _intValue(json['similarityHash'], 0),
      averageHashHex: _nullableStringValue(json['averageHashHex']),
      differenceHashHex: _nullableStringValue(json['differenceHashHex']),
      perceptualHashHex: _nullableStringValue(json['perceptualHashHex']),
      waveletHashHex: _nullableStringValue(json['waveletHashHex']),
      colorSignature: _intListValue(json['colorSignature']),
      luminanceSignature: _intListValue(json['luminanceSignature']),
      qualityFlags: _qualityFlagsValue(json['qualityFlags']),
      analyzedAt: _dateValue(json['analyzedAt'], fallbackTime),
    );
  }
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
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

List<int> _intListValue(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is int)
        item
      else if (item is num)
        item.round()
      else if (item is String)
        int.tryParse(item) ?? 0,
  ];
}

double _doubleValue(Object? value, double fallback) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

List<QualityFlag> _qualityFlagsValue(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final flag in value)
      _enumValue(QualityFlag.values, flag, QualityFlag.unsupportedType),
  ];
}
