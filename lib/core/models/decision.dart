enum Decision {
  keep,
  maybe,
  reviewForRemoval;

  String get label => switch (this) {
    Decision.keep => 'Keep',
    Decision.maybe => 'Maybe',
    Decision.reviewForRemoval => 'Review for removal',
  };
}
