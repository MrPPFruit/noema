import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  test('stores selected image identity without original file reads', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final asset = SelectedGalleryAsset(
      id: 'asset-path-1',
      name: 'IMG_0001.JPG',
      thumbnailPath: 'cache/IMG_0001.JPG',
      previewBytes: bytes,
    );

    expect(asset.id, 'asset-path-1');
    expect(asset.name, 'IMG_0001.JPG');
    expect(asset.thumbnailPath, 'cache/IMG_0001.JPG');
    expect(asset.previewBytes, bytes);
  });
}
