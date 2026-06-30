import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/analysis/local_image_analyzer.dart';
import 'package:noema/core/models/analysis_result.dart';

void main() {
  test('flags dark images with low brightness', () {
    final bytes = _solidPng(8, 8, img.ColorRgb8(8, 8, 8));

    final result = const LocalImageAnalyzer().analyze(
      photoId: 'photo-1',
      bytes: bytes,
      analyzedAt: DateTime(2026, 5, 25),
    );

    expect(result.exposureFlag, ExposureFlag.dark);
    expect(result.qualityFlags, contains(QualityFlag.dark));
  });

  test('flags overexposed images with high brightness', () {
    final bytes = _solidPng(8, 8, img.ColorRgb8(250, 250, 250));

    final result = const LocalImageAnalyzer().analyze(
      photoId: 'photo-1',
      bytes: bytes,
      analyzedAt: DateTime(2026, 5, 25),
    );

    expect(result.exposureFlag, ExposureFlag.overexposed);
    expect(result.qualityFlags, contains(QualityFlag.overexposed));
  });

  test('flags undecodable image bytes as unsupported type', () {
    final result = const LocalImageAnalyzer().analyze(
      photoId: 'photo-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      analyzedAt: DateTime(2026, 5, 25),
    );

    expect(result.qualityFlags, contains(QualityFlag.unsupportedType));
  });

  test('captures multiple visual signatures for structured images', () {
    final bytes = _checkerPng(
      low: img.ColorRgb8(10, 120, 40),
      high: img.ColorRgb8(220, 210, 16),
    );

    final result = const LocalImageAnalyzer().analyze(
      photoId: 'photo-1',
      bytes: bytes,
      analyzedAt: DateTime(2026, 5, 25),
    );

    expect(result.similarityHash, isNonZero);
    expect(result.averageHashHex, isNotNull);
    expect(result.differenceHashHex, isNotNull);
    expect(result.perceptualHashHex, isNotNull);
    expect(result.waveletHashHex, isNotNull);
    expect(result.colorSignature, hasLength(144));
    expect(result.luminanceSignature, hasLength(256));
    expect(
      AnalysisResult.fromJson(result.toJson()).waveletHashHex,
      result.waveletHashHex,
    );
  });
}

Uint8List _solidPng(int width, int height, img.Color color) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _checkerPng({required img.Color low, required img.Color high}) {
  final image = img.Image(width: 16, height: 16);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      image.setPixel(x, y, (x + y).isEven ? low : high);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
