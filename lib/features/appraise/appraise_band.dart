import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';

const appraiseAiFormedScoreFloor = 60;
const appraiseAiFineScoreFloor = 80;

enum AppraisePhotoBand { flaw, formed, fine }

enum AppraiseTechnicalGate { pass, softIssue, hardFail, unknown }

AppraisePhotoBand appraiseBandForPhoto(
  PhotoAsset photo,
  AnalysisResult? analysis, {
  int? totalScore,
}) {
  final score = totalScore ?? appraiseStoredScoreForPhoto(photo);
  if (score != null) {
    return appraiseBandForScore(score);
  }
  return appraiseBandForTechnicalGate(appraiseTechnicalGateFor(analysis));
}

AppraisePhotoBand appraiseBandForScore(int totalScore) {
  if (totalScore >= appraiseAiFineScoreFloor) {
    return AppraisePhotoBand.fine;
  }
  if (totalScore >= appraiseAiFormedScoreFloor) {
    return AppraisePhotoBand.formed;
  }
  return AppraisePhotoBand.flaw;
}

AppraisePhotoBand appraiseBandForTechnicalGate(AppraiseTechnicalGate gate) {
  return switch (gate) {
    AppraiseTechnicalGate.hardFail ||
    AppraiseTechnicalGate.softIssue => AppraisePhotoBand.flaw,
    AppraiseTechnicalGate.pass ||
    AppraiseTechnicalGate.unknown => AppraisePhotoBand.formed,
  };
}

AppraiseTechnicalGate appraiseTechnicalGateFor(AnalysisResult? analysis) {
  if (analysis == null) {
    return AppraiseTechnicalGate.unknown;
  }
  final flags = analysis.qualityFlags;
  if (flags.contains(QualityFlag.unavailable) ||
      flags.contains(QualityFlag.unsupportedType) ||
      analysis.blurScore < 0.28 ||
      analysis.brightnessScore < 0.18 ||
      analysis.brightnessScore > 0.92) {
    return AppraiseTechnicalGate.hardFail;
  }
  if (analysis.blurScore < 0.50 ||
      analysis.brightnessScore < 0.24 ||
      analysis.brightnessScore > 0.76 ||
      analysis.exposureFlag != ExposureFlag.normal) {
    return AppraiseTechnicalGate.softIssue;
  }
  return AppraiseTechnicalGate.pass;
}

int? appraiseStoredScoreForPhoto(PhotoAsset photo) {
  return photo.appraisal?.totalScore ?? photo.appraisalScore;
}
