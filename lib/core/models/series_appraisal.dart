enum SeriesAppraisalBand { formed, fine, cherished }

class PhotoSeriesAppraisal {
  PhotoSeriesAppraisal({
    required this.id,
    required this.sessionId,
    required this.band,
    required List<String> photoIds,
    required this.photoSetHash,
    required this.captureStartAt,
    required this.captureEndAt,
    required this.createdAt,
    required this.updatedAt,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.result,
  }) : photoIds = List.unmodifiable(photoIds);

  final String id;
  final String sessionId;
  final SeriesAppraisalBand band;
  final List<String> photoIds;
  final String photoSetHash;
  final DateTime captureStartAt;
  final DateTime captureEndAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String provider;
  final String model;
  final String promptVersion;
  final PhotoSeriesAppraisalResult result;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'band': band.name,
      'photoIds': photoIds,
      'photoSetHash': photoSetHash,
      'captureStartAt': captureStartAt.toIso8601String(),
      'captureEndAt': captureEndAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'provider': provider,
      'model': model,
      'promptVersion': promptVersion,
      'result': result.toJson(),
    };
  }

  factory PhotoSeriesAppraisal.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return PhotoSeriesAppraisal(
      id: _stringValue(
        json['id'],
        'series-${fallbackTime.microsecondsSinceEpoch}',
      ),
      sessionId: _stringValue(json['sessionId'], ''),
      band: _enumValue(
        SeriesAppraisalBand.values,
        json['band'],
        SeriesAppraisalBand.formed,
      ),
      photoIds: _stringList(json['photoIds']),
      photoSetHash: _stringValue(json['photoSetHash'], ''),
      captureStartAt: _dateValue(json['captureStartAt'], fallbackTime),
      captureEndAt: _dateValue(json['captureEndAt'], fallbackTime),
      createdAt: _dateValue(json['createdAt'], fallbackTime),
      updatedAt: _dateValue(json['updatedAt'], fallbackTime),
      provider: _stringValue(json['provider'], ''),
      model: _stringValue(json['model'], ''),
      promptVersion: _stringValue(json['promptVersion'], ''),
      result: PhotoSeriesAppraisalResult.fromJson(_jsonMap(json['result'])),
    );
  }

  PhotoSeriesAppraisal copyWith({
    String? id,
    String? sessionId,
    SeriesAppraisalBand? band,
    List<String>? photoIds,
    String? photoSetHash,
    DateTime? captureStartAt,
    DateTime? captureEndAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? provider,
    String? model,
    String? promptVersion,
    PhotoSeriesAppraisalResult? result,
  }) {
    return PhotoSeriesAppraisal(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      band: band ?? this.band,
      photoIds: photoIds ?? this.photoIds,
      photoSetHash: photoSetHash ?? this.photoSetHash,
      captureStartAt: captureStartAt ?? this.captureStartAt,
      captureEndAt: captureEndAt ?? this.captureEndAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      promptVersion: promptVersion ?? this.promptVersion,
      result: result ?? this.result,
    );
  }
}

class PhotoSeriesAppraisalResult {
  PhotoSeriesAppraisalResult({
    required this.title,
    required this.overall,
    required this.themeLine,
    required List<PhotoSeriesRelationship> relationships,
    required this.sequence,
    required this.refine,
    required this.question,
    required this.scores,
  }) : relationships = List.unmodifiable(relationships);

  final String title;
  final String overall;
  final String themeLine;
  final List<PhotoSeriesRelationship> relationships;
  final PhotoSeriesSequence sequence;
  final String refine;
  final String question;
  final PhotoSeriesScoreSet scores;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'overall': overall,
      'themeLine': themeLine,
      'relationships': [
        for (final relationship in relationships) relationship.toJson(),
      ],
      'sequence': sequence.toJson(),
      'refine': refine,
      'question': question,
      'scores': scores.toJson(),
    };
  }

  factory PhotoSeriesAppraisalResult.fromJson(Map<String, Object?> json) {
    return PhotoSeriesAppraisalResult(
      title: _stringValue(json['title'], '未命名系列'),
      overall: _stringValue(json['overall'], ''),
      themeLine: _stringValue(json['themeLine'], ''),
      relationships: [
        for (final relationship in _jsonMapList(json['relationships']))
          PhotoSeriesRelationship.fromJson(relationship),
      ],
      sequence: PhotoSeriesSequence.fromJson(_jsonMap(json['sequence'])),
      refine: _stringValue(json['refine'], ''),
      question: _stringValue(json['question'], ''),
      scores: PhotoSeriesScoreSet.fromJson(_jsonMap(json['scores'])),
    );
  }
}

class PhotoSeriesRelationship {
  PhotoSeriesRelationship({
    required List<String> photoIds,
    required this.role,
    required this.text,
  }) : photoIds = List.unmodifiable(photoIds);

  final List<String> photoIds;
  final String role;
  final String text;

  Map<String, Object?> toJson() {
    return {'photoIds': photoIds, 'role': role, 'text': text};
  }

  factory PhotoSeriesRelationship.fromJson(Map<String, Object?> json) {
    return PhotoSeriesRelationship(
      photoIds: _stringList(json['photoIds']),
      role: _stringValue(json['role'], ''),
      text: _stringValue(json['text'], ''),
    );
  }
}

class PhotoSeriesSequence {
  PhotoSeriesSequence({
    required List<String> suggestedPhotoIds,
    required this.text,
  }) : suggestedPhotoIds = List.unmodifiable(suggestedPhotoIds);

  final List<String> suggestedPhotoIds;
  final String text;

  Map<String, Object?> toJson() {
    return {'suggestedPhotoIds': suggestedPhotoIds, 'text': text};
  }

  factory PhotoSeriesSequence.fromJson(Map<String, Object?> json) {
    return PhotoSeriesSequence(
      suggestedPhotoIds: _stringList(json['suggestedPhotoIds']),
      text: _stringValue(json['text'], ''),
    );
  }
}

class PhotoSeriesScoreSet {
  const PhotoSeriesScoreSet({
    required this.theme,
    required this.technique,
    required this.emotion,
    required this.association,
    required this.editing,
  });

  final int theme;
  final int technique;
  final int emotion;
  final int association;
  final int editing;

  int get total => theme + technique + emotion + association + editing;

  Map<String, Object?> toJson() {
    return {
      'theme': theme,
      'technique': technique,
      'emotion': emotion,
      'association': association,
      'editing': editing,
    };
  }

  factory PhotoSeriesScoreSet.fromJson(Map<String, Object?> json) {
    return PhotoSeriesScoreSet(
      theme: _score20(json['theme']),
      technique: _score20(json['technique']),
      emotion: _score20(json['emotion']),
      association: _score20(json['association']),
      editing: _score20(json['editing']),
    );
  }
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

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return [
    for (final item in value)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
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
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _score20(Object? value) {
  if (value is num) {
    return value.round().clamp(0, 20).toInt();
  }
  return int.tryParse('$value')?.clamp(0, 20).toInt() ?? 0;
}
