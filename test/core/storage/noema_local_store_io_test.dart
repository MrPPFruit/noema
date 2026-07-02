import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/storage/noema_local_store_io.dart';

void main() {
  test('read migrates stale iOS app container paths', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('noema/local_storage');
    final storageDir = await Directory.systemTemp.createTemp('noema-storage-');
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await storageDir.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStorageDirectory') {
            return storageDir.path;
          }
          return null;
        });

    final storeFile = File(
      '${storageDir.path}${Platform.pathSeparator}noema_workspace_store_v1.json',
    );
    await storeFile.writeAsString(
      '{"thumbnailPath":"/var/mobile/Containers/Data/Application/OLD-ID/Library/Application Support/Noema/noema_media/imports/photo.jpg"}',
    );

    final source = await NoemaLocalStorePlatform().read();

    final expected = '${storageDir.path}/noema_media/imports/photo.jpg'
        .replaceAll(r'\', '/');
    expect(source, contains(expected));
    expect(await storeFile.readAsString(), contains(expected));
  });
}
