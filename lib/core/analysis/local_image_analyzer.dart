import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:noema/core/models/analysis_result.dart';

class LocalImageAnalyzer {
  const LocalImageAnalyzer();

  AnalysisResult analyze({
    required String photoId,
    required Uint8List bytes,
    required DateTime analyzedAt,
  }) {
    final decoded = _decodeImage(bytes);
    if (decoded == null) {
      return AnalysisResult(
        photoId: photoId,
        blurScore: 0,
        brightnessScore: 0.5,
        exposureFlag: ExposureFlag.normal,
        similarityHash: 0,
        colorSignature: const [],
        luminanceSignature: const [],
        qualityFlags: const [QualityFlag.unsupportedType],
        analyzedAt: analyzedAt,
      );
    }

    final resized = img.copyResize(decoded, width: 32, height: 32);
    final luminance = _luminanceGrid(resized);
    final brightness = _average(luminance);
    final blurScore = _edgeScore(luminance, width: 32, height: 32);
    final averageHashHex = _averageHashHex(decoded);
    final differenceHashHex = _differenceHashHex(decoded);
    final perceptualHashHex = _perceptualHashHex(decoded);
    final waveletHashHex = _waveletHashHex(decoded);
    final exposureFlag = _exposureFlag(brightness);
    final qualityFlags = <QualityFlag>[
      if (blurScore < 0.28) QualityFlag.possibleBlur,
      if (exposureFlag == ExposureFlag.dark) QualityFlag.dark,
      if (exposureFlag == ExposureFlag.overexposed) QualityFlag.overexposed,
      if (exposureFlag == ExposureFlag.highlightRisk) QualityFlag.highlightRisk,
    ];

    return AnalysisResult(
      photoId: photoId,
      blurScore: blurScore,
      brightnessScore: brightness,
      exposureFlag: exposureFlag,
      similarityHash: _foldHashHex(averageHashHex),
      averageHashHex: averageHashHex,
      differenceHashHex: differenceHashHex,
      perceptualHashHex: perceptualHashHex,
      waveletHashHex: waveletHashHex,
      colorSignature: _colorSignature(decoded),
      luminanceSignature: _luminanceSignature(decoded),
      qualityFlags: qualityFlags,
      analyzedAt: analyzedAt,
    );
  }

