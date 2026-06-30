import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/observe/observe_photo_wall_layout.dart';

void main() {
  test('photo wall keeps each item aspect ratio', () {
    final layout = buildObservePhotoWallLayout(
      width: 342,
      density: ObserveWallDensity.balanced,
      items: const [
        ObservePhotoWallItem(id: 'wide', aspectRatio: 1.8),
        ObservePhotoWallItem(id: 'tall', aspectRatio: 0.72),
        ObservePhotoWallItem(id: 'square', aspectRatio: 1),
      ],
    );

    expect(layout.rects, hasLength(3));
    final wide = layout.rects.singleWhere((rect) => rect.id == 'wide');
    final tall = layout.rects.singleWhere((rect) => rect.id == 'tall');

    expect(wide.width / wide.height, closeTo(1.8, 0.01));
    expect(tall.width / tall.height, closeTo(0.72, 0.01));
  });

  test('larger density gives a larger photo wall rhythm', () {
    const items = [
      ObservePhotoWallItem(id: '1', aspectRatio: 1.4),
      ObservePhotoWallItem(id: '2', aspectRatio: 0.75),
      ObservePhotoWallItem(id: '3', aspectRatio: 1),
      ObservePhotoWallItem(id: '4', aspectRatio: 1.7),
      ObservePhotoWallItem(id: '5', aspectRatio: 0.8),
      ObservePhotoWallItem(id: '6', aspectRatio: 1.2),
    ];

    final compact = buildObservePhotoWallLayout(
      width: 342,
      density: ObserveWallDensity.compact,
      items: items,
    );
    final spacious = buildObservePhotoWallLayout(
      width: 342,
      density: ObserveWallDensity.spacious,
      items: items,
    );

    expect(spacious.height, greaterThan(compact.height));
    expect(
      spacious.rects.first.height,
      greaterThan(compact.rects.first.height),
    );
  });

  test('invalid ratios are clamped into safe visible tiles', () {
    final layout = buildObservePhotoWallLayout(
      width: 240,
      density: ObserveWallDensity.compact,
      items: const [
        ObservePhotoWallItem(id: 'bad', aspectRatio: 0),
        ObservePhotoWallItem(id: 'huge', aspectRatio: 20),
      ],
    );

    expect(layout.rects, hasLength(2));
    for (final rect in layout.rects) {
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.left + rect.width, lessThanOrEqualTo(240.1));
    }
  });

  test('dense rows never overflow the right wall edge', () {
    const items = [
      ObservePhotoWallItem(id: '1', aspectRatio: 0.75),
      ObservePhotoWallItem(id: '2', aspectRatio: 1.33),
      ObservePhotoWallItem(id: '3', aspectRatio: 1.77),
      ObservePhotoWallItem(id: '4', aspectRatio: 1.33),
      ObservePhotoWallItem(id: '5', aspectRatio: 0.75),
      ObservePhotoWallItem(id: '6', aspectRatio: 1.6),
      ObservePhotoWallItem(id: '7', aspectRatio: 1.4),
      ObservePhotoWallItem(id: '8', aspectRatio: 1.2),
    ];

    for (final density in ObserveWallDensity.values) {
      final layout = buildObservePhotoWallLayout(
        width: 342,
        density: density,
        items: items,
      );

      for (final rect in layout.rects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(
          rect.left + rect.width,
          lessThanOrEqualTo(342.1),
          reason: 'density=$density id=${rect.id}',
        );
      }
    }
  });
}
