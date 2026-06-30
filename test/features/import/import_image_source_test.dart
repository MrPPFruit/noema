import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/import/import_image_source.dart';

void main() {
  test('uses native file images for local picker paths on Android and iOS', () {
    final widget =
        buildImportImageFromPath(
              path: '/tmp/noema/photo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
            as Image;

    expect(widget.image, isA<FileImage>());
    expect((widget.image as FileImage).file.path, '/tmp/noema/photo.jpg');
  });

  test('keeps network image handling for remote paths on io platforms', () {
    final widget =
        buildImportImageFromPath(
              path: 'https://example.com/photo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
            as Image;

    expect(widget.image, isA<NetworkImage>());
  });

  test('applies decode size hints for large local picker previews', () {
    final widget =
        buildImportImageFromPath(
              path: '/tmp/noema/photo.jpg',
              fit: BoxFit.cover,
              cacheWidth: 160,
              cacheHeight: 120,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
            as Image;

    expect(
      widget.image,
      isA<ResizeImage>()
          .having((provider) => provider.width, 'width', 160)
          .having((provider) => provider.height, 'height', 120),
    );
    expect(widget.filterQuality, FilterQuality.low);
  });
}
