import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appraise/appraise_screen.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/processing/photo_viewer_page.dart';

void main() {
  testWidgets('photo viewer defaults to slide page transition', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PhotoViewerPage(workspaceController: _controller())),
    );
    await tester.pump();

    final viewer = tester.widget<PhotoViewerPage>(find.byType(PhotoViewerPage));
    expect(viewer.pageVisualTransition, PhotoViewerPageVisualTransition.slide);
  });

  testWidgets('second pointer immediately locks photo viewer paging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: PhotoViewerPage(workspaceController: _controller())),
    );
    await tester.pump();

    final pageViewFinder = find.byType(PageView);
    expect(pageViewFinder, findsOneWidget);
    expect(
      tester.widget<PageView>(pageViewFinder).physics,
      isA<BouncingScrollPhysics>(),
    );

    final viewerCenter = tester.getCenter(find.byType(InteractiveViewer));
    final firstFinger = await tester.createGesture(pointer: 1);
    await firstFinger.down(viewerCenter.translate(-28, 0));
    await tester.pump();

    expect(
      tester.widget<PageView>(pageViewFinder).physics,
      isA<BouncingScrollPhysics>(),
    );

    final secondFinger = await tester.createGesture(pointer: 2);
    await secondFinger.down(viewerCenter.translate(28, 0));
    await tester.pump();

    expect(
      tester.widget<PageView>(pageViewFinder).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    await secondFinger.up();
    await firstFinger.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.widget<PageView>(pageViewFinder).physics,
      isA<BouncingScrollPhysics>(),
    );
  });

  testWidgets('double tap zoom enables panning the enlarged photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: PhotoViewerPage(workspaceController: _controller())),
    );
    await tester.pump();

    InteractiveViewer viewer() =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

    expect(viewer().panEnabled, isFalse);

    final target = find.byType(InteractiveViewer);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(viewer().panEnabled, isTrue);
  });

  testWidgets('orientation fill keeps a landscape photo inside the top frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(),
          imageBottomInsetFraction: 0.64,
          fillByPhotoOrientation: true,
        ),
      ),
    );
    await tester.pump();

    final image = find.byKey(const ValueKey('photo-viewer-fitted-image')).first;
    final reviewImage = tester.widget<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage).first,
    );
    final imageSize = tester.getSize(image);
    final imageRect = tester.getRect(image);
    final frameBottom = 900 * (1 - 0.64);

    expect(imageSize.width, closeTo(600, 1));
    expect(imageSize.height, closeTo(frameBottom, 1));
    expect(imageRect.top, greaterThanOrEqualTo(0));
    expect(imageRect.bottom, lessThanOrEqualTo(frameBottom + 1));
    expect(reviewImage.fit, BoxFit.cover);
  });

  testWidgets('viewer uses decoded image ratio when metadata is stale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(
            width: 3024,
            height: 4032,
            previewBytes: _pngBytes(width: 800, height: 400),
          ),
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    final image = find.byKey(const ValueKey('photo-viewer-fitted-image')).first;
    final imageSize = tester.getSize(image);

    expect(imageSize.width, closeTo(600, 1));
    expect(imageSize.height, closeTo(300, 1));
  });

  testWidgets('viewer requests preview even when thumbnail fallback exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(
            sourceUri: 'content://media/photo/1',
            thumbnailPath: '/cache/photo-thumb.jpg',
          ),
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    final reviewImage = tester.widget<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage).first,
    );

    expect(reviewImage.recoverKind, NoemaRecoverableImageKind.preview);
    expect(reviewImage.recoverMaxSize, 4096);
    expect(reviewImage.recoverWhenPathMissing, isTrue);
    expect(reviewImage.refreshWhenSourceAvailable, isTrue);
  });

  testWidgets('viewer prewarms neighboring source previews before paging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = Directory.systemTemp.createTempSync(
      'noema-viewer-prewarm-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) async {
            calls.add(call);
            if (call.method != 'createPreview') {
              return null;
            }
            final uri = call.arguments['uri'] as String;
            final filename = uri.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final file = File('${tempDir.path}/$filename.png')
              ..writeAsBytesSync(_pngBytes(width: 24, height: 16));
            return file.path;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(noemaMediaPickerChannelName),
            null,
          );
    });

    final controller = _controllerWithSourceUris(count: 6);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: controller,
          initialPhotoId: 'photo-1',
          sort: 'oldestFirst',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final previewUris = [
      for (final call in calls)
        if (call.method == 'createPreview') call.arguments['uri'] as String,
    ];

    expect(previewUris, contains('content://media/photo/2'));
    expect(
      controller.workspace.assetById('photo-2')?.photo.previewPath,
      isNotNull,
    );
    expect(previewUris, isNot(contains('content://media/photo/4')));
  });

  testWidgets('viewer keeps decoded images cacheable after closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(
            sourceUri: 'content://media/photo/1',
            thumbnailPath: '/cache/photo-thumb.jpg',
          ),
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    final reviewImage = tester.widget<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage).first,
    );

    expect(reviewImage.evictOnDispose, isFalse);
  });

  testWidgets('viewer avoids thumbnail underlay when a preview path exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(
            thumbnailPath: '/cache/photo-thumb.jpg',
            previewPath: '/cache/photo-preview.jpg',
          ),
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey(
          'photo-viewer-thumbnail-underlay-/cache/photo-thumb.jpg',
        ),
      ),
      findsNothing,
    );
    final reviewImage = tester.widget<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage).first,
    );
    expect(reviewImage.revealOnFirstAvailable, isFalse);
  });

  testWidgets(
    'viewer does not let import preview bytes override source ratio',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewerPage(
            workspaceController: _controller(
              width: 3024,
              height: 4032,
              previewBytes: _pngBytes(width: 800, height: 400),
              sourceUri: 'content://media/photo/portrait',
            ),
            initialPhotoId: 'photo-1',
          ),
        ),
      );
      await tester.pump();

      final image = find
          .byKey(const ValueKey('photo-viewer-fitted-image'))
          .first;
      final imageSize = tester.getSize(image);

      expect(imageSize.width, closeTo(600, 1));
      expect(imageSize.height, closeTo(800, 1));
    },
  );

  testWidgets('viewer switches from preview bytes to recovered preview path', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(
            sourceUri: 'content://media/photo/1',
            previewBytes: _pngBytes(width: 80, height: 40),
          ),
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    final reviewImage = tester.widget<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage).first,
    );

    expect(reviewImage.recoverKind, NoemaRecoverableImageKind.preview);
    expect(reviewImage.refreshWhenSourceAvailable, isTrue);
  });

  testWidgets('viewer decode size stays stable while appraisal sheet moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inset = ValueNotifier<double>(0.12);
    addTearDown(inset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          workspaceController: _controller(width: 3000, height: 2000),
          imageBottomInsetFraction: 0.12,
          imageBottomInsetFractionListenable: inset,
        ),
      ),
    );
    await tester.pump();

    NoemaRecoverableReviewImage reviewImage() =>
        tester.widget<NoemaRecoverableReviewImage>(
          find.byType(NoemaRecoverableReviewImage).first,
        );

    final initialCacheWidth = reviewImage().cacheWidth;
    final initialCacheHeight = reviewImage().cacheHeight;

    inset.value = 0.64;
    await tester.pump();

    expect(reviewImage().cacheWidth, initialCacheWidth);
    expect(reviewImage().cacheHeight, initialCacheHeight);
    expect(
      tester.getSize(find.byKey(const ValueKey('photo-viewer-fitted-image'))),
      isNot(equals(const Size(600, 400))),
    );
  });

  testWidgets('observe viewer mounts appraisal sheet at the lowest stop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller();
    controller.setAssetAppraisal('photo-1', _appraisal());

    await tester.pumpWidget(
      MaterialApp(
        home: AppraiseSheetPhotoViewerPage(
          workspaceController: controller,
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    final sheet = find.byKey(const ValueKey('appraise-viewer-sheet'));
    expect(sheet, findsOneWidget);
    expect(tester.getRect(sheet).height, closeTo(90, 2));
    expect(find.text('总观内容。'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('appraise-viewer-sheet-handle')),
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();

    expect(find.text('总观内容。'), findsOneWidget);
    expect(find.text('你最想保留什么？'), findsOneWidget);
  });

  testWidgets('observe viewer appraisal sheet removes the open photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: AppraiseSheetPhotoViewerPage(
          workspaceController: controller,
          initialPhotoId: 'photo-1',
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('appraise-viewer-sheet-handle')),
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('appraise-viewer-sheet-remove')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('appraise-viewer-sheet-remove')),
    );
    await tester.pumpAndSettle();

    expect(find.text('从此境移除'), findsOneWidget);
    expect(find.text('只从此境移除'), findsOneWidget);
    expect(find.text('删除手机相册原图'), findsOneWidget);

    await tester.tap(find.text('只从此境移除'));
    await tester.pumpAndSettle();

    expect(controller.workspace.assets, hasLength(2));
    expect(controller.workspace.assetById('photo-1'), isNull);
  });
}

