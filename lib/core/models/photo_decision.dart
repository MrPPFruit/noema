import 'package:noema/core/models/decision.dart';

enum DecisionSource { user, algorithmSuggestion }

class PhotoDecision {
  const PhotoDecision({
    required this.photoId,
    required this.decision,
    required this.decidedAt,
    required this.updatedAt,
    required this.source,
  });

  final String photoId;
  final Decision decision;
  final DateTime decidedAt;
  final DateTime updatedAt;
  final DecisionSource source;

  Map<String, Object?> toJson() {
    return {
      'photoId': photoId,
      'decision': decision.name,
      'decidedAt': decidedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'source': source.name,
    };
  }

  factory PhotoDecision.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return PhotoDecision(
      photoId: _stringValue(json['photoId'], ''),
      decision: _enumValue(Decision.values, json['decision'], Decision.maybe),
      decidedAt: _dateValue(json['decidedAt'], fallbackTime),
      updatedAt: _dateValue(json['updatedAt'], fallbackTime),
      source: _enumValue(
        DecisionSource.values,
        json['source'],
        DecisionSource.user,
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

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}
