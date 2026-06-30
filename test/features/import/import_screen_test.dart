import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:noema/app/router.dart';
import 'package:noema/core/models/similar_group.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/import_screen.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/processing/processing_screen.dart';

void main() {
  testWidgets('empty picker result stays on import with calm copy', (
    tester,
  ) async {
    final controller = _sampleWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => const [],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('为境命名'), findsOneWidget);
    expect(find.text('还没有选择照片'), findsOneWidget);
    expect(find.text('0 张'), findsOneWidget);
    expect(find.byTooltip('创建境'), findsNothing);
  });

  testWidgets('back button visual edge aligns with the content column', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => const [],
        ),
      ),
    );

    final backLeft = tester
        .getTopLeft(find.byKey(const ValueKey('import-back-button-visual')))
        .dx;
    final nameLeft = tester
        .getTopLeft(find.byKey(const ValueKey('import-name-input')))
        .dx;

    expect((backLeft - nameLeft).abs(), lessThanOrEqualTo(0.1));
  });

  testWidgets('English space name input keeps the same title font', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('en'),
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => const [],
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('import-name-input')),
    );
    expect(field.style?.fontFamily, 'LXGWWenKaiGB');
  });

  testWidgets('picker exception stays on import with retry copy', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => throw Exception(),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('为境命名'), findsOneWidget);
    expect(find.text('没能打开相册'), findsOneWidget);
  });

  testWidgets('gallery permission denial stays on import with clear copy', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async =>
              throw const NoemaGalleryAccessDeniedException(),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('为境命名'), findsOneWidget);
    expect(find.text('需要先允许访问图库'), findsOneWidget);
  });

  testWidgets('pending picker ignores duplicate taps', (tester) async {
    final controller = ReviewWorkspaceController();
    final completer = Completer<List<SelectedGalleryAsset>>();
    var calls = 0;

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) {
            calls += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await tester.pump();
    await tester.tap(find.byTooltip('添加照片'));
    await tester.pump();

    expect(calls, 1);

    completer.complete(const []);
    await _pumpUi(tester);
  });

  testWidgets(
    'selected images append across picker sessions and skip repeats',
    (tester) async {
      final controller = ReviewWorkspaceController();
      var calls = 0;

      await tester.pumpWidget(
        _TestApp(
          controller: controller,
          importScreen: ImportScreen(
            workspaceController: controller,
            pickAssets: (_) async {
              calls += 1;
              if (calls == 1) {
                return [_asset('asset-1', 'IMG_1.JPG'), _asset('asset-2')];
              }
              return [_asset('asset-2'), _asset('asset-3', 'IMG_3.JPG')];
            },
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加照片'));
      await _pumpUi(tester);

      expect(find.text('2 张'), findsOneWidget);
      expect(find.text('IMG_1.JPG'), findsOneWidget);
      expect(find.text('IMG_2.JPG'), findsOneWidget);

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 4);
      expect(grid.childrenDelegate.estimatedChildCount, 2);

      await tester.tap(find.byTooltip('添加照片'));
      await _pumpUi(tester);

      expect(find.text('3 张'), findsOneWidget);
      expect(find.text('已略过重复照片'), findsOneWidget);
      expect(find.text('IMG_2.JPG'), findsOneWidget);
      expect(find.text('IMG_3.JPG'), findsOneWidget);
      final updatedGrid = tester.widget<GridView>(find.byType(GridView));
      expect(updatedGrid.childrenDelegate.estimatedChildCount, 3);
    },
  );

  testWidgets('append mode caps a large space at the hard photo limit', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets([
      for (var index = 0; index < noemaWorkspaceHardPhotoLimit - 1; index += 1)
        _asset('existing-$index', 'EXISTING_$index.JPG'),
    ], name: '大境');

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          appendMode: true,
          pickAssets: (_) async => [
            _asset('new-1', 'NEW_1.JPG'),
            _asset('new-2', 'NEW_2.JPG'),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('单个境最多先支持 1000 张'), findsOneWidget);
    expect(find.text('本次 1 张'), findsOneWidget);
    expect(find.text('NEW_1.JPG'), findsOneWidget);
    expect(find.text('NEW_2.JPG'), findsNothing);

    await tester.tap(find.byTooltip('添入此境'));
    await _pumpUi(tester);

    expect(
      controller.workspace.assets,
      hasLength(noemaWorkspaceHardPhotoLimit),
    );
  });

  testWidgets('cancel after photos keeps the current import state calm', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    var calls = 0;

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async {
            calls += 1;
            if (calls == 1) {
              return [_asset('asset-1', 'IMG_1.JPG')];
            }
            return const [];
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);
    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('IMG_1.JPG'), findsOneWidget);

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('IMG_1.JPG'), findsOneWidget);
    expect(find.text('还没有选择照片'), findsNothing);
  });

  testWidgets('picked photos appear in row-sized batches while preparing', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [
            for (var index = 1; index <= 9; index++)
              _asset('asset-$index', 'IMG_$index.JPG'),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在打开相册'), findsOneWidget);
    expect(find.text('4 张'), findsOneWidget);
    expect(find.text('IMG_4.JPG'), findsOneWidget);
    expect(find.text('IMG_5.JPG'), findsNothing);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    expect(find.text('8 张'), findsOneWidget);
    expect(find.text('IMG_8.JPG'), findsOneWidget);
    expect(find.text('IMG_9.JPG'), findsNothing);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    expect(find.text('9 张'), findsOneWidget);
    expect(find.text('IMG_9.JPG'), findsOneWidget);
  });

  testWidgets('Android thumbnail hydration uses bounded parallel work', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final thumbnailCompleters = <Completer<String?>>[];
    final thumbnailCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      if (call.method != 'createThumbnail') {
        return Future<Object?>.value(null);
      }

      thumbnailCalls.add(call);
      final completer = Completer<String?>();
      thumbnailCompleters.add(completer);
      return completer.future;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [
            for (var index = 1; index <= 5; index++) _androidAsset(index),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(find.text('正在带入照片'), findsOneWidget);
    expect(thumbnailCompleters.length, 3);
    expect(
      thumbnailCalls.map((call) => call.arguments['maxSize']),
      everyElement(320),
    );

    thumbnailCompleters[0].complete('/cache/thumb-1.jpg');
    thumbnailCompleters[1].complete('/cache/thumb-2.jpg');
    thumbnailCompleters[2].complete('/cache/thumb-3.jpg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(thumbnailCompleters.length, 5);

    thumbnailCompleters[3].complete('/cache/thumb-4.jpg');
    thumbnailCompleters[4].complete('/cache/thumb-5.jpg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('正在带入照片'), findsNothing);
  });

  testWidgets('Android thumbnail hydration skips duplicate picker results', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final thumbnailCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      if (call.method != 'createThumbnail') {
        return Future<Object?>.value(null);
      }

      thumbnailCalls.add(call);
      return Future<Object?>.value('/cache/${thumbnailCalls.length}.jpg');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [
            _androidAsset(1),
            _androidAsset(1),
            _androidAsset(2),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);
    await _pumpImportHydration(tester);

    expect(find.text('2 张'), findsOneWidget);
    expect(find.text('已略过重复照片'), findsOneWidget);
    expect(thumbnailCalls.map((call) => call.arguments['uri']), [
      'content://media/photo/1',
      'content://media/photo/2',
    ]);
  });

  testWidgets('Android metadata hydration updates assets after first paint', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final metadataCompleter = Completer<Map<String, Object?>>();
    final metadataCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      if (call.method == 'loadMetadata') {
        metadataCalls.add(call);
        return metadataCompleter.future;
      }
      if (call.method == 'createThumbnail') {
        return Future<Object?>.value(null);
      }
      return Future<Object?>.value(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => const [
            SelectedGalleryAsset(
              id: 'content://media/photo/1',
              name: 'photo',
              sourceUri: 'content://media/photo/1',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(find.text('正在带入照片'), findsOneWidget);
    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('photo'), findsOneWidget);
    expect(metadataCalls.map((call) => call.arguments['uri']), [
      'content://media/photo/1',
    ]);

    metadataCompleter.complete({
      'uri': 'content://media/photo/1',
      'name': 'IMG_REAL.JPG',
      'width': 4032,
      'height': 3024,
      'takenAtMillis': 1767225600000,
      'modifiedAtMillis': 1767225660000,
      'mimeType': 'image/jpeg',
      'fileSize': 3456789,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('正在带入照片'), findsNothing);
    expect(find.text('IMG_REAL.JPG'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '日本');
    await _pumpUi(tester);
    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);

    final photo = controller.workspace.assets.single.photo;
    expect(photo.width, 4032);
    expect(photo.height, 3024);
    expect(photo.createdAt, DateTime.fromMillisecondsSinceEpoch(1767225600000));
    expect(photo.mimeType, 'image/jpeg');
    expect(photo.fileSize, 3456789);
  });

  testWidgets(
    'Android thumbnail hydration feeds visual near-duplicate groups',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'noema-import-analysis-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final thumbnail = File('${tempDir.path}/duplicate.png');
      thumbnail.writeAsBytesSync(_checkerPng(inverted: false));

      const channel = MethodChannel(noemaMediaPickerChannelName);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) {
        final uri = call.arguments['uri'] as String?;
        if (call.method == 'loadMetadata') {
          final suffix = uri?.split('/').last ?? '1';
          final index = int.tryParse(suffix) ?? 1;
          return Future<Object?>.value({
            'uri': uri,
            'name': 'IMG_$index.JPG',
            'width': 32,
            'height': 32,
            'takenAtMillis': 1767225600000 + index * 60000,
            'mimeType': 'image/png',
            'fileSize': thumbnail.lengthSync(),
          });
        }
        if (call.method == 'createThumbnail') {
          return Future<Object?>.value(thumbnail.path);
        }
        return Future<Object?>.value(null);
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final controller = ReviewWorkspaceController();
      await tester.pumpWidget(
        _TestApp(
          controller: controller,
          importScreen: ImportScreen(
            workspaceController: controller,
            pickAssets: (_) async => [_androidAsset(1), _androidAsset(2)],
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加照片'));
      await _pumpUi(tester);
      await _pumpImportHydration(tester);
      await tester.enterText(find.byType(TextField), '重复测试');
      await _pumpUi(tester);

      expect(find.byTooltip('创建境'), findsOneWidget);
      await tester.tap(find.byTooltip('创建境'));
      await _pumpUi(tester);

      expect(controller.workspace.assets, hasLength(2));
      expect(
        controller.workspace.analysisResults.every(
          (result) => result.similarityHash != 0,
        ),
        isTrue,
      );
      expect(controller.workspace.groups, hasLength(1));
      expect(
        controller.workspace.groups.single.groupReason,
        GroupReason.nearDuplicate,
      );
      expect(controller.workspace.groups.single.photoIds, [
        'photo-1',
        'photo-2',
      ]);
    },
  );

  testWidgets('import grid thumbnails decode near their display size', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [
            _asset('asset-1', 'IMG_1.JPG', 'https://example.com/IMG_1.JPG'),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(ColorFiltered),
        matching: find.byType(Image),
      ),
    );
    expect(
      image.image,
      isA<ResizeImage>()
          .having((provider) => provider.width, 'width', isNotNull)
          .having((provider) => provider.height, 'height', isNotNull),
    );
    expect(image.filterQuality, FilterQuality.low);
  });

  testWidgets('import grid uses scene edge fades', (tester) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [_asset('asset-1')],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.byType(NoemaScrollEdgeFade), findsNWidgets(2));
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.clipBehavior, Clip.hardEdge);
  });

  testWidgets('name and photos are required before creating a space', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [_asset('asset-1')],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.byTooltip('创建境'), findsOneWidget);

    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);
    expect(find.text('先为境命名'), findsOneWidget);
    expect(find.text('写下一个名字后再创建'), findsNothing);
    expect(find.text('为境命名'), findsOneWidget);
    final hintRect = tester.getRect(find.text('先为境命名'));
    final actionRect = tester.getRect(
      find.byKey(const ValueKey('create-jing-action-anchor')),
    );
    expect(hintRect.center.dx, closeTo(actionRect.center.dx, 1));
    expect(actionRect.top - hintRect.bottom, greaterThanOrEqualTo(18));

    await tester.enterText(find.byType(TextField), '东京婚礼');
    await _pumpUi(tester);
    expect(find.text('先为境命名'), findsNothing);
    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);

    expect(find.text('东京婚礼'), findsWidgets);
    expect(find.text('赏'), findsOneWidget);
    expect(find.text('甄'), findsOneWidget);
    expect(find.text('鉴'), findsOneWidget);
    expect(controller.workspace.session.name, '东京婚礼');
    expect(controller.workspace.assets.length, 1);
  });

  testWidgets('append mode keeps current space name and adds only new photos', (
    tester,
  ) async {
    final controller = _sampleWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          appendMode: true,
          pickAssets: (_) async => [_asset('asset-new', 'NEW.JPG')],
        ),
      ),
    );

    expect(find.text('友人'), findsOneWidget);
    expect(find.text('18 张已在此境'), findsOneWidget);
    expect(find.text('为境命名'), findsNothing);

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('添入此境'), findsOneWidget);
    expect(find.text('本次 1 张'), findsOneWidget);
    expect(find.byTooltip('添入此境'), findsOneWidget);

    await tester.tap(find.byTooltip('添入此境'));
    await _pumpUi(tester);

    expect(controller.workspace.session.name, '友人');
    expect(controller.workspace.assets.length, 19);
    expect(find.text('19 张'), findsOneWidget);
  });

  testWidgets('tap previews a photo and close returns to the grid', (
    tester,
  ) async {
    final controller = _sampleWorkspaceController();
    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        importScreen: ImportScreen(
          workspaceController: controller,
          pickAssets: (_) async => [_asset('asset-1')],
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    await tester.tap(find.text('IMG_1.JPG'));
    await _pumpUi(tester);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await _pumpUi(tester);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.text('IMG_1.JPG'), findsOneWidget);
  });

  testWidgets(
    'long press selects multiple photos and removes them from import',
    (tester) async {
      final controller = ReviewWorkspaceController();
      await tester.pumpWidget(
        _TestApp(
          controller: controller,
          importScreen: ImportScreen(
            workspaceController: controller,
            pickAssets: (_) async => [_asset('asset-1'), _asset('asset-2')],
          ),
        ),
      );

      await tester.tap(find.byTooltip('添加照片'));
      await _pumpUi(tester);

      await tester.longPress(find.text('IMG_1.JPG'));
      await _pumpUi(tester);
      expect(find.text('已选 1 张'), findsNothing);
      expect(find.text('让照片入境'), findsNothing);
      expect(find.byTooltip('取消'), findsOneWidget);
      expect(find.byTooltip('移除'), findsOneWidget);

      await tester.tap(find.byTooltip('移除').first);
      await _pumpUi(tester);
      expect(find.text('从此境移除'), findsOneWidget);
      expect(find.text('原照片仍在系统相册中'), findsOneWidget);
      final dialogSize = tester.getSize(
        find.byKey(const ValueKey('remove-dialog-panel')),
      );
      expect(dialogSize.width, lessThanOrEqualTo(342));

      await tester.tap(find.byTooltip('移除').last);
      await _pumpUi(tester);

      expect(find.text('1 张'), findsOneWidget);
      expect(find.text('IMG_1.JPG'), findsNothing);
      expect(find.text('IMG_2.JPG'), findsOneWidget);
    },
  );

  testWidgets('invalid processing count falls back safely', (tester) async {
    final controller = _sampleWorkspaceController();
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: _supportedLocales,
        routerConfig: GoRouter(
          initialLocation: '${NoemaRoutes.processing}?count=abc',
          routes: [
            GoRoute(
              path: NoemaRoutes.processing,
              builder: (context, state) => ProcessingScreen(
                workspaceController: controller,
                selectedCount: parseSelectedCount(
                  state.uri.queryParameters['count'],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('友人'), findsOneWidget);
    expect(find.text('18 张'), findsOneWidget);
  });

  testWidgets('negative processing count falls back safely', (tester) async {
    final controller = _sampleWorkspaceController();
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: _supportedLocales,
        routerConfig: GoRouter(
          initialLocation: '${NoemaRoutes.processing}?count=-1',
          routes: [
            GoRoute(
              path: NoemaRoutes.processing,
              builder: (context, state) => ProcessingScreen(
                workspaceController: controller,
                selectedCount: parseSelectedCount(
                  state.uri.queryParameters['count'],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('友人'), findsOneWidget);
    expect(find.text('18 张'), findsOneWidget);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 360));
}

Future<void> _pumpImportHydration(WidgetTester tester) async {
  for (var index = 0; index < 20; index += 1) {
    await tester.pump(const Duration(milliseconds: 80));
    if (find.text('正在带入照片').evaluate().isEmpty) {
      return;
    }
  }
}

SelectedGalleryAsset _asset(String id, [String? name, String? thumbnailPath]) {
  return SelectedGalleryAsset(
    id: id,
    name: name ?? 'IMG_${id.split('-').last}.JPG',
    thumbnailPath: thumbnailPath,
  );
}

SelectedGalleryAsset _androidAsset(int index) {
  return SelectedGalleryAsset(
    id: 'content://media/photo/$index',
    name: 'IMG_$index.JPG',
    sourceUri: 'content://media/photo/$index',
  );
}

Uint8List _checkerPng({required bool inverted}) {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      final light = ((x ~/ 4 + y ~/ 4) % 2 == 0) ^ inverted;
      image.setPixel(
        x,
        y,
        light ? img.ColorRgb8(240, 240, 240) : img.ColorRgb8(24, 24, 24),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

ReviewWorkspaceController _sampleWorkspaceController() {
  final controller = ReviewWorkspaceController();
  controller.loadSelectedAssets(
    List.generate(
      18,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
      ),
    ),
    name: '友人',
  );
  return controller;
}

const _supportedLocales = [Locale('zh'), Locale('en')];
const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.controller,
    required this.importScreen,
    this.locale = const Locale('zh'),
  });

  final ReviewWorkspaceController controller;
  final ImportScreen importScreen;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      locale: locale,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _supportedLocales,
      routerConfig: GoRouter(
        initialLocation: NoemaRoutes.import,
        routes: [
          GoRoute(
            path: NoemaRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: NoemaRoutes.import,
            builder: (context, state) => importScreen,
          ),
          GoRoute(
            path: NoemaRoutes.observe,
            builder: (context, state) => ProcessingScreen(
              workspaceController: controller,
              selectedCount: parseSelectedCount(
                state.uri.queryParameters['count'],
              ),
            ),
          ),
          GoRoute(
            path: NoemaRoutes.processing,
            builder: (context, state) => ProcessingScreen(
              workspaceController: controller,
              selectedCount: parseSelectedCount(
                state.uri.queryParameters['count'],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
