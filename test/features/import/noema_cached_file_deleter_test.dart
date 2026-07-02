import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/import/noema_cached_file_deleter.dart';

void main() {
  test('deletes only local files under noema_media', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'noema-media-delete-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final cachedFile = File('${tempDir.path}/noema_media/imports/photo.jpg');
    final outsideFile = File('${tempDir.path}/outside.jpg');
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes([1, 2, 3]);
    await outsideFile.writeAsBytes([4, 5, 6]);

    final deleted = await deleteNoemaLocalCachedFiles([
      cachedFile.path,
      outsideFile.path,
      cachedFile.path,
    ]);

    expect(deleted, 1);
    expect(await cachedFile.exists(), isFalse);
    expect(await outsideFile.exists(), isTrue);
  });
}
