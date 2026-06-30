import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/features/import/noema_media_picker.dart';

void main() {
  testWidgets('evictOnDispose can dispose an active review image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                previewBytes: _solidPng(),
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                ),
              ),
              fit: BoxFit.cover,
              cacheWidth: 80,
              cacheHeight: 80,
              recoverKind: NoemaRecoverableImageKind.preview,
              recoverMaxSize: 320,
              evictOnDispose: true,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal does not flash back to fallback on parent rebuild', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'noema-recoverable-image-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final thumbnail = File('${tempDir.path}/thumb.png')
      ..writeAsBytesSync(_solidPng());
    final asset = ReviewAsset(
      displayName: 'IMG_1.JPG',
      photo: PhotoAsset(
        id: 'photo-1',
        sessionId: 'session-1',
        platformAssetId: 'file-1',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        width: 32,
        height: 32,
        mediaKind: MediaKind.photo,
        availability: AssetAvailability.available,
        thumbnailPath: thumbnail.path,
      ),
    );

    Widget host(int revision) {
      return MaterialApp(
        home: Center(
          child: Column(
            children: [
              Text('revision-$revision'),
              SizedBox(
                width: 80,
                height: 80,
                child: NoemaRecoverableReviewImage(
                  asset: asset,
                  fit: BoxFit.cover,
                  cacheWidth: 80,
                  cacheHeight: 80,
                  recoverKind: NoemaRecoverableImageKind.thumbnail,
                  recoverMaxSize: 320,
                  allowAlternatePathFallback: false,
                  revealOnFirstAvailable: true,
                  fallback: const SizedBox(
                    key: ValueKey('fallback'),
                    width: 80,
                    height: 80,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(host(1));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).frameBuilder, isNotNull);

    await tester.pumpWidget(host(2));
    await tester.pump();

    expect(find.text('revision-2'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
  });

  testWidgets('preview bytes do not block preview path recovery', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) async {
            calls.add(call);
            if (call.method == 'createPreview') {
              return '/cache/full-preview.jpg';
            }
            return null;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    final recovered = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                previewBytes: _solidPng(),
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/1',
                ),
              ),
              fit: BoxFit.contain,
              recoverKind: NoemaRecoverableImageKind.preview,
              recoverMaxSize: 4096,
              refreshWhenSourceAvailable: true,
              onRecovered: (photoId, path) => recovered[photoId] = path,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(calls.where((call) => call.method == 'createPreview'), hasLength(1));
    expect(calls.single.arguments['maxSize'], 4096);
    expect(recovered['photo-1'], '/cache/full-preview.jpg');
  });

  testWidgets('recovered preview keeps one gapless image element', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'noema-gapless-recovery-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final recoveredPreview = File('${tempDir.path}/preview.png')
      ..writeAsBytesSync(_solidPng());
    final previewCompleter = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) {
            if (call.method == 'createPreview') {
              return previewCompleter.future;
            }
            return Future<Object?>.value(null);
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                previewBytes: _solidPng(),
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/1',
                ),
              ),
              fit: BoxFit.contain,
              recoverKind: NoemaRecoverableImageKind.preview,
              recoverMaxSize: 4096,
              refreshWhenSourceAvailable: true,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    var image = tester.widget<Image>(find.byType(Image));
    expect(image.key, isNull);
    expect(image.gaplessPlayback, isTrue);

    previewCompleter.complete(recoveredPreview.path);
    await tester.pump();
    await tester.pump();

    image = tester.widget<Image>(find.byType(Image));
    expect(image.key, isNull);
    expect(image.gaplessPlayback, isTrue);
  });

  testWidgets('stale native cache paths stay visible while regenerating', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'noema-stale-cache-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final staleThumbnail =
        File('${tempDir.path}/noema_media/thumbs/v4_old_320.jpg')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_solidPng());
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) async {
            calls.add(call);
            if (call.method == 'createThumbnail') {
              return '/data/user/0/app/files/noema_media/thumbs/v5_fresh_320.jpg';
            }
            return null;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    final recovered = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/1',
                  thumbnailPath: staleThumbnail.path,
                ),
              ),
              fit: BoxFit.cover,
              recoverKind: NoemaRecoverableImageKind.thumbnail,
              recoverMaxSize: 320,
              allowAlternatePathFallback: false,
              onRecovered: (photoId, path) => recovered[photoId] = path,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(
      calls.where((call) => call.method == 'createThumbnail'),
      hasLength(1),
    );
    expect(recovered['photo-1'], endsWith('/v5_fresh_320.jpg'));
  });

  testWidgets('mismatched v5 cache path refreshes from source uri', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'noema-mismatched-cache-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final wrongThumbnail =
        File('${tempDir.path}/noema_media/thumbs/v5_123_320.jpg')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_solidPng());
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) async {
            calls.add(call);
            if (call.method == 'createThumbnail') {
              return '/cache/fresh-alpha.jpg';
            }
            return null;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    final recovered = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/alpha',
                  thumbnailPath: wrongThumbnail.path,
                ),
              ),
              fit: BoxFit.cover,
              recoverKind: NoemaRecoverableImageKind.thumbnail,
              recoverMaxSize: 320,
              allowAlternatePathFallback: false,
              onRecovered: (photoId, path) => recovered[photoId] = path,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      calls.where((call) => call.method == 'createThumbnail'),
      hasLength(1),
    );
    expect(recovered['photo-1'], '/cache/fresh-alpha.jpg');
  });

  testWidgets('stale cache refresh failure does not report missing', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'noema-stale-cache-failure-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final staleThumbnail =
        File('${tempDir.path}/noema_media/thumbs/v4_old_320.jpg')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_solidPng());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (_) async => null,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    final failures = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: NoemaRecoverableReviewImage(
              asset: ReviewAsset(
                displayName: 'IMG_1.JPG',
                photo: PhotoAsset(
                  id: 'photo-1',
                  sessionId: 'session-1',
                  platformAssetId: 'memory-1',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  width: 32,
                  height: 32,
                  mediaKind: MediaKind.photo,
                  availability: AssetAvailability.available,
                  sourceUri: 'content://media/photo/1',
                  thumbnailPath: staleThumbnail.path,
                ),
              ),
              fit: BoxFit.cover,
              recoverKind: NoemaRecoverableImageKind.thumbnail,
              recoverMaxSize: 320,
              allowAlternatePathFallback: false,
              onRecoveryFailed: failures.add,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(failures, isEmpty);
  });
}

Uint8List _solidPng() {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(120, 160, 220));
  return Uint8List.fromList(img.encodePng(image));
}
