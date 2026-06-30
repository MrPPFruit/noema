import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/models/photo_decision.dart';

void main() {
  test('decision labels match UI specification vocabulary', () {
    expect(Decision.keep.label, 'Keep');
    expect(Decision.maybe.label, 'Maybe');
    expect(Decision.reviewForRemoval.label, 'Review for removal');
  });

  test('photo decision stores user decision metadata', () {
    final decidedAt = DateTime(2026, 5, 25, 14, 32);
    final decision = PhotoDecision(
      photoId: 'photo-1',
      decision: Decision.keep,
      decidedAt: decidedAt,
      updatedAt: decidedAt,
      source: DecisionSource.user,
    );

    expect(decision.photoId, 'photo-1');
    expect(decision.decision, Decision.keep);
    expect(decision.source, DecisionSource.user);
  });
}
