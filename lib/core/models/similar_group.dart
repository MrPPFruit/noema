import 'dart:collection';

import 'package:noema/core/models/analysis_result.dart';

enum GroupReason { burst, nearDuplicate, timeCluster, needsAttention }

enum ReviewStatus { pending, inProgress, completed }

class SimilarGroup {
  SimilarGroup({
    required this.id,
    required this.sessionId,
    required List<String> photoIds,
    required this.groupReason,
    required List<QualityFlag> attentionReasons,
    required this.reviewStatus,
    required this.createdAt,
    required this.updatedAt,
    this.recommendedLeadPhotoId,
    this.currentIndex,
  }) : _photoIds = List.unmodifiable(photoIds),
       _attentionReasons = List.unmodifiable(attentionReasons);

  final String id;
  final String sessionId;
  final List<String> _photoIds;
  final GroupReason groupReason;
  final List<QualityFlag> _attentionReasons;
  final ReviewStatus reviewStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? recommendedLeadPhotoId;
  final int? currentIndex;

  UnmodifiableListView<String> get photoIds => UnmodifiableListView(_photoIds);

  UnmodifiableListView<QualityFlag> get attentionReasons =>
      UnmodifiableListView(_attentionReasons);

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'photoIds': _photoIds,
      'groupReason': groupReason.name,
      'attentionReasons': [for (final reason in _attentionReasons) reason.name],
      'reviewStatus': reviewStatus.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'recommendedLeadPhotoId': recommendedLeadPhotoId,
      'currentIndex': currentIndex,
    };
  }

  factory SimilarGroup.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return SimilarGroup(
      id: _stringValue(
        json['id'],
        'group-${fallbackTime.microsecondsSinceEpoch}',
      ),
      sessionId: _stringValue(json['sessionId'], ''),
      photoIds: _stringListValue(json['photoIds']),
      groupReason: _enumValue(
        GroupReason.values,
        json['groupReason'],
        GroupReason.timeCluster,
      ),
      attentionReasons: _qualityFlagsValue(json['attentionReasons']),
      reviewStatus: _enumValue(
        ReviewStatus.values,
        json['reviewStatus'],
        ReviewStatus.pending,
      ),
      createdAt: _dateValue(json['createdAt'], fallbackTime),
      updatedAt: _dateValue(json['updatedAt'], fallbackTime),
      recommendedLeadPhotoId: _nullableStringValue(
        json['recommendedLeadPhotoId'],
      ),
      currentIndex: _nullableIntValue(json['currentIndex']),
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

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

List<String> _stringListValue(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is String && item.isNotEmpty) item,
  ];
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
