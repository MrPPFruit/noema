import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/review_groups/review_groups_screen.dart';

void main() {
  testWidgets('empty review groups show a calm empty state', (tester) async {
    await tester.pumpWidget(_TestApp(controller: ReviewWorkspaceController()));

    expect(find.text('当前境内暂无可甄选的相似照片'), findsOneWidget);
    expect(find.text('快甄'), findsWidgets);
    expect(find.text('对照甄'), findsWidgets);
    expect(
      find.byKey(const ValueKey('review-group-floating-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-groups-clear-completed-out-button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('single attention groups stay out of cull review', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Unavailable',
        previewUnavailable: true,
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    expect(find.text('当前境内暂无可甄选的相似照片'), findsOneWidget);
    expect(find.text('快甄'), findsWidgets);
    expect(find.text('对照甄'), findsWidgets);
    expect(
      find.byKey(const ValueKey('review-group-floating-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsNothing,
    );
  });

  testWidgets('review group detail previews without changing photo status', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 10);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 4032,
        height: 3024,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 4)),
      ),
      SelectedGalleryAsset(
        id: 'asset-4',
        name: 'Photo 4',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 6)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.tap(find.byKey(const ValueKey('review-group-card-group-1')));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('review-photo-status-photo-2')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('review-photo-tile-photo-2')));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('cull-preview-zoomable-photo-2')),
      findsOneWidget,
    );
    expect(controller.decisions['photo-2'], isNull);
  });

  testWidgets('fast cull preview closes from outside the photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 10, 30);
    controller.loadSelectedAssets([
      for (var index = 0; index < 3; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(Duration(seconds: index * 2)),
        ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openFastCull(tester);

    await tester.tap(find.byKey(const ValueKey('fast-cull-current-photo')));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('cull-preview-zoomable-photo-1')),
      findsOneWidget,
    );
    final previewFrame = tester.getRect(
      find.byKey(const ValueKey('cull-preview-photo-frame-photo-1')),
    );
    expect(previewFrame.width, closeTo(390, 0.1));
    expect(previewFrame.height, closeTo(520, 0.1));

    await tester.tapAt(const Offset(195, 790));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(controller.decisions['photo-1'], isNull);
    expect(
      find.byKey(const ValueKey('cull-preview-zoomable-photo-1')),
      findsNothing,
    );
  });

  testWidgets('clear outbound photos can remove only space indexes', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 11);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 4)),
      ),
      SelectedGalleryAsset(
        id: 'asset-4',
        name: 'Photo 4',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 6)),
      ),
    ]);
    controller.recordDecision('photo-2', Decision.reviewForRemoval);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.tap(find.byKey(const ValueKey('review-group-card-group-1')));
    await _pumpCullUi(tester);

    await tester.tap(find.byTooltip('清除出境'));
    await _pumpCullUi(tester);

    expect(find.text('从此境移除'), findsOneWidget);
    expect(find.text('只从此境移除'), findsOneWidget);
    expect(find.text('删除手机相册原图'), findsOneWidget);

    await tester.tap(find.text('只从此境移除'));
    await tester.pump();

    expect(controller.workspace.assetById('photo-2'), isNull);
    expect(controller.workspace.assets, hasLength(3));
    expect(controller.decisions.containsKey('photo-2'), isFalse);
  });

  testWidgets('global clear only removes discards from completed groups', (
    tester,
  ) async {
    final deletedPaths = <String>[];
    final deletedUris = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(noemaMediaPickerChannelName),
          (call) async {
            if (call.method == 'galleryAccessStatus') {
              return 'full';
            }
            if (call.method == 'deleteCachedFiles') {
              final arguments = call.arguments as Map<Object?, Object?>;
              final paths = (arguments['paths'] as List<Object?>)
                  .cast<String>();
              deletedPaths.addAll(paths);
              return paths.length;
            }
            if (call.method == 'deleteMediaItems') {
              final arguments = call.arguments as Map<Object?, Object?>;
              final uris = (arguments['uris'] as List<Object?>).cast<String>();
              deletedUris.addAll(uris);
              return <String, Object?>{
                'deleted': true,
                'count': uris.length,
                'cancelled': false,
              };
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

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 11, 30);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        sourceUri: 'content://media/external/images/media/1',
        thumbnailPath: '/data/noema_media/thumbs/photo-1.jpg',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        sourceUri: 'content://media/external/images/media/2',
        thumbnailPath: '/data/noema_media/thumbs/photo-2.jpg',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        sourceUri: 'content://media/external/images/media/3',
        thumbnailPath: '/data/noema_media/thumbs/photo-3.jpg',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 34)),
      ),
      SelectedGalleryAsset(
        id: 'asset-4',
        name: 'Photo 4',
        sourceUri: 'content://media/external/images/media/4',
        thumbnailPath: '/data/noema_media/thumbs/photo-4.jpg',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 36)),
      ),
    ]);
    controller.recordDecision('photo-1', Decision.keep);
    controller.recordDecision('photo-2', Decision.reviewForRemoval);
    controller.recordDecision('photo-3', Decision.reviewForRemoval);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.tap(
      find.byKey(const ValueKey('review-groups-clear-completed-out-button')),
    );
    await _pumpCullUi(tester);

    expect(find.text('从此境移除'), findsOneWidget);
    expect(find.textContaining('将处理已完成组中标记丢弃的 1 张照片'), findsOneWidget);
    expect(find.text('只从此境移除'), findsOneWidget);
    expect(find.text('删除手机相册原图'), findsOneWidget);

    await tester.tap(find.text('删除手机相册原图'));
    await tester.pump();
    await tester.idle();

    expect(controller.workspace.assetById('photo-2'), isNull);
    expect(controller.workspace.assetById('photo-3'), isNotNull);
    expect(controller.workspace.assets, hasLength(3));
    expect(controller.decisions.containsKey('photo-2'), isFalse);
    expect(
      controller.decisions['photo-3']?.decision,
      Decision.reviewForRemoval,
    );
    expect(deletedUris, ['content://media/external/images/media/2']);
    expect(deletedPaths, contains('/data/noema_media/thumbs/photo-2.jpg'));
    expect(
      deletedPaths,
      isNot(contains('/data/noema_media/thumbs/photo-3.jpg')),
    );
  });

  testWidgets('new review groups do not show default progress', (tester) async {
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 12);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 4032,
        height: 3024,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    expect(find.text('0%'), findsNothing);
    expect(controller.decisions, isEmpty);

    await tester.tap(find.byKey(const ValueKey('review-group-card-group-1')));
    await _pumpCullUi(tester);

    expect(find.text('0%'), findsNothing);
  });

  testWidgets('review groups open on the current unfinished group', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 12, 5);
    controller.loadSelectedAssets([
      for (var index = 0; index < 6; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(
            Duration(seconds: (index ~/ 2) * 34 + (index % 2) * 2),
          ),
        ),
    ]);
    controller.recordDecision('photo-3', Decision.keep);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('review-group-card-group-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('review-group-edge-previous')));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsOneWidget,
    );

    controller.recordDecision('photo-5', Decision.keep);
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsOneWidget,
    );
  });

  testWidgets('review group detail opens as a constrained half sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 12, 10);
    controller.loadSelectedAssets([
      for (var index = 0; index < 20; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt,
        ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.tap(find.byKey(const ValueKey('review-group-card-group-1')));
    await _pumpCullUi(tester);

    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('review-group-detail-sheet')),
    );
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(sheetRect.height, greaterThan(viewportHeight * 0.64));
    expect(sheetRect.height, lessThan(viewportHeight * 0.72));
    expect(sheetRect.bottom, closeTo(viewportHeight, 0.5));
    expect(
      find.byKey(const ValueKey('review-group-detail-handle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-detail-barrier')),
      findsOneWidget,
    );
    expect(find.byTooltip('快甄'), findsNothing);
    expect(find.byTooltip('对照甄'), findsNothing);
    expect(
      find.byKey(const ValueKey('review-photo-status-photo-1')),
      findsNothing,
    );

    final firstTileRect = tester.getRect(
      find.byKey(const ValueKey('review-photo-tile-photo-1')),
    );
    final fourthTileRect = tester.getRect(
      find.byKey(const ValueKey('review-photo-tile-photo-4')),
    );
    expect(firstTileRect.width, closeTo(firstTileRect.height, 0.5));
    expect(fourthTileRect.width, closeTo(fourthTileRect.height, 0.5));
    expect(firstTileRect.top, closeTo(fourthTileRect.top, 0.5));
    expect(firstTileRect.left, lessThan(fourthTileRect.left));

    await tester.drag(
      find.byKey(const ValueKey('review-group-detail-grid')),
      const Offset(0, -220),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.byKey(const ValueKey('review-photo-tile-photo-20')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await _pumpCullUi(tester);

    final hiddenSheetRect = tester.getRect(
      find.byKey(const ValueKey('review-group-detail-sheet')),
    );
    expect(hiddenSheetRect.top, greaterThanOrEqualTo(viewportHeight));
    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'horizontal cull home drag switches groups with visible neighbors',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = ReviewWorkspaceController();
      final capturedAt = DateTime(2026, 6, 3, 12, 30);
      controller.loadSelectedAssets([
        SelectedGalleryAsset(
          id: 'asset-1',
          name: 'Photo 1',
          width: 3024,
          height: 4032,
          createdAt: capturedAt,
        ),
        SelectedGalleryAsset(
          id: 'asset-2',
          name: 'Photo 2',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(const Duration(seconds: 2)),
        ),
        SelectedGalleryAsset(
          id: 'asset-3',
          name: 'Photo 3',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(const Duration(seconds: 34)),
        ),
        SelectedGalleryAsset(
          id: 'asset-4',
          name: 'Photo 4',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(const Duration(seconds: 36)),
        ),
      ]);

      await tester.pumpWidget(_TestApp(controller: controller));
      await _pumpCullUi(tester);

      expect(
        find.byKey(const ValueKey('review-group-card-group-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-neighbor-group-2')),
        findsOneWidget,
      );

      await tester.drag(
        find.byKey(const ValueKey('review-group-card-group-1')),
        const Offset(-82, 0),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('review-group-layer-group-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-layer-group-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-card-group-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-neighbor-group-1')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 520));

      expect(
        find.byKey(const ValueKey('review-group-card-group-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-layer-group-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('review-group-layer-group-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-neighbor-group-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('cull home emits haptic when a mode target highlights', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final hapticCalls = _recordHapticCalls(tester);

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(_burstGroupAssets(groupCount: 1));

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.drag(
      find.byKey(const ValueKey('review-group-card-group-1')),
      const Offset(0, -150),
    );
    await tester.pump();

    expect(_lightImpactCount(hapticCalls), 1);

    await _pumpCullUi(tester);
    expect(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      findsOneWidget,
    );
  });

  testWidgets('horizontal cull home edge taps switch groups', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 12, 45);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 34)),
      ),
      SelectedGalleryAsset(
        id: 'asset-4',
        name: 'Photo 4',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 36)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    await tester.tap(find.byKey(const ValueKey('review-group-edge-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));

    expect(
      find.byKey(const ValueKey('review-group-card-group-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('review-group-edge-previous')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));

    expect(
      find.byKey(const ValueKey('review-group-card-group-1')),
      findsOneWidget,
    );
  });

  testWidgets('portrait review group controls stay inside cull boundaries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 12, 50);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Portrait 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Portrait 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('review-group-floating-field')),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('review-group-card-group-1')),
    );
    final progressRect = tester.getRect(
      find.byKey(const ValueKey('review-group-progress-seal')),
    );
    final indicatorRect = tester.getRect(
      find.byKey(const ValueKey('review-group-page-indicator-window')),
    );
    final upperBoundaryY = fieldRect.top + fieldRect.height * 0.18;
    final lowerBoundaryY = fieldRect.top + fieldRect.height * 0.82;

    expect(progressRect.top, greaterThanOrEqualTo(upperBoundaryY + 11.5));
    expect(progressRect.bottom, lessThanOrEqualTo(cardRect.top - 7.5));
    expect(indicatorRect.top, greaterThanOrEqualTo(cardRect.bottom + 7.5));
    expect(indicatorRect.bottom, lessThanOrEqualTo(lowerBoundaryY - 11.5));
  });

  testWidgets('page indicator caps overflow and centers the current dot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(_burstGroupAssets(groupCount: 12));

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);

    for (var groupIndex = 1; groupIndex <= 4; groupIndex += 1) {
      await tester.drag(
        find.byKey(ValueKey('review-group-card-group-$groupIndex')),
        const Offset(-82, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 520));
    }

    expect(
      find.byKey(const ValueKey('review-group-card-group-5')),
      findsOneWidget,
    );

    final slotFinder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('review-group-page-indicator-slot-');
    });
    expect(slotFinder, findsNWidgets(7));
    expect(
      find.byKey(
        const ValueKey('review-group-page-indicator-ellipsis-leading'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('review-group-page-indicator-ellipsis-trailing'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-current')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-6')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('review-group-page-indicator-group-group-12')),
      findsNothing,
    );

    final windowCenter = tester.getCenter(
      find.byKey(const ValueKey('review-group-page-indicator-window')),
    );
    final currentCenter = tester.getCenter(
      find.byKey(const ValueKey('review-group-page-indicator-current')),
    );
    expect(currentCenter.dx, closeTo(windowCenter.dx, 0.5));
  });

  testWidgets('fast cull drag decisions and recall thumbnails are reversible', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 13);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 4)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openFastCull(tester);

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, -150),
    );
    await _pumpCullUi(tester);

    expect(
      controller.decisions['photo-1']?.decision,
      Decision.reviewForRemoval,
    );
    expect(
      find.byKey(const ValueKey('fast-cull-discard-photo-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('fast-cull-discard-photo-1')));
    await _pumpCullUi(tester);

    expect(controller.decisions.containsKey('photo-1'), isFalse);
    expect(
      find.byKey(const ValueKey('fast-cull-discard-photo-1')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, 150),
    );
    await _pumpCullUi(tester);

    expect(controller.decisions['photo-1']?.decision, Decision.keep);
    expect(
      find.byKey(const ValueKey('fast-cull-keep-photo-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('fast-cull-keep-photo-1')));
    await _pumpCullUi(tester);

    expect(controller.decisions.containsKey('photo-1'), isFalse);
    expect(find.byKey(const ValueKey('fast-cull-keep-photo-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      findsOneWidget,
    );
  });

  testWidgets('fast cull emits haptic when a decision target highlights', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final hapticCalls = _recordHapticCalls(tester);

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(_burstGroupAssets(groupCount: 1));

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openFastCull(tester);
    hapticCalls.clear();

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, -150),
    );
    await tester.pump();

    expect(_lightImpactCount(hapticCalls), 1);

    await _pumpCullUi(tester);
    expect(
      controller.decisions['photo-1']?.decision,
      Decision.reviewForRemoval,
    );
  });

  testWidgets('fast cull completion can continue to next unfinished group', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 13, 30);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 34)),
      ),
      SelectedGalleryAsset(
        id: 'asset-4',
        name: 'Photo 4',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 36)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openFastCull(tester);

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, -150),
    );
    await _pumpCullUi(tester);
    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, 150),
    );
    await _pumpCullUi(tester);

    expect(find.text('这组已完成'), findsOneWidget);
    expect(find.text('返回甄页面'), findsOneWidget);
    expect(find.text('下一组未完成'), findsOneWidget);

    await tester.tap(find.text('下一组未完成'));
    await _pumpCullUi(tester);

    expect(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      findsOneWidget,
    );
    expect(find.text('这组已完成'), findsNothing);
    expect(controller.decisions.containsKey('photo-3'), isFalse);
  });

  testWidgets('fast cull target labels keep equal arc spacing on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 14);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openFastCull(tester);

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('fast-cull-boundary-field')),
    );
    final discardCenterY = tester
        .getCenter(find.byKey(const ValueKey('fast-cull-discard-label')))
        .dy;
    final keepCenterY = tester
        .getCenter(find.byKey(const ValueKey('fast-cull-keep-label')))
        .dy;
    final upperArcY = fieldRect.top + fieldRect.height * 0.18;
    final lowerArcY = fieldRect.top + fieldRect.height * 0.82;
    final discardGap = upperArcY - discardCenterY;
    final keepGap = keepCenterY - lowerArcY;

    expect(discardGap, closeTo(keepGap, 0.5));
    expect(discardGap, greaterThan(40));
  });

  testWidgets('fast cull recall thumbnails stay square and clear of labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 15);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
      SelectedGalleryAsset(
        id: 'asset-3',
        name: 'Photo 3',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 4)),
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(controller: controller, locale: const Locale('en')),
    );
    await _pumpCullUi(tester);
    await _openFastCull(tester);

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, -150),
    );
    await _pumpCullUi(tester);

    final discardThumbRect = tester.getRect(
      find.byKey(const ValueKey('fast-cull-discard-photo-1')),
    );
    final discardTextRect = tester.getRect(find.text('Discard').first);
    expect(discardThumbRect.width, closeTo(discardThumbRect.height, 0.5));
    expect(
      discardThumbRect.overlaps(discardTextRect),
      isFalse,
      reason: 'thumb=$discardThumbRect text=$discardTextRect',
    );

    await tester.drag(
      find.byKey(const ValueKey('fast-cull-current-photo')),
      const Offset(0, 150),
    );
    await _pumpCullUi(tester);

    final keepThumbRect = tester.getRect(
      find.byKey(const ValueKey('fast-cull-keep-photo-2')),
    );
    final keepTextRect = tester.getRect(find.text('Keep').first);
    expect(keepThumbRect.width, closeTo(keepThumbRect.height, 0.5));
    expect(
      keepThumbRect.overlaps(keepTextRect),
      isFalse,
      reason: 'thumb=$keepThumbRect text=$keepTextRect',
    );
  });

  testWidgets(
    'fast cull queues insert newest thumbnail on the left and scroll',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = ReviewWorkspaceController();
      final capturedAt = DateTime(2026, 6, 3, 16);
      controller.loadSelectedAssets([
        for (var index = 0; index < 6; index += 1)
          SelectedGalleryAsset(
            id: 'asset-${index + 1}',
            name: 'Photo ${index + 1}',
            width: 3024,
            height: 4032,
            createdAt: capturedAt.add(Duration(seconds: index * 2)),
          ),
      ]);

      await tester.pumpWidget(_TestApp(controller: controller));
      await _pumpCullUi(tester);
      await _openFastCull(tester);

      for (var index = 0; index < 3; index += 1) {
        await tester.drag(
          find.byKey(const ValueKey('fast-cull-current-photo')),
          const Offset(0, -150),
        );
        await _pumpCullUi(tester);
      }

      final newestRect = tester.getRect(
        find.byKey(const ValueKey('fast-cull-discard-photo-3')),
      );
      final middleRect = tester.getRect(
        find.byKey(const ValueKey('fast-cull-discard-photo-2')),
      );
      final oldestRect = tester.getRect(
        find.byKey(const ValueKey('fast-cull-discard-photo-1')),
      );
      expect(newestRect.left, lessThan(middleRect.left));
      expect(middleRect.left, lessThan(oldestRect.left));

      for (var index = 0; index < 3; index += 1) {
        await tester.drag(
          find.byKey(const ValueKey('fast-cull-current-photo')),
          const Offset(0, -150),
        );
        await _pumpCullUi(tester);
      }

      final queueFinder = find.byKey(
        const ValueKey('fast-cull-discard-queue-scroll'),
      );
      final queueRect = tester.getRect(queueFinder);
      expect(queueRect.width, closeTo(272, 0.5));

      final sixthBeforeScroll = tester.getRect(
        find.byKey(const ValueKey('fast-cull-discard-photo-1')),
      );
      expect(sixthBeforeScroll.right, greaterThan(queueRect.right));

      await tester.drag(queueFinder, const Offset(-90, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360));

      final sixthAfterScroll = tester.getRect(
        find.byKey(const ValueKey('fast-cull-discard-photo-1')),
      );
      expect(sixthAfterScroll.right, lessThanOrEqualTo(queueRect.right + 1));
    },
  );

  testWidgets('compare cull drags and recalls the challenge photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 17);
    controller.loadSelectedAssets([
      for (var index = 0; index < 4; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(Duration(seconds: index * 2)),
        ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openCompareCull(tester);

    expect(
      find.byKey(const ValueKey('compare-cull-left-photo-photo-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-right-photo-photo-2')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      const Offset(0, -96),
    );
    await _pumpCullUi(tester);

    expect(
      controller.decisions['photo-2']?.decision,
      Decision.reviewForRemoval,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-discard-photo-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-right-photo-photo-3')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('compare-cull-discard-photo-2')),
    );
    await _pumpCullUi(tester);

    expect(controller.decisions.containsKey('photo-2'), isFalse);
    expect(
      find.byKey(const ValueKey('compare-cull-discard-photo-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-right-photo-photo-2')),
      findsOneWidget,
    );
  });

  testWidgets('compare cull emits haptic when a decision target highlights', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final hapticCalls = _recordHapticCalls(tester);

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(_burstGroupAssets(groupCount: 1));

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openCompareCull(tester);
    hapticCalls.clear();

    await tester.drag(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      const Offset(0, -96),
    );
    await tester.pump();

    expect(_lightImpactCount(hapticCalls), 1);

    await _pumpCullUi(tester);
    expect(
      controller.decisions['photo-2']?.decision,
      Decision.reviewForRemoval,
    );
  });

  testWidgets('compare cull centers the last remaining photo', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 17, 30);
    controller.loadSelectedAssets([
      for (var index = 0; index < 3; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(Duration(seconds: index * 2)),
        ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openCompareCull(tester);

    final initialLeftRect = tester.getRect(
      find.byKey(const ValueKey('compare-cull-left-photo-photo-1')),
    );

    await tester.drag(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      const Offset(0, -96),
    );
    await _pumpCullUi(tester);
    await tester.drag(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      const Offset(0, -96),
    );
    await _pumpCullUi(tester);

    expect(
      controller.decisions['photo-2']?.decision,
      Decision.reviewForRemoval,
    );
    expect(
      controller.decisions['photo-3']?.decision,
      Decision.reviewForRemoval,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-right-photo-empty')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      findsNothing,
    );

    final singleRect = tester.getRect(
      find.byKey(const ValueKey('compare-cull-left-photo-photo-1')),
    );
    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('compare-cull-boundary-field')),
    );
    expect(singleRect.center.dx, closeTo(fieldRect.center.dx, 1));
    expect(singleRect.width, greaterThan(initialLeftRect.width + 20));
    expect(singleRect.height, greaterThan(initialLeftRect.height + 40));
    expect(singleRect.left, greaterThanOrEqualTo(fieldRect.left - 1));
    expect(singleRect.right, lessThanOrEqualTo(fieldRect.right + 1));
    expect(singleRect.top, greaterThanOrEqualTo(fieldRect.top + 73));
    expect(singleRect.bottom, lessThanOrEqualTo(fieldRect.bottom - 73));

    await tester.tap(find.byKey(const ValueKey('compare-cull-left-photo')));
    await tester.pump();

    final openTransitionFinder = find.byKey(
      const ValueKey('cull-preview-open-transition-photo-1'),
    );
    expect(openTransitionFinder, findsOneWidget);
    expect(tester.widget<Opacity>(openTransitionFinder).opacity, lessThan(1));

    await tester.pump(const Duration(milliseconds: 520));

    expect(
      find.byKey(const ValueKey('cull-preview-zoomable-photo-1')),
      findsOneWidget,
    );
    final previewFrame = tester.getRect(
      find.byKey(const ValueKey('cull-preview-photo-frame-photo-1')),
    );
    expect(previewFrame.width, closeTo(390, 0.1));
    expect(previewFrame.height, closeTo(520, 0.1));
    expect(
      find.byKey(const ValueKey('compare-cull-pair-preview')),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      find.byKey(const ValueKey('cull-preview-zoomable-photo-1')),
      findsNothing,
    );
  });

  testWidgets('compare single photo frame hugs decoded landscape image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final landscapeBytes = _landscapePngBytes(width: 800, height: 400);
    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 17, 45);
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'Photo 1',
        width: 3024,
        height: 4032,
        previewBytes: landscapeBytes,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: 'asset-2',
        name: 'Photo 2',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(seconds: 2)),
      ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openCompareCull(tester);

    await tester.drag(
      find.byKey(const ValueKey('compare-cull-right-photo')),
      const Offset(0, -96),
    );
    await _pumpCullUi(tester);

    final singleRect = tester.getRect(
      find.byKey(const ValueKey('compare-cull-left-photo-photo-1')),
    );
    expect(singleRect.width / singleRect.height, greaterThan(1.6));
    expect(singleRect.height, lessThan(220));
  });

  testWidgets('compare cull opens paired synchronized preview', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ReviewWorkspaceController();
    final capturedAt = DateTime(2026, 6, 3, 18);
    controller.loadSelectedAssets([
      for (var index = 0; index < 3; index += 1)
        SelectedGalleryAsset(
          id: 'asset-${index + 1}',
          name: 'Photo ${index + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(Duration(seconds: index * 2)),
        ),
    ]);

    await tester.pumpWidget(_TestApp(controller: controller));
    await _pumpCullUi(tester);
    await _openCompareCull(tester);

    await tester.tap(find.byKey(const ValueKey('compare-cull-left-photo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final previewFinder = find.byKey(
      const ValueKey('compare-cull-pair-preview'),
    );
    final leftPreviewFinder = find.byKey(
      const ValueKey('compare-cull-preview-left-photo-photo-1'),
    );
    final rightPreviewFinder = find.byKey(
      const ValueKey('compare-cull-preview-right-photo-photo-2'),
    );
    final leftTravelFinder = find.byKey(
      const ValueKey('compare-cull-preview-travel-left-photo-photo-1'),
    );
    final rightTravelFinder = find.byKey(
      const ValueKey('compare-cull-preview-travel-right-photo-photo-2'),
    );

    expect(previewFinder, findsOneWidget);
    expect(leftTravelFinder, findsOneWidget);
    expect(rightTravelFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 420));

    expect(leftPreviewFinder, findsOneWidget);
    expect(rightPreviewFinder, findsOneWidget);
    expect(leftTravelFinder, findsNothing);
    expect(rightTravelFinder, findsNothing);
    final leftPreviewRect = tester.getRect(leftPreviewFinder);
    final rightPreviewRect = tester.getRect(rightPreviewFinder);
    expect(leftPreviewRect.bottom <= rightPreviewRect.top, isTrue);
    expect(leftPreviewRect.left < rightPreviewRect.right, isTrue);
    expect(rightPreviewRect.left < leftPreviewRect.right, isTrue);
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsNothing);

    await tester.tapAt(const Offset(22, 22));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(previewFinder, findsNothing);

    await tester.tap(find.byKey(const ValueKey('compare-cull-left-photo')));
    await _pumpCullUi(tester);
    expect(previewFinder, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(previewFinder, findsNothing);
    expect(controller.decisions, isEmpty);
  });
}

