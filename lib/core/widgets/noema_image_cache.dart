import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _noemaDeviceProfileChannel = MethodChannel('noema/device_profile');
const _bytesPerPixel = 4;
const _mb = 1 << 20;

Future<void> configureNoemaImageCache() async {
  final profile = await _loadNoemaImageCacheProfile();
  PaintingBinding.instance.imageCache
    ..maximumSize = 240
    ..maximumSizeBytes = noemaImageCacheBudgetBytes(
      memoryClassMb: profile.memoryClassMb,
      totalMemoryMb: profile.totalMemoryMb,
      screenWidthPixels: profile.screenWidthPixels,
      screenHeightPixels: profile.screenHeightPixels,
      isLowRamDevice: profile.isLowRamDevice,
    );
}

int noemaImageCacheBudgetBytes({
  int? memoryClassMb,
  int? totalMemoryMb,
  int? screenWidthPixels,
  int? screenHeightPixels,
  bool isLowRamDevice = false,
}) {
  final memoryClassBytes = _positiveMb(memoryClassMb, fallbackMb: 256);
  final screenBytes = _screenBytes(
    screenWidthPixels: screenWidthPixels,
    screenHeightPixels: screenHeightPixels,
  );
  final percentBudget = (memoryClassBytes * (isLowRamDevice ? 0.20 : 0.25))
      .round();
  final screenBudget =
      screenBytes * (isLowRamDevice ? 6 : 14) +
      (isLowRamDevice ? 24 * _mb : 48 * _mb);
  final preferred = math.max(percentBudget, screenBudget);
  final memoryClassCap = (memoryClassBytes * (isLowRamDevice ? 0.33 : 0.75))
      .round();
  final totalMemoryCap = totalMemoryMb == null || totalMemoryMb <= 0
      ? memoryClassCap
      : (_positiveMb(totalMemoryMb, fallbackMb: 0) *
                (isLowRamDevice ? 0.025 : 0.035))
            .round();
  final absoluteCap = isLowRamDevice ? 96 * _mb : 192 * _mb;
  final cap = [memoryClassCap, totalMemoryCap, absoluteCap].reduce(math.min);
  final floor = isLowRamDevice ? 48 * _mb : 96 * _mb;
  return _roundToMb(math.max(floor, math.min(preferred, cap)), stepMb: 16);
}

({int width, int height}) noemaImageCacheSize(
  BuildContext context, {
  required double width,
  required double height,
  double headroom = 1.16,
  int maxExtent = 4096,
}) {
  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
  return (
    width: noemaImageCacheExtent(
      width,
      pixelRatio: pixelRatio,
      headroom: headroom,
      maxExtent: maxExtent,
    ),
    height: noemaImageCacheExtent(
      height,
      pixelRatio: pixelRatio,
      headroom: headroom,
      maxExtent: maxExtent,
    ),
  );
}

int noemaImageCacheExtent(
  double logicalExtent, {
  required double pixelRatio,
  double headroom = 1.16,
  int maxExtent = 4096,
}) {
  if (!logicalExtent.isFinite || logicalExtent <= 0) {
    return 1;
  }
  final extent = (logicalExtent * pixelRatio * headroom).ceil();
  return math.max(1, math.min(maxExtent, extent));
}

Future<_NoemaImageCacheProfile> _loadNoemaImageCacheProfile() async {
  try {
    final result = await _noemaDeviceProfileChannel
        .invokeMapMethod<Object?, Object?>('imageCacheProfile');
    return _NoemaImageCacheProfile.fromMap(result);
  } on MissingPluginException {
    return const _NoemaImageCacheProfile();
  } on PlatformException {
    return const _NoemaImageCacheProfile();
  }
}

int _positiveMb(int? value, {required int fallbackMb}) {
  if (value == null || value <= 0) {
    return fallbackMb * _mb;
  }
  return value * _mb;
}

int _screenBytes({int? screenWidthPixels, int? screenHeightPixels}) {
  if (screenWidthPixels == null ||
      screenHeightPixels == null ||
      screenWidthPixels <= 0 ||
      screenHeightPixels <= 0) {
    return 10 * _mb;
  }
  return screenWidthPixels * screenHeightPixels * _bytesPerPixel;
}

int _roundToMb(int bytes, {required int stepMb}) {
  final step = stepMb * _mb;
  return ((bytes + step - 1) ~/ step) * step;
}

class _NoemaImageCacheProfile {
  const _NoemaImageCacheProfile({
    this.memoryClassMb,
    this.totalMemoryMb,
    this.screenWidthPixels,
    this.screenHeightPixels,
    this.isLowRamDevice = false,
  });

  factory _NoemaImageCacheProfile.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const _NoemaImageCacheProfile();
    }
    return _NoemaImageCacheProfile(
      memoryClassMb: _intValue(map['memoryClassMb']),
      totalMemoryMb: _intValue(map['totalMemoryMb']),
      screenWidthPixels: _intValue(map['screenWidthPixels']),
      screenHeightPixels: _intValue(map['screenHeightPixels']),
      isLowRamDevice: map['isLowRamDevice'] == true,
    );
  }

  final int? memoryClassMb;
  final int? totalMemoryMb;
  final int? screenWidthPixels;
  final int? screenHeightPixels;
  final bool isLowRamDevice;
}

int? _intValue(Object? value) {
  return switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}
