import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/features/appraise/appraise_band.dart';

void main() {
  group('appraise band', () {
    test('maps stored scores to flaw formed and fine bands', () {
      expect(appraiseBandForScore(59), AppraisePhotoBand.flaw);
      expect(appraiseBandForScore(60), AppraisePhotoBand.formed);
      expect(appraiseBandForScore(79), AppraisePhotoBand.formed);
      expect(appraiseBandForScore(80), AppraisePhotoBand.fine);
    });

    test('uses technical gate when no appraisal score exists', () {
      expect(
        appraiseBandForPhoto(_photo('p1'), _analysis('p1')),
        AppraisePhotoBand.formed,
      );
      expect(
        appraiseBandForPhoto(_photo('p2'), _analysis('p2', blurScore: 0.49)),
        AppraisePhotoBand.flaw,
      );
      expect(
        appraiseBandForPhoto(
          _photo('p3'),
          _analysis('p3', brightnessScore: 0.17),
        ),
        AppraisePhotoBand.flaw,
      );
      expect(
        appraiseBandForPhoto(_photo('p4'), null),
        AppraisePhotoBand.formed,
      );
    });

    test('stored score overrides local technical gate', () {
      expect(
        appraiseBandForPhoto(
          _photo('p5', appraisalScore: 82),
          _analysis('p5', blurScore: 0.2),
        ),
        AppraisePhotoBand.fine,
      );
    });
  });
}

PhotoAsset _photo(String id, {int? appraisalScore}) {
  return PhotoAsset(
    id: id,
    sessionId: 'session-1',
    platformAssetId: id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    width: 1200,
    height: 800,
    mediaKind: MediaKind.photo,
    availability: AssetAvailability.available,
    appraisalScore: appraisalScore,
  );
}

AnalysisResult _analysis(
  String photoId, {
  double blurScore = 0.9,
  double brightnessScore = 0.55,
  ExposureFlag exposureFlag = ExposureFlag.normal,
  List<QualityFlag> qualityFlags = const [],
}) {
  return AnalysisResult(
    photoId: photoId,
    blurScore: blurScore,
    brightnessScore: brightnessScore,
    exposureFlag: exposureFlag,
    similarityHash: 1,
    colorSignature: const [1, 2, 3],
    luminanceSignature: const [3, 2, 1],
    qualityFlags: qualityFlags,
    analyzedAt: DateTime(2026),
  );
}