ReviewWorkspaceController _controller({
  int width = 4032,
  int height = 3024,
  Uint8List? previewBytes,
  String? sourceUri,
  String? thumbnailPath,
  String? previewPath,
}) {
  final controller = ReviewWorkspaceController();
  final capturedAt = DateTime(2026, 6, 4, 10);
  controller.loadSelectedAssets(
    List.generate(
      3,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
        width: width,
        height: height,
        sourceUri: sourceUri,
        thumbnailPath: thumbnailPath,
        previewBytes: index == 0 ? previewBytes : null,
        createdAt: capturedAt.add(Duration(seconds: index)),
      ),
    ),
    name: '友人',
  );
  if (previewPath != null) {
    controller.updateAssetPreviewPath('photo-1', previewPath);
  }
  return controller;
}

ReviewWorkspaceController _controllerWithSourceUris({required int count}) {
  final controller = ReviewWorkspaceController();
  final capturedAt = DateTime(2026, 6, 4, 10);
  controller.loadSelectedAssets(
    List.generate(
      count,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
        width: 4032,
        height: 3024,
        sourceUri: 'content://media/photo/${index + 1}',
        createdAt: capturedAt.add(Duration(seconds: index)),
      ),
    ),
    name: '友人',
  );
  return controller;
}

Uint8List _pngBytes({required int width, required int height}) {
  return Uint8List.fromList(
    img.encodePng(img.Image(width: width, height: height)),
  );
}

PhotoAppraisal _appraisal() {
  return PhotoAppraisal(
    initial: '画面成立。',
    overall: '总观内容。',
    refine: '打磨内容。',
    question: '你最想保留什么？',
    metrics: [
      const PhotoAppraisalMetric(label: '主题', value: 19, text: '主题明确。'),
      const PhotoAppraisalMetric(label: '技术', value: 18, text: '技术稳定。'),
      const PhotoAppraisalMetric(label: '情感', value: 20, text: '情感成立。'),
      const PhotoAppraisalMetric(label: '联想', value: 17, text: '联想可加强。'),
    ],
  );
}
