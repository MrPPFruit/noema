import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/import/noema_media_picker.dart';

void main() {
  test('maps native media metadata into selected asset', () {
    final asset = selectedGalleryAssetFromMediaMap({
      'uri': 'content://media/photo/42',
      'id': 'photo-42',
      'name': 'IMG_0042.JPG',
      'mimeType': 'image/jpeg',
      'fileSize': 3456789,
      'width': 4032,
      'height': 3024,
      'takenAtMillis': 1767225600000,
      'modifiedAtMillis': 1767225660000,
      'iso': 100,
      'shutterSpeed': '1/500s',
      'aperture': 5.6,
      'focalLengthMm': 24,
      'whiteBalance': 'WB 5600K',
    });

    expect(asset.id, 'photo-42');
    expect(asset.sourceUri, 'content://media/photo/42');
    expect(asset.name, 'IMG_0042.JPG');
    expect(asset.mimeType, 'image/jpeg');
    expect(asset.fileSize, 3456789);
    expect(asset.width, 4032);
    expect(asset.height, 3024);
    expect(asset.createdAt, DateTime.fromMillisecondsSinceEpoch(1767225600000));
    expect(asset.updatedAt, DateTime.fromMillisecondsSinceEpoch(1767225660000));
    expect(asset.exif?.iso, 100);
    expect(asset.exif?.shutterSpeed, '1/500s');
    expect(asset.exif?.aperture, 5.6);
    expect(asset.exif?.focalLengthMm, 24);
    expect(asset.exif?.whiteBalance, 'WB 5600K');
    expect(asset.previewUnavailable, isFalse);
  });

  test('ignores invalid dimensions and timestamps', () {
    final asset = selectedGalleryAssetFromMediaMap({
      'uri': 'content://media/photo/43',
      'name': 'IMG_0043.JPG',
      'width': 0,
      'height': -1,
      'takenAtMillis': 0,
      'modifiedAtMillis': 'bad',
    });

    expect(asset.id, 'content://media/photo/43');
    expect(asset.width, isNull);
    expect(asset.height, isNull);
    expect(asset.createdAt, isNull);
    expect(asset.updatedAt, isNull);
  });

  test('prefers EXIF capture time over MediaStore capture time', () {
    final asset = selectedGalleryAssetFromMediaMap({
      'uri': 'content://media/photo/43-exif',
      'name': 'DSC0043.JPG',
      'takenAtMillis': 1767225600000,
      'exifTakenAtMillis': 1775377800000,
    });

    expect(asset.createdAt, DateTime.fromMillisecondsSinceEpoch(1775377800000));
  });

  testWidgets('uses method channel for picking and thumbnail creation', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'galleryAccessStatus') {
        return 'partial';
      }
      if (call.method == 'requestGalleryAccess') {
        return 'full';
      }
      if (call.method == 'refreshGalleryIndex') {
        return {
          'access': 'full',
          'count': 42,
          'path': '/files/noema_media/index/gallery_index_v1.json',
        };
      }
      if (call.method == 'warmGalleryThumbnails') {
        return 12;
      }
      if (call.method == 'pickImages') {
        return [
          {
            'uri': 'content://media/photo/44',
            'name': 'IMG_0044.JPG',
            'width': 3000,
            'height': 2000,
          },
        ];
      }
      if (call.method == 'createThumbnail') {
        return '/cache/thumb.jpg';
      }
      if (call.method == 'loadMetadata') {
        return {
          'uri': 'content://media/photo/44',
          'name': 'IMG_0044.JPG',
          'width': 3000,
          'height': 2000,
          'takenAtMillis': 1767225600000,
        };
      }
      if (call.method == 'createPreview') {
        return '/cache/preview.jpg';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    const picker = NoemaMediaPicker(channel: channel);
    final status = await picker.galleryAccessStatus();
    final access = await picker.requestGalleryAccess();
    final index = await picker.refreshGalleryIndex();
    final warmed = await picker.warmGalleryThumbnails();
    final assets = await picker.pickImages(limit: 50);
    final thumb = await picker.createThumbnail(uri: 'content://media/photo/44');
    final metadata = await picker.loadMetadata(uri: 'content://media/photo/44');
    final preview = await picker.createPreview(uri: 'content://media/photo/44');

    expect(status, NoemaGalleryAccess.partial);
    expect(access, NoemaGalleryAccess.full);
    expect(index.access, NoemaGalleryAccess.full);
    expect(index.count, 42);
    expect(index.path, '/files/noema_media/index/gallery_index_v1.json');
    expect(warmed, 12);
    expect(assets.single.sourceUri, 'content://media/photo/44');
    expect(thumb, '/cache/thumb.jpg');
    expect(metadata?.width, 3000);
    expect(
      metadata?.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1767225600000),
    );
    expect(preview, '/cache/preview.jpg');
    expect(calls.map((call) => call.method), [
      'galleryAccessStatus',
      'requestGalleryAccess',
      'refreshGalleryIndex',
      'warmGalleryThumbnails',
      'pickImages',
      'createThumbnail',
      'loadMetadata',
      'createPreview',
    ]);
  });

  testWidgets('shares concurrent cached preview requests', (tester) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final previewCompleter = Completer<Object?>();
    var previewCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      if (call.method == 'createPreview') {
        previewCalls += 1;
        return previewCompleter.future;
      }
      return Future<Object?>.value(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    addTearDown(() {
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
    });

    const picker = NoemaMediaPicker(channel: channel);
    final first = picker.createPreview(
      uri: 'content://media/photo/44',
      maxSize: 3072,
    );
    final second = picker.createPreview(
      uri: 'content://media/photo/44',
      maxSize: 3072,
    );
    await tester.pump();

    expect(previewCalls, 1);

    previewCompleter.complete('/cache/preview-3072.jpg');
    expect(await Future.wait([first, second]), [
      '/cache/preview-3072.jpg',
      '/cache/preview-3072.jpg',
    ]);
  });

  testWidgets(
    'does not keep completed preview requests as a long-lived cache',
    (tester) async {
      const channel = MethodChannel(noemaMediaPickerChannelName);
      var previewCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'createPreview') {
          previewCalls += 1;
          return '/cache/preview-$previewCalls.jpg';
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      const picker = NoemaMediaPicker(channel: channel);
      final first = await picker.createPreview(
        uri: 'content://media/photo/44',
        maxSize: 3072,
      );
      final second = await picker.createPreview(
        uri: 'content://media/photo/44',
        maxSize: 3072,
      );

      expect(first, '/cache/preview-1.jpg');
      expect(second, '/cache/preview-2.jpg');
      expect(previewCalls, 2);
    },
  );
}
