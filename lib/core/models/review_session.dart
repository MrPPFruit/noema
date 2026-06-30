enum ReviewStage {
  selecting,
  importing,
  thumbnailing,
  analyzing,
  reviewing,
  completed,
}

enum ReviewSessionStatus {
  draft,
  importing,
  analyzing,
  ready,
  reviewing,
  completed,
  interrupted,
  canceled,
}

class ReviewSession {
  const ReviewSession({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.totalCount,
    required this.importedCount,
    required this.analyzedCount,
    required this.currentStage,
    required this.status,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalCount;
  final int importedCount;
  final int analyzedCount;
  final ReviewStage currentStage;
  final ReviewSessionStatus status;

  ReviewSession copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalCount,
    int? importedCount,
    int? analyzedCount,
    ReviewStage? currentStage,
    ReviewSessionStatus? status,
  }) {
    return ReviewSession(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalCount: totalCount ?? this.totalCount,
      importedCount: importedCount ?? this.importedCount,
      analyzedCount: analyzedCount ?? this.analyzedCount,
      currentStage: currentStage ?? this.currentStage,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'totalCount': totalCount,
      'importedCount': importedCount,
      'analyzedCount': analyzedCount,
      'currentStage': currentStage.name,
      'status': status.name,
    };
  }

  factory ReviewSession.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return ReviewSession(
      id: _stringValue(
        json['id'],
        'session-${fallbackTime.microsecondsSinceEpoch}',
      ),
      name: _stringValue(json['name'], 'Selected photos'),
      createdAt: _dateValue(json['createdAt'], fallbackTime),
      updatedAt: _dateValue(json['updatedAt'], fallbackTime),
      totalCount: _intValue(json['totalCount'], 0),
      importedCount: _intValue(json['importedCount'], 0),
      analyzedCount: _intValue(json['analyzedCount'], 0),
      currentStage: _enumValue(
        ReviewStage.values,
        json['currentStage'],
        ReviewStage.reviewing,
      ),
      status: _enumValue(
        ReviewSessionStatus.values,
        json['status'],
        ReviewSessionStatus.ready,
      ),
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

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}