  img.Image? _decodeImage(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  List<double> _luminanceGrid(img.Image image) {
    final values = <double>[];
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final pixel = image.getPixel(x, y);
        final luminance =
            (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b) / 255;
        values.add(luminance.clamp(0, 1));
      }
    }
    return values;
  }

  double _average(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _edgeScore(
    List<double> values, {
    required int width,
    required int height,
  }) {
    if (values.length < 2 || width < 2 || height < 2) {
      return 0;
    }

    var totalDelta = 0.0;
    var count = 0;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final index = y * width + x;
        if (x + 1 < width) {
          totalDelta += (values[index] - values[index + 1]).abs();
          count += 1;
        }
        if (y + 1 < height) {
          totalDelta += (values[index] - values[index + width]).abs();
          count += 1;
        }
      }
    }
    return count == 0 ? 0 : min(1, totalDelta / count * 8);
  }

  String _averageHashHex(img.Image source) {
    final resized = img.copyResize(source, width: 8, height: 8);
    final values = _luminanceGrid(resized);
    final average = _average(values);
    return _hashBitsToHex([for (final value in values) value >= average]);
  }

  String _differenceHashHex(img.Image source) {
    final resized = img.copyResize(source, width: 9, height: 8);
    final values = _luminanceGrid(resized);
    final bits = <bool>[];
    for (var y = 0; y < 8; y += 1) {
      for (var x = 0; x < 8; x += 1) {
        final left = values[y * 9 + x];
        final right = values[y * 9 + x + 1];
        bits.add(right >= left);
      }
    }
    return _hashBitsToHex(bits);
  }

  String _perceptualHashHex(img.Image source) {
    final resized = img.copyResize(source, width: 32, height: 32);
    final luminance = _luminanceGrid(resized);
    final coefficients = <double>[];
    for (var v = 0; v < 8; v += 1) {
      for (var u = 0; u < 8; u += 1) {
        var sum = 0.0;
        for (var y = 0; y < 32; y += 1) {
          for (var x = 0; x < 32; x += 1) {
            final pixel = luminance[y * 32 + x];
            sum +=
                pixel *
                cos(((2 * x + 1) * u * pi) / 64) *
                cos(((2 * y + 1) * v * pi) / 64);
          }
        }
        coefficients.add(sum);
      }
    }

    final average = _average(coefficients.skip(1).toList(growable: false));
    return _hashBitsToHex([
      for (final coefficient in coefficients) coefficient >= average,
    ]);
  }

  String _waveletHashHex(img.Image source) {
    const size = 32;
    const hashSize = 8;
    final resized = img.copyResize(source, width: size, height: size);
    var values = [for (final value in _luminanceGrid(resized)) value];

    var currentSize = size;
    while (currentSize > hashSize) {
      final next = List<double>.filled(size * size, 0);
      final half = currentSize ~/ 2;
      for (var y = 0; y < currentSize; y += 1) {
        for (var x = 0; x < half; x += 1) {
          final left = values[y * size + x * 2];
          final right = values[y * size + x * 2 + 1];
          next[y * size + x] = (left + right) / 2;
          next[y * size + half + x] = (left - right) / 2;
        }
      }

      final transformed = List<double>.from(next);
      for (var x = 0; x < currentSize; x += 1) {
        for (var y = 0; y < half; y += 1) {
          final top = next[(y * 2) * size + x];
          final bottom = next[(y * 2 + 1) * size + x];
          transformed[y * size + x] = (top + bottom) / 2;
          transformed[(half + y) * size + x] = (top - bottom) / 2;
        }
      }

      values = transformed;
      currentSize = half;
    }

    final coefficients = <double>[];
    for (var y = 0; y < hashSize; y += 1) {
      for (var x = 0; x < hashSize; x += 1) {
        coefficients.add(values[y * size + x]);
      }
    }
    final average = _average(coefficients.skip(1).toList(growable: false));
    return _hashBitsToHex([
      for (final coefficient in coefficients) coefficient >= average,
    ]);
  }

  int _foldHashHex(String hashHex) {
    final hash = BigInt.tryParse(hashHex, radix: 16);
    if (hash == null) {
      return 0;
    }
    final lowMask = (BigInt.one << 26) - BigInt.one;
    final midMask = (BigInt.one << 26) - BigInt.one;
    final low = (hash & lowMask).toInt();
    final mid = ((hash >> 26) & midMask).toInt();
    final high = (hash >> 52).toInt();
    return low ^ mid ^ high;
  }

  List<int> _colorSignature(img.Image source) {
    const blocks = 3;
    const bins = 16;
    final resized = img.copyResize(source, width: 96, height: 96);
    final signature = <int>[];
    final blockWidth = resized.width ~/ blocks;
    final blockHeight = resized.height ~/ blocks;

    for (var blockY = 0; blockY < blocks; blockY += 1) {
      for (var blockX = 0; blockX < blocks; blockX += 1) {
        final histogram = List<double>.filled(bins, 0);
        final startX = blockX * blockWidth;
        final startY = blockY * blockHeight;
        final endX = blockX == blocks - 1 ? resized.width : startX + blockWidth;
        final endY = blockY == blocks - 1
            ? resized.height
            : startY + blockHeight;
        for (var y = startY; y < endY; y += 1) {
          for (var x = startX; x < endX; x += 1) {
            final pixel = resized.getPixel(x, y);
            final bin = _hsvHueBin(
              pixel.r.toDouble() / 255,
              pixel.g.toDouble() / 255,
              pixel.b.toDouble() / 255,
              bins,
            );
            histogram[bin.index] += bin.weight;
          }
        }
        final total = histogram.fold<double>(0, (sum, value) => sum + value);
        for (final value in histogram) {
          signature.add(total <= 0 ? 0 : (value / total * 255).round());
        }
      }
    }
    return signature;
  }

  List<int> _luminanceSignature(img.Image source) {
    final resized = img.copyResize(source, width: 16, height: 16);
    final values = _luminanceGrid(resized);
    return [for (final value in values) (value * 255).round()];
  }

  ({int index, double weight}) _hsvHueBin(
    double red,
    double green,
    double blue,
    int bins,
  ) {
    final maxChannel = max(red, max(green, blue));
    final minChannel = min(red, min(green, blue));
    final delta = maxChannel - minChannel;
    final saturation = maxChannel == 0 ? 0.0 : delta / maxChannel;
    if (saturation < 0.12 || delta == 0) {
      return (index: 0, weight: 0.35 + maxChannel * 0.65);
    }

    late final double hue;
    if (maxChannel == red) {
      hue = ((green - blue) / delta).remainder(6);
    } else if (maxChannel == green) {
      hue = (blue - red) / delta + 2;
    } else {
      hue = (red - green) / delta + 4;
    }
    final normalizedHue = (hue * 60 + 360) % 360;
    final hueBins = bins - 1;
    final hueIndex = (normalizedHue / 360 * hueBins).floor();
    return (
      index: 1 + hueIndex.clamp(0, hueBins - 1).toInt(),
      weight: (0.25 + saturation * 0.5 + maxChannel * 0.25).clamp(0, 1),
    );
  }

  String _hashBitsToHex(List<bool> bits) {
    var hash = BigInt.zero;
    for (var index = 0; index < bits.length; index += 1) {
      if (bits[index]) {
        hash |= BigInt.one << index;
      }
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  ExposureFlag _exposureFlag(double brightness) {
    if (brightness < 0.24) {
      return ExposureFlag.dark;
    }
    if (brightness > 0.86) {
      return ExposureFlag.overexposed;
    }
    if (brightness > 0.76) {
      return ExposureFlag.highlightRisk;
    }
    return ExposureFlag.normal;
  }
}
