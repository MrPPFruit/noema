import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/widgets/review_asset_thumbnail.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/features/import/noema_media_picker.dart';

void main() {
  testWidgets('ReviewAssetThumbnail decodes file previews near tile size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: ReviewAssetThumbnail(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: '/tmp/IMG_1.JPG',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 4032,
                  height: 3024,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  thumbnailPath: '/tmp/IMG_1.JPG',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<ResizeImage>()
          .having((provider) => provider.width, 'width', isNotNull)
          .having((provider) => provider.height, 'height', isNotNull),
    );
    expect(image.filterQuality, FilterQuality.low);
  });

  testWidgets('ReviewAssetThumbnail rebuilds thumbnail from source uri', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls.add(call);
      if (call.method == 'createThumbnail') {
        return Future<Object?>.value('/files/noema_media/thumbs/v4-photo.jpg');
      }
      return Future<Object?>.value(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final recoveredPaths = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: ReviewAssetThumbnail(
              asset: ReviewAsset(
                displayName: 'IMG_2.JPG',
                photo: PhotoAsset(
                  id: 'photo-2',
                  sessionId: 'session-1',
                  platformAssetId: 'content://media/photo/2',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 4032,
                  height: 3024,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/2',
                ),
              ),
              onThumbnailLoaded: (photoId, thumbnailPath) {
                recoveredPaths[photoId] = thumbnailPath;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(calls.single.method, 'createThumbnail');
    expect(calls.single.arguments['uri'], 'content://media/photo/2');
    expect(calls.single.arguments['maxSize'], 256);
    expect(recoveredPaths['photo-2'], '/files/noema_media/thumbs/v4-photo.jpg');
  });
}