Future<void> _pumpCullUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 520));
}

Future<void> _openFastCull(
  WidgetTester tester, {
  String groupId = 'group-1',
}) async {
  await tester.drag(
    find.byKey(ValueKey('review-group-card-$groupId')),
    const Offset(0, -150),
  );
  await _pumpCullUi(tester);
}

Future<void> _openCompareCull(
  WidgetTester tester, {
  String groupId = 'group-1',
}) async {
  await tester.drag(
    find.byKey(ValueKey('review-group-card-$groupId')),
    const Offset(0, 150),
  );
  await _pumpCullUi(tester);
}

List<MethodCall> _recordHapticCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

int _lightImpactCount(List<MethodCall> calls) {
  return calls
      .where((call) => call.arguments == 'HapticFeedbackType.lightImpact')
      .length;
}

List<SelectedGalleryAsset> _burstGroupAssets({required int groupCount}) {
  final capturedAt = DateTime(2026, 6, 4, 10);
  return [
    for (var groupIndex = 0; groupIndex < groupCount; groupIndex += 1)
      for (var photoIndex = 0; photoIndex < 2; photoIndex += 1)
        SelectedGalleryAsset(
          id: 'asset-${groupIndex * 2 + photoIndex + 1}',
          name: 'Photo ${groupIndex + 1}-${photoIndex + 1}',
          width: 3024,
          height: 4032,
          createdAt: capturedAt.add(
            Duration(seconds: groupIndex * 34 + photoIndex * 2),
          ),
        ),
  ];
}

Uint8List _landscapePngBytes({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(94, 168, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: width - 1,
    y2: (height / 2).round(),
    color: img.ColorRgb8(159, 216, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.controller, this.locale = const Locale('zh')});

  final ReviewWorkspaceController controller;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: ReviewGroupsScreen(workspaceController: controller),
    );
  }
}
