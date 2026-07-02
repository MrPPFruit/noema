import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noema/features/import/gallery_import_preparer.dart';

void main() {
  test('prepares picker file as a lightweight path reference', () async {
    final tempDir = await Directory.systemTemp.createTemp('noema-import-');
    addTearDown(() => tempDir.delete(recursive: true));
    final image = File('${tempDir.path}/photo.jpg');
    final bytes = List<int>.generate(8, (index) => index);
    await image.writeAsBytes(bytes);

    final asset = await const GalleryImportPreparer().prepareOne(
      XFile(image.path, name: 'photo.jpg'),
    );

    expect(asset.id, image.path);
    expect(asset.name, 'photo.jpg');
    expect(asset.thumbnailPath, image.path);
    expect(asset.previewBytes, isNull);
    expect(asset.analysisBytes, isNull);
    expect(asset.previewUnavailable, isFalse);
  });

  test('does not decode dimensions during lightweight preparation', () async {
    final tempDir = await Directory.systemTemp.createTemp('noema-import-');
    addTearDown(() => tempDir.delete(recursive: true));
    final image = File('${tempDir.path}/landscape.png');
    await image.writeAsBytes(List<int>.generate(16, (index) => index));

    final asset = await const GalleryImportPreparer().prepareOne(
      XFile(image.path, name: 'landscape.png'),
    );

    expect(asset.width, isNull);
    expect(asset.height, isNull);
    expect(asset.previewBytes, isNull);
    expect(asset.analysisBytes, isNull);
  });

  test(
    'keeps large picker file as path preview without truncated bytes',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('noema-import-');
      addTearDown(() => tempDir.delete(recursive: true));
      final image = File('${tempDir.path}/large.jpg');
      await image.writeAsBytes(List<int>.generate(16, (index) => index));

      final asset = await const GalleryImportPreparer().prepareOne(
        XFile(image.path, name: 'large.jpg'),
      );

      expect(asset.thumbnailPath, image.path);
      expect(asset.previewBytes, isNull);
      expect(asset.analysisBytes, isNull);
      expect(asset.previewUnavailable, isFalse);
    },
  );

  test('does not block on empty picker file checks', () async {
    final tempDir = await Directory.systemTemp.createTemp('noema-import-');
    addTearDown(() => tempDir.delete(recursive: true));
    final image = File('${tempDir.path}/empty.jpg');
    await image.writeAsBytes(const []);

    final asset = await const GalleryImportPreparer().prepareOne(
      XFile(image.path, name: 'empty.jpg'),
    );

    expect(asset.thumbnailPath, image.path);
    expect(asset.previewBytes, isNull);
    expect(asset.previewUnavailable, isFalse);
  });

  test(
    'does not touch missing picker path during lightweight preparation',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('noema-import-');
      addTearDown(() => tempDir.delete(recursive: true));
      final missingPath = '${tempDir.path}/missing.jpg';

      final asset = await const GalleryImportPreparer().prepareOne(
        XFile(missingPath, name: 'missing.jpg'),
      );

      expect(asset.id, missingPath);
      expect(asset.thumbnailPath, missingPath);
      expect(asset.previewBytes, isNull);
      expect(asset.previewUnavailable, isFalse);
    },
  );
}
