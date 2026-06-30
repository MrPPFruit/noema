class GroupingEvaluationReport {
  const GroupingEvaluationReport({
    required this.truePositivePairs,
    required this.falsePositivePairs,
    required this.falseNegativePairs,
    required this.trueNegativePairs,
  });

  final int truePositivePairs;
  final int falsePositivePairs;
  final int falseNegativePairs;
  final int trueNegativePairs;

  double get precision {
    final denominator = truePositivePairs + falsePositivePairs;
    if (denominator == 0) {
      return 0;
    }
    return truePositivePairs / denominator;
  }

  double get recall {
    final denominator = truePositivePairs + falseNegativePairs;
    if (denominator == 0) {
      return 0;
    }
    return truePositivePairs / denominator;
  }

  double get f1Score {
    final p = precision;
    final r = recall;
    if (p == 0 || r == 0) {
      return 0;
    }
    return 2 * p * r / (p + r);
  }
}

GroupingEvaluationReport evaluateGrouping({
  required List<String> itemIds,
  required List<List<String>> expectedGroups,
  required List<List<String>> actualGroups,
}) {
  final expectedPairs = _pairKeys(expectedGroups);
  final actualPairs = _pairKeys(actualGroups);
  final universePairs = _pairKeys([itemIds]);

  var truePositivePairs = 0;
  var falsePositivePairs = 0;
  var falseNegativePairs = 0;
  var trueNegativePairs = 0;

  for (final pair in universePairs) {
    final expected = expectedPairs.contains(pair);
    final actual = actualPairs.contains(pair);
    if (expected && actual) {
      truePositivePairs += 1;
    } else if (!expected && actual) {
      falsePositivePairs += 1;
    } else if (expected && !actual) {
      falseNegativePairs += 1;
    } else {
      trueNegativePairs += 1;
    }
  }

  return GroupingEvaluationReport(
    truePositivePairs: truePositivePairs,
    falsePositivePairs: falsePositivePairs,
    falseNegativePairs: falseNegativePairs,
    trueNegativePairs: trueNegativePairs,
  );
}

Set<String> _pairKeys(List<List<String>> groups) {
  final pairs = <String>{};
  for (final group in groups) {
    if (group.length < 2) {
      continue;
    }
    for (var i = 0; i < group.length - 1; i += 1) {
      for (var j = i + 1; j < group.length; j += 1) {
        pairs.add(_pairKey(group[i], group[j]));
      }
    }
  }
  return pairs;
}

String _pairKey(String a, String b) {
  if (a.compareTo(b) <= 0) {
    return '$a|$b';
  }
  return '$b|$a';
}
