import 'dart:math' as math;

enum ObserveWallDensity { compact, balanced, spacious }

class ObservePhotoWallItem {
  const ObservePhotoWallItem({required this.id, required this.aspectRatio});

  final String id;
  final double aspectRatio;
}

class ObservePhotoWallRect {
  const ObservePhotoWallRect({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String id;
  final double left;
  final double top;
  final double width;
  final double height;
}

class ObservePhotoWallLayout {
  const ObservePhotoWallLayout({required this.rects, required this.height});

  final List<ObservePhotoWallRect> rects;
  final double height;
}

ObservePhotoWallLayout buildObservePhotoWallLayout({
  required List<ObservePhotoWallItem> items,
  required double width,
  required ObserveWallDensity density,
}) {
  if (items.isEmpty || width <= 0) {
    return const ObservePhotoWallLayout(rects: [], height: 0);
  }

  final metrics = _ObserveWallMetrics.forDensity(density, width: width);
  final gaps = math.max(0, metrics.columns - 1) * metrics.spacing;
  final columnWidth = (width - gaps) / metrics.columns;
  if (columnWidth <= 0) {
    return const ObservePhotoWallLayout(rects: [], height: 0);
  }

  final rects = <ObservePhotoWallRect>[];
  final columnHeights = List<double>.filled(metrics.columns, 0);

  for (final item in items) {
    final ratio = _safeAspectRatio(item.aspectRatio);
    var column = 0;
    for (var index = 1; index < columnHeights.length; index++) {
      if (columnHeights[index] < columnHeights[column]) {
        column = index;
      }
    }

    final top = columnHeights[column];
    final tileHeight = columnWidth / ratio;
    rects.add(
      ObservePhotoWallRect(
        id: item.id,
        left: column * (columnWidth + metrics.spacing),
        top: top,
        width: columnWidth,
        height: tileHeight,
      ),
    );
    columnHeights[column] = top + tileHeight + metrics.spacing;
  }

  final height = columnHeights.fold<double>(0, math.max) - metrics.spacing;
  return ObservePhotoWallLayout(rects: rects, height: math.max(0, height));
}

double _safeAspectRatio(double value) {
  if (value.isNaN || value.isInfinite || value <= 0) {
    return 1;
  }
  return value.clamp(0.58, 2.05);
}

class _ObserveWallMetrics {
  const _ObserveWallMetrics({required this.columns, required this.spacing});

  final int columns;
  final double spacing;

  factory _ObserveWallMetrics.forDensity(
    ObserveWallDensity density, {
    required double width,
  }) {
    final base = switch (density) {
      ObserveWallDensity.compact => const _ObserveWallMetrics(
        columns: 4,
        spacing: 6,
      ),
      ObserveWallDensity.balanced => const _ObserveWallMetrics(
        columns: 3,
        spacing: 7,
      ),
      ObserveWallDensity.spacious => const _ObserveWallMetrics(
        columns: 2,
        spacing: 8,
      ),
    };
    if (width < 600) {
      return base;
    }
    final targetWidth = switch (density) {
      ObserveWallDensity.compact => 112.0,
      ObserveWallDensity.balanced => 132.0,
      ObserveWallDensity.spacious => 168.0,
    };
    final columns = math.max(base.columns, math.min(8, width ~/ targetWidth));
    return _ObserveWallMetrics(columns: columns, spacing: base.spacing);
  }
}
