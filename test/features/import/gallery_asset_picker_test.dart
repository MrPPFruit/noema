import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/import/gallery_asset_picker.dart';
import 'package:noema/features/import/noema_media_picker.dart';

void main() {
  testWidgets('Android import requests gallery access before Photo Picker', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'requestGalleryAccess' => 'full',
        'refreshGalleryIndex' => {
          'access': 'full',
          'count': 2,
          'path': '/files/noema_media/index/gallery_index_v1.json',
        },
        'warmGalleryThumbnails' => 2,
        'pickImages' => [
          {
            'uri': 'content://media/photo/7',
            'name': 'IMG_0007.JPG',
            'width': 3000,
            'height': 2000,
          },
        ],
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    try {
      await tester.pumpWidget(const SizedBox());
      final assets = await pickGalleryAssets(
        tester.element(find.byType(SizedBox)),
      );

      expect(assets.single.sourceUri, 'content://media/photo/7');
      expect(calls.map((call) => call.method), [
        'requestGalleryAccess',
        'refreshGalleryIndex',
        'warmGalleryThumbnails',
        'pickImages',
      ]);
      expect(calls.last.arguments['limit'], galleryPickerLimit);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android import stops when gallery access is denied', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'requestGalleryAccess' ? 'denied' : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    try {
      await tester.pumpWidget(const SizedBox());

      await expectLater(
        pickGalleryAssets(tester.element(find.byType(SizedBox))),
        throwsA(isA<NoemaGalleryAccessDeniedException>()),
      );
      expect(calls.map((call) => call.method), ['requestGalleryAccess']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'iOS import uses native picker without pre-requesting library access',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'pickImages' => [
            {
              'uri': 'ios-phasset-local-id',
              'id': 'ios-phasset-local-id',
              'name': 'IMG_0008.HEIC',
              'width': 4032,
              'height': 3024,
            },
          ],
          _ => null,
        };
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      try {
        await tester.pumpWidget(const SizedBox());
        final assets = await pickGalleryAssets(
          tester.element(find.byType(SizedBox)),
        );

        expect(assets.single.sourceUri, 'ios-phasset-local-id');
        expect(calls.map((call) => call.method), ['pickImages']);
        expect(calls.single.arguments['limit'], galleryPickerLimit);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('iOS import does not fallback when native channel is missing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    const channel = MethodChannel(noemaMediaPickerChannelName);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      throw MissingPluginException('No implementation found');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    try {
      await tester.pumpWidget(const SizedBox());

      await expectLater(
        pickGalleryAssets(tester.element(find.byType(SizedBox))),
        throwsA(isA<MissingPluginException>()),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
