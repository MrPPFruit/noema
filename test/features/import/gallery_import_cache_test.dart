import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noema/features/import/gallery_import_cache.dart';

void main() {
  test('persists picker file under Noema import cache', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('noema/local_storage');
    final tempDir = await Directory.systemTemp.createTemp('noema-import-');
    final storageDir = await Directory.systemTemp.createTemp('noema-storage-');
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tempDir.delete(recursive: true);
      await storageDir.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStorageDirectory') {
            return storageDir.path;
          }
          return null;
        });

    final source = File('${tempDir.path}/IMG 001.JPG');
    await source.writeAsBytes([1, 2, 3, 4]);

    final persisted = await persistGalleryImportFile(
      XFile(source.path, name: 'IMG 001.JPG'),
    );

    expect(persisted, isNotNull);
    expect(persisted, startsWith('${storageDir.path}/noema_media/imports/'));
    expect(File(persisted!).readAsBytesSync(), [1, 2, 3, 4]);
  });
}
