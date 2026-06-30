import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/review_session.dart';
import 'package:noema/core/models/similar_group.dart';

final mockNow = DateTime(2026, 5, 25, 14, 32);

final mockSession = ReviewSession(
  id: 'session-001',
  name: 'Afternoon review',
  createdAt: mockNow,
  updatedAt: mockNow,
  totalCount: 18,
  importedCount: 18,
  analyzedCount: 18,
  currentStage: ReviewStage.reviewing,
  status: ReviewSessionStatus.ready,
);

final mockAssets = List.generate(6, (index) {
  return PhotoAsset(
    id: 'photo-${index + 1}',
    sessionId: mockSession.id,
    platformAssetId: 'platform-photo-${index + 1}',
    createdAt: mockNow.add(Duration(seconds: index * 6)),
    updatedAt: mockNow,
    width: 3024,
    height: 4032,
    mediaKind: MediaKind.photo,
    availability: AssetAvailability.available,
  );
});

final mockGroups = [
  SimilarGroup(
    id: 'group-001',
    sessionId: mockSession.id,
    photoIds: mockAssets.take(4).map((asset) => asset.id).toList(),
    groupReason: GroupReason.nearDuplicate,
    attentionReasons: const [],
    reviewStatus: ReviewStatus.pending,
    createdAt: mockNow,
    updatedAt: mockNow,
  ),
  SimilarGroup(
    id: 'group-002',
    sessionId: mockSession.id,
    photoIds: mockAssets.skip(4).map((asset) => asset.id).toList(),
    groupReason: GroupReason.needsAttention,
    attentionReasons: const [QualityFlag.possibleBlur],
    reviewStatus: ReviewStatus.pending,
    createdAt: mockNow,
    updatedAt: mockNow,
  ),
];
