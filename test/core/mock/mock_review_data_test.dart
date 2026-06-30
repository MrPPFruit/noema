import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/mock/mock_review_data.dart';

void main() {
  test('mock review data is internally consistent', () {
    final assetIds = mockAssets.map((asset) => asset.id).toSet();

    expect(mockAssets, isNotEmpty);
    expect(mockGroups, isNotEmpty);
    expect(mockSession.totalCount, greaterThanOrEqualTo(mockAssets.length));

    for (final group in mockGroups) {
      expect(group.sessionId, mockSession.id);
      expect(group.photoIds, isNotEmpty);
      expect(group.photoIds.every(assetIds.contains), isTrue);
    }
  });
}
